-- LOCAL ONLY: run after the migration against disposable Supabase fixtures.
-- Example: psql LOCAL_URL -v club_id=... -v profile_id=... -v other_club_id=...
--   -f supabase/tests/dashboard_indicator_details.sql
-- Run for a financial manager, a member, and custom-permission users. The club
-- fixtures should include >100 rows, boundary dates, inactive accounts/products,
-- mixed BAR/inventory areas, private/sensitive documents and different requester
-- and beneficiary profiles. Manager fixtures must include two low-stock products
-- with the same name (IDs break ties) and a pending request created by a different
-- financial manager, including one without a members row if possible.
-- No production execution is authorized.
-- All settings are transaction-local; this script writes no application records.
\set ON_ERROR_STOP on
begin;
select set_config('request.jwt.claim.sub', :'profile_id', true);
select set_config('request.jwt.claims',
  json_build_object('sub', :'profile_id', 'role','authenticated')::text, true);
select set_config('dashboard_test.club', :'club_id', true);
select set_config('dashboard_test.other_club', :'other_club_id', true);

do $$
declare
  target uuid := current_setting('dashboard_test.club')::uuid;
  other_club uuid := current_setting('dashboard_test.other_club')::uuid;
  indicators text[] := array[
    'members','prospects','total_balance','fee_outstanding',
    'open_events','low_stock','expiring_documents','pending_approvals'
  ];
  indicator text;
  expected jsonb := '{}'::jsonb;
  ids jsonb;
  raw_ids jsonb;
  money numeric;
  summary jsonb;
  detail jsonb;
  page_cursor jsonb;
  previous_cursor jsonb;
  page_limit integer;
  page_ids jsonb;
  page_number integer;
  tie_checked boolean := false;
  stock_detail_authorized boolean := false;
  requester_test_request uuid;
  requester_test_name text;
  candidate record;
  fixture_user uuid := auth.uid();
  expected_requesters jsonb;
  other_profile uuid;
  foreign_request uuid;
  actual_ids jsonb;
  rejected boolean;
begin
  if not public.has_club_access(target) then
    raise exception 'Fixture profile must belong to target club.';
  end if;
  if public.has_club_access(other_club) then
    raise exception 'Fixture profile must NOT belong to other club.';
  end if;
  if has_function_privilege('anon',
      'public.dashboard_indicator_details_v1(uuid,text,integer,jsonb)','execute')
    or has_function_privilege('anon',
      'public.dashboard_summary_rc1(uuid)','execute') then
    raise exception 'Anonymous execution must be revoked.';
  end if;
  if (select p.prosecdef from pg_proc p where p.oid =
      'public.dashboard_indicator_details_v1(uuid,text,integer,jsonb)'::regprocedure)
    or (select p.prosecdef from pg_proc p where p.oid =
      'bob_dashboard_private.indicator_rows_v1(uuid,text)'::regprocedure) then
    raise exception 'Detail and row helper must remain SECURITY INVOKER.';
  end if;

  if has_schema_privilege('authenticated','bob_dashboard_private','CREATE') then
    raise exception 'authenticated must not CREATE in the private schema.';
  end if;
  if has_function_privilege('anon',
      'bob_dashboard_private.approval_requester_name_v1(uuid,uuid)','execute') then
    raise exception 'Anonymous requester lookup must be revoked.';
  end if;

  select coalesce(jsonb_object_agg(r.id::text,jsonb_build_object(
    'requested_by',r.requested_by,'name',nullif(btrim(p.full_name),'')
  )),'{}'::jsonb) into expected_requesters
  from public.financial_requests r
  left join public.profiles p on p.id = r.requested_by
  where r.club_id = target and r.status in ('pending_review','awaiting_validation');
  select p.id into other_profile from public.profiles p
  where p.id <> fixture_user and not exists (
    select 1 from public.financial_requests r where r.id = p.id
  ) order by p.id limit 1;
  select r.id into foreign_request from public.financial_requests r
  where r.club_id = other_club order by r.id limit 1;

  if public.financial_manager_v1(target) then
    -- Prove resolution for a different authorized requester, not just self.
    for candidate in
      select r.id,r.requested_by,nullif(btrim(p.full_name),'') as name
      from public.financial_requests r
      join public.profiles p on p.id = r.requested_by
      where r.club_id = target and r.status in ('pending_review','awaiting_validation')
        and r.requested_by <> fixture_user and nullif(btrim(p.full_name),'') is not null
      order by r.id
    loop
      perform set_config('request.jwt.claim.sub',candidate.requested_by::text,true);
      perform set_config('request.jwt.claims',jsonb_build_object(
        'sub',candidate.requested_by,'role','authenticated'
      )::text,true);
      if public.financial_manager_v1(target) then
        requester_test_request := candidate.id;
        requester_test_name := candidate.name;
        exit;
      end if;
    end loop;
    perform set_config('request.jwt.claim.sub',fixture_user::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object(
      'sub',fixture_user,'role','authenticated'
    )::text,true);
    if requester_test_request is null then
      raise exception 'Manager fixture needs a request created by another authorized manager.';
    end if;
    if not exists (
      select 1 from public.products p where p.club_id = target and p.active = true
        and p.current_stock-p.reserved_stock <= p.minimum_stock
      group by p.name having count(*) > 1
    ) then
      raise exception 'Manager fixture needs low-stock products with equal names.';
    end if;
  end if;

  -- As the local test owner, collect the full expected set in memory only.
  foreach indicator in array indicators loop
    if indicator = 'pending_approvals' and not public.financial_manager_v1(target) then
      -- The name helper correctly refuses even owner-invoked lookups when the
      -- authenticated subject lacks the approval permission.
      ids := null;
      money := 0;
    else
      select coalesce(jsonb_agg(r.id order by
        r.sort_number asc nulls last, r.sort_date asc nulls last,
        r.sort_time asc nulls last, r.sort_text asc nulls last, r.id asc
      ),'[]'::jsonb), coalesce(sum(r.monetary_value),0)
      into ids,money
      from bob_dashboard_private.indicator_rows_v1(target,indicator) r;
    end if;
    -- Independent expectations protect against a shared helper/resume mistake.
    case indicator
      when 'members' then
        select coalesce(jsonb_agg(m.id order by m.member_number asc nulls last,m.full_name asc,m.id asc),'[]'::jsonb) into raw_ids
        from public.members m where m.club_id = target
          and m.status::text not in ('prospect','former','deceased');
      when 'prospects' then
        select coalesce(jsonb_agg(m.id order by m.member_number asc nulls last,m.full_name asc,m.id asc),'[]'::jsonb) into raw_ids
        from public.members m where m.club_id = target and m.status::text = 'prospect';
      when 'total_balance' then
        select coalesce(jsonb_agg(a.id order by a.name asc,a.id asc),'[]'::jsonb) into raw_ids
        from public.treasury_accounts a where a.club_id = target and a.active = true;
      when 'fee_outstanding' then
        select coalesce(jsonb_agg(f.id order by
          f.due_date asc nulls last,m.full_name asc,f.id asc
        ),'[]'::jsonb) into raw_ids
        from public.fee_obligations f
        left join public.members m on m.id = f.member_id and m.club_id = f.club_id
        where f.club_id = target
          and greatest(f.amount-f.paid_amount,0) > 0;
      when 'open_events' then
        select coalesce(jsonb_agg(e.id order by e.starts_at asc,e.name asc,e.id asc),'[]'::jsonb) into raw_ids
        from public.events e where e.club_id = target
          and e.status::text not in ('completed','cancelled','archived');
      when 'low_stock' then
        select coalesce(jsonb_agg(p.id order by p.name asc,p.id asc),'[]'::jsonb) into raw_ids
        from public.products p where p.club_id = target and p.active = true
          and p.current_stock-p.reserved_stock <= p.minimum_stock;
      when 'expiring_documents' then
        select coalesce(jsonb_agg(d.id order by d.expires_at asc,d.name asc,d.id asc),'[]'::jsonb) into raw_ids
        from public.documents d where d.club_id = target
          and d.expires_at between current_date and current_date+30;
      when 'pending_approvals' then
        select coalesce(jsonb_agg(r.id order by r.created_at asc,r.id asc),'[]'::jsonb) into raw_ids
        from public.financial_requests r where r.club_id = target
          and r.status in ('pending_review','awaiting_validation');
    end case;
    if ids is null then ids := raw_ids; end if;
    if ids <> raw_ids then
      raise exception 'Shared criterion returned the wrong set: %',indicator;
    end if;
    expected := expected || jsonb_build_object(indicator,
      jsonb_build_object('ids',ids,'money',money));
  end loop;

  -- Every RPC below runs as authenticated and is subject to the actual RLS.
  execute 'set local role authenticated';
  summary := public.dashboard_summary_rc1(target);
  if exists(select 1 from public.profiles p where p.id <> fixture_user) then
    raise exception 'Generic profile reads exposed other users despite RLS.';
  end if;
  if requester_test_request is not null then
    if bob_dashboard_private.approval_requester_name_v1(target,requester_test_request)
        is distinct from requester_test_name then
      raise exception 'Authorized lookup failed for another requester.';
    end if;
  end if;
  if other_profile is not null then
    rejected := false;
    begin
      perform bob_dashboard_private.approval_requester_name_v1(target,other_profile);
    exception when insufficient_privilege then rejected := true;
    end;
    if not rejected then raise exception 'Helper accepted a generic profile ID.'; end if;
  end if;
  rejected := false;
  begin
    perform bob_dashboard_private.approval_requester_name_v1(
      target,coalesce(foreign_request,'00000000-0000-0000-0000-000000000000'::uuid)
    );
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Helper accepted a request outside its club.'; end if;
  if not public.has_club_permission(target,'viewTreasury') then
    foreach indicator in array array[
      'total_balance','fee_outstanding','monthly_income','monthly_expense'
    ] loop
      if summary->indicator is distinct from 'null'::jsonb then
        raise exception 'Unauthorized financial field: %',indicator;
      end if;
    end loop;
  end if;

  foreach indicator in array indicators loop
    page_cursor := null;
    actual_ids := '[]'::jsonb;
    page_number := 0;
    -- Single-row stock pages place every equal-name pair across a boundary.
    page_limit := case when indicator = 'low_stock' then 1 else 17 end;
    loop
      detail := public.dashboard_indicator_details_v1(target,indicator,page_limit,page_cursor);
      page_number := page_number + 1;
      if not (detail->>'authorized')::boolean then
        if detail->'rows' <> '[]'::jsonb
          or detail->'total_rows' is distinct from 'null'::jsonb
          or detail->'monetary_total' is distinct from 'null'::jsonb
          or detail->'next_cursor' is distinct from 'null'::jsonb
          or (detail->>'complete')::boolean then
          raise exception 'Unauthorized detail returned data: %',indicator;
        end if;
        exit;
      end if;
      if indicator = 'low_stock' then stock_detail_authorized := true; end if;
      if not (detail->>'complete')::boolean then
        raise exception 'Partial detail was presented as authorized.';
      end if;
      if (detail->>'total_rows')::bigint <>
          jsonb_array_length(expected->indicator->'ids') then
        raise exception 'Wrong aggregate row count: %',indicator;
      end if;
      if indicator in ('total_balance','fee_outstanding') and (
        (detail->>'monetary_total')::numeric <>
          (expected->indicator->>'money')::numeric
        or detail->'monetary_total' <> summary->indicator
      ) then
        raise exception 'Wrong financial aggregate: %',indicator;
      end if;
      select coalesce(jsonb_agg(r.value->'id' order by r.ordinality),'[]'::jsonb)
      into page_ids
      from jsonb_array_elements(detail->'rows') with ordinality r(value,ordinality);
      if exists (
        select 1 from jsonb_array_elements_text(page_ids) p(id)
        where actual_ids ? p.id
      ) then
        raise exception 'Repeated ID between pages (including first/second): %',indicator;
      end if;
      if page_ids <> (
        select coalesce(jsonb_agg(e.value order by e.ordinality),'[]'::jsonb)
        from jsonb_array_elements(expected->indicator->'ids')
          with ordinality e(value,ordinality)
        where e.ordinality > jsonb_array_length(actual_ids)
          and e.ordinality <= jsonb_array_length(actual_ids) + page_limit
      ) then
        raise exception 'Page % has incorrect logical ordering: %',page_number,indicator;
      end if;
      if indicator = 'low_stock' and page_cursor is not null
        and page_cursor->>'text' is not distinct from detail->'rows'->0->>'name' then
        if (detail->'rows'->0->>'id')::uuid <= (page_cursor->>'id')::uuid then
          raise exception 'Equal-name boundary failed to use ID as final tie-breaker.';
        end if;
        tie_checked := true;
      end if;
      if indicator = 'pending_approvals' and exists (
        select 1 from jsonb_array_elements(detail->'rows') r
        where r->'requested_by' is distinct from
            expected_requesters->(r->>'id')->'requested_by'
          or r->'requester_name' is distinct from
            expected_requesters->(r->>'id')->'name'
          or (r->>'requester_name_missing')::boolean is distinct from
            ((expected_requesters->(r->>'id')->>'name') is null)
      ) then
        raise exception 'Requester identity/name was wrong or silently hidden by RLS.';
      end if;
      actual_ids := actual_ids || page_ids;
      if detail->>'next_cursor' is null then
        if actual_ids <> expected->indicator->'ids' then
          raise exception 'Pagination omitted, reordered or duplicated rows: %',indicator;
        end if;
        exit;
      end if;
      previous_cursor := page_cursor;
      page_cursor := detail->'next_cursor';
      if previous_cursor is not null and row(
        (page_cursor->>'number') is null, coalesce((page_cursor->>'number')::integer,0),
        (page_cursor->>'date') is null, coalesce((page_cursor->>'date')::date,'-infinity'::date),
        (page_cursor->>'time') is null, coalesce((page_cursor->>'time')::timestamptz,'-infinity'::timestamptz),
        (page_cursor->>'text') is null, coalesce(page_cursor->>'text',''), (page_cursor->>'id')::uuid
      ) <= row(
        (previous_cursor->>'number') is null, coalesce((previous_cursor->>'number')::integer,0),
        (previous_cursor->>'date') is null, coalesce((previous_cursor->>'date')::date,'-infinity'::date),
        (previous_cursor->>'time') is null, coalesce((previous_cursor->>'time')::timestamptz,'-infinity'::timestamptz),
        (previous_cursor->>'text') is null, coalesce(previous_cursor->>'text',''), (previous_cursor->>'id')::uuid
      ) then
        raise exception 'Composite cursor did not advance: %',indicator;
      end if;
    end loop;
    if indicator in ('total_balance','fee_outstanding')
      and not public.has_club_permission(target,'viewTreasury')
      and (detail->>'authorized')::boolean then
      raise exception 'Direct unauthorized financial RPC was allowed.';
    end if;
    if indicator = 'fee_outstanding'
      and not public.has_club_permission(target,'manageFees')
      and (detail->>'authorized')::boolean then
      raise exception 'viewTreasury incorrectly granted access to all fees.';
    end if;
    if indicator = 'pending_approvals'
      and not public.financial_manager_v1(target)
      and (detail->>'authorized')::boolean then
      raise exception 'Own requests incorrectly granted approval access.';
    end if;
  end loop;

  if stock_detail_authorized and public.financial_manager_v1(target) and not tie_checked then
    raise exception 'Equal-name stock pagination test was not exercised.';
  end if;
  rejected := false;
  begin
    perform public.dashboard_indicator_details_v1(target,'members',50,
      jsonb_build_object('v',1,'club_id',other_club,'indicator','members',
        'number',null,'date',null,'time',null,'text',null,
        'id','00000000-0000-0000-0000-000000000001')
    );
  exception when invalid_parameter_value then rejected := true;
  end;
  if not rejected then raise exception 'Cross-club cursor was accepted.'; end if;
  rejected := false;
  begin
    perform public.dashboard_indicator_details_v1(other_club,'members',50,null);
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Cross-club RPC was not rejected.'; end if;
  rejected := false;
  begin
    perform public.dashboard_summary_rc1(other_club);
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Cross-club summary was not rejected.'; end if;

  rejected := false;
  begin
    perform public.dashboard_indicator_details_v1(target,'unknown',50,null);
  exception when invalid_parameter_value then rejected := true;
  end;
  if not rejected then raise exception 'Unknown indicator was accepted.'; end if;
  rejected := false;
  begin
    perform public.dashboard_indicator_details_v1(target,'members',101,null);
  exception when invalid_parameter_value then rejected := true;
  end;
  if not rejected then raise exception 'Invalid page size was accepted.'; end if;

  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  rejected := false;
  begin
    perform public.dashboard_indicator_details_v1(target,'members',50,null);
  exception when insufficient_privilege then rejected := true;
  end;
  if not rejected then raise exception 'Missing authentication was accepted.'; end if;
  raise notice 'Dashboard SQL checks passed for this fixture profile.';
end;
$$;
rollback;
