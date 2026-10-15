-- Dashboard criteria are shared by the privileged aggregate and the invoker
-- drill-down. No table, policy, existing record or module permission is changed.
-- Never add bob_dashboard_private to PostgREST's exposed schemas.
-- authenticated needs USAGE and the specific EXECUTE grants below because the
-- public detail RPC is SECURITY INVOKER. It must never be able to CREATE here.
-- indicator_rows_v1 also remains INVOKER: direct calls retain the caller's RLS.
-- The sole DEFINER exception resolves one approval requester's name, with its
-- own strict authorization; it provides no generic profile lookup.
create schema if not exists bob_dashboard_private;
revoke all on schema bob_dashboard_private from public, anon;
revoke create on schema bob_dashboard_private from authenticated;
grant usage on schema bob_dashboard_private to authenticated;

-- A manager can create a reimbursement for another member while requested_by
-- records the manager, who need not have a members row. Therefore a members-only
-- fallback cannot reliably identify the requester. Keep profiles RLS unchanged.
create or replace function bob_dashboard_private.approval_requester_name_v1(
  target_club uuid, p_request uuid
)
returns text
language plpgsql stable security definer set search_path = public
as $$
declare
  requester uuid;
  requester_name text;
begin
  if auth.uid() is null
    or not public.has_club_access(target_club)
    or not public.financial_manager_v1(target_club) then
    raise exception 'Sem autorização para consultar aprovações.' using errcode = '42501';
  end if;
  -- Accept a request ID, never an arbitrary profile ID. Only the pending
  -- approval context of this club can legitimize access to this single name.
  select r.requested_by into requester
  from public.financial_requests r
  where r.club_id = target_club and r.id = p_request
    and r.status in ('pending_review','awaiting_validation');
  if not found then
    raise exception 'Pedido não acessível neste contexto.' using errcode = '42501';
  end if;
  if requester is null then return null; end if;
  select nullif(btrim(p.full_name),'') into requester_name
  from public.profiles p where p.id = requester;
  return requester_name;
end;
$$;
revoke all on function bob_dashboard_private.approval_requester_name_v1(uuid,uuid)
  from public, anon;
grant execute on function bob_dashboard_private.approval_requester_name_v1(uuid,uuid)
  to authenticated;

create or replace function bob_dashboard_private.indicator_rows_v1(
  target_club uuid, p_indicator text
)
returns table(
  id uuid, row_data jsonb, monetary_value numeric,
  sort_number integer, sort_date date, sort_time timestamptz, sort_text text
)
language plpgsql stable security invoker set search_path = public
as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.' using errcode = '42501';
  end if;

  case p_indicator
    when 'members', 'prospects' then
      return query
      select m.id, jsonb_build_object(
        'id', m.id, 'member_number', m.member_number,
        'full_name', m.full_name, 'nickname', m.nickname
      ), null::numeric, m.member_number, null::date, null::timestamptz, m.full_name
      from public.members m
      where m.club_id = target_club and (
        (p_indicator = 'members' and
          m.status::text not in ('prospect','former','deceased')) or
        (p_indicator = 'prospects' and m.status::text = 'prospect')
      );
    when 'total_balance' then
      return query
      select a.id, jsonb_build_object(
        'id', a.id, 'name', a.name, 'balance', b.balance
      ), b.balance, null::integer, null::date, null::timestamptz, a.name
      from public.treasury_accounts a
      cross join lateral (
        select a.opening_balance
          + coalesce((select sum(case
              when t.kind::text = 'income' then t.amount
              when t.kind::text in ('expense','transfer') then -t.amount
              else 0 end)
            from public.treasury_transactions t
            where t.club_id = target_club and t.account_id = a.id), 0)
          + coalesce((select sum(t.amount)
            from public.treasury_transactions t
            where t.club_id = target_club and t.kind::text = 'transfer'
              and t.destination_account_id = a.id), 0) as balance
      ) b
      where a.club_id = target_club and a.active = true;
    when 'fee_outstanding' then
      return query
      select f.id, jsonb_build_object(
        'id', f.id, 'member_name', m.full_name,
        'outstanding', greatest(f.amount - f.paid_amount, 0),
        'due_date', f.due_date
      ), greatest(f.amount - f.paid_amount, 0),
      null::integer, f.due_date, null::timestamptz, m.full_name
      from public.fee_obligations f
      left join public.members m on m.id = f.member_id and m.club_id = f.club_id
      where f.club_id = target_club and greatest(f.amount - f.paid_amount, 0) > 0;
    when 'open_events' then
      return query
      select e.id, jsonb_build_object(
        'id', e.id, 'name', e.name, 'starts_at', e.starts_at, 'status', e.status
      ), null::numeric, null::integer, null::date, e.starts_at, e.name
      from public.events e
      where e.club_id = target_club
        and e.status::text not in ('completed','cancelled','archived');
    when 'low_stock' then
      return query
      select p.id, jsonb_build_object(
        'id', p.id, 'name', p.name, 'current_stock', p.current_stock,
        'reserved_stock', p.reserved_stock,
        'available_stock', p.current_stock - p.reserved_stock,
        'minimum_stock', p.minimum_stock
      ), null::numeric, null::integer, null::date, null::timestamptz, p.name
      from public.products p
      where p.club_id = target_club and p.active = true
        and p.current_stock - p.reserved_stock <= p.minimum_stock;
    when 'expiring_documents' then
      return query
      select d.id, jsonb_build_object(
        'id', d.id, 'name', d.name, 'expires_at', d.expires_at
      ), null::numeric, null::integer, d.expires_at, null::timestamptz, d.name
      from public.documents d
      where d.club_id = target_club
        and d.expires_at between current_date and current_date + 30;
    when 'pending_approvals' then
      if not public.financial_manager_v1(target_club) then
        raise exception 'Sem autorização para consultar aprovações.' using errcode = '42501';
      end if;
      return query
      select r.id, jsonb_build_object(
        'id', r.id, 'request_type', r.request_type,
        'description', r.description, 'amount', r.amount,
        'requested_by', r.requested_by,
        'requester_name', requester.name,
        -- A missing name is real missing/blank data, never a silent RLS omission.
        'requester_name_missing', requester.name is null,
        'status', r.status
      ), null::numeric, null::integer, null::date, r.created_at, null::text
      from public.financial_requests r
      cross join lateral (
        select bob_dashboard_private.approval_requester_name_v1(target_club,r.id) as name
      ) requester
      where r.club_id = target_club
        and r.status in ('pending_review','awaiting_validation');
    else
      raise exception 'Indicador desconhecido.' using errcode = '22023';
  end case;
end;
$$;
revoke all on function bob_dashboard_private.indicator_rows_v1(uuid,text)
  from public, anon;
grant execute on function bob_dashboard_private.indicator_rows_v1(uuid,text)
  to authenticated;

create or replace function public.dashboard_summary_rc1(target_club uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  can_financial boolean;
  can_approve boolean;
  indicator text;
  row_count bigint;
  monetary_total numeric;
  result jsonb := '{}'::jsonb;
  counts jsonb := '{}'::jsonb;
  overdue_count bigint;
  unread_count bigint;
  monthly_income numeric;
  monthly_expense numeric;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.' using errcode = '42501';
  end if;
  can_financial := public.has_club_permission(target_club,'viewTreasury');
  can_approve := public.financial_manager_v1(target_club);

  foreach indicator in array array[
    'members','prospects','total_balance','fee_outstanding',
    'open_events','low_stock','expiring_documents','pending_approvals'
  ] loop
    if indicator in ('total_balance','fee_outstanding') and not can_financial then
      -- NULL, never real financial amounts (including a direct RPC call).
      result := result || jsonb_build_object(indicator, null);
      counts := counts || jsonb_build_object(indicator, null);
    elsif indicator = 'pending_approvals' and not can_approve then
      result := result || jsonb_build_object(indicator, 0);
      counts := counts || jsonb_build_object(indicator, 0);
    else
      select count(*), coalesce(sum(r.monetary_value),0)
      into row_count, monetary_total
      from bob_dashboard_private.indicator_rows_v1(target_club,indicator) r;
      result := result || jsonb_build_object(indicator,
        case when indicator in ('total_balance','fee_outstanding')
          then to_jsonb(monetary_total) else to_jsonb(row_count) end);
      counts := counts || jsonb_build_object(indicator,row_count);
    end if;
  end loop;

  -- Preserve the existing non-monetary overdue alert; use the shared pending
  -- obligation set and date-only boundary rather than another balance formula.
  select count(*) into overdue_count
  from bob_dashboard_private.indicator_rows_v1(target_club,'fee_outstanding') r
  where (r.row_data->>'due_date')::date < current_date;

  select count(*) into unread_count from public.announcements a
  where a.club_id = target_club and a.requires_acknowledgement = true
    and a.published_at <= now() and (a.expires_at is null or a.expires_at > now())
    and not exists (
      select 1 from public.announcement_acknowledgements aa
      where aa.announcement_id = a.id and aa.profile_id = auth.uid()
    );
  if can_financial then
    select coalesce(sum(t.amount) filter(where t.kind::text = 'income'),0),
           coalesce(sum(t.amount) filter(where t.kind::text = 'expense'),0)
    into monthly_income,monthly_expense
    from public.treasury_transactions t
    where t.club_id = target_club
      and date_trunc('month',t.transaction_date::timestamp)
        = date_trunc('month',current_date::timestamp);
  end if;
  return result || jsonb_build_object(
    'can_view_financial',can_financial, 'indicator_row_counts',counts,
    'overdue_fees',overdue_count, 'unread_announcements',unread_count,
    'monthly_income',monthly_income, 'monthly_expense',monthly_expense
  );
end;
$$;
revoke all on function public.dashboard_summary_rc1(uuid) from public, anon;
grant execute on function public.dashboard_summary_rc1(uuid) to authenticated;

create or replace function public.dashboard_indicator_details_v1(
  target_club uuid,
  p_indicator text,
  p_limit integer default 50,
  p_cursor jsonb default null
)
returns jsonb
language plpgsql stable security invoker set search_path = public
as $$
declare
  allowed boolean;
  aggregate_summary jsonb;
  expected_count bigint;
  expected_money numeric;
  visible_count bigint;
  visible_money numeric;
  page_rows jsonb;
  cursor_value jsonb;
  cursor_id uuid;
  cursor_number integer;
  cursor_date date;
  cursor_time timestamptz;
  cursor_text text;
  denied jsonb;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.' using errcode = '42501';
  end if;
  if p_indicator is null or p_indicator not in (
    'members','prospects','total_balance','fee_outstanding',
    'open_events','low_stock','expiring_documents','pending_approvals'
  ) then
    raise exception 'Indicador desconhecido.' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'Limite deve estar entre 1 e 100.' using errcode = '22023';
  end if;


  -- A cursor is opaque to clients, not an authorization credential. All club,
  -- indicator and RLS checks are repeated for each page. No dynamic SQL/OFFSET.
  -- Include explicit JSON nulls: null ordering keys must not omit later rows.
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) is distinct from 'object'
      or not (p_cursor ?& array['v','club_id','indicator','number','date','time','text','id'])
      or (p_cursor - array['v','club_id','indicator','number','date','time','text','id']) <> '{}'::jsonb
      or p_cursor->'v' is distinct from '1'::jsonb
      or p_cursor->>'club_id' is distinct from target_club::text
      or p_cursor->>'indicator' is distinct from p_indicator
      or jsonb_typeof(p_cursor->'id') is distinct from 'string'
      or jsonb_typeof(p_cursor->'number') not in ('number','null')
      or jsonb_typeof(p_cursor->'date') not in ('string','null')
      or jsonb_typeof(p_cursor->'time') not in ('string','null')
      or jsonb_typeof(p_cursor->'text') not in ('string','null') then
      raise exception 'Cursor inválido para este indicador.' using errcode = '22023';
    end if;
    begin
      cursor_id := (p_cursor->>'id')::uuid;
      cursor_number := (p_cursor->>'number')::integer;
      cursor_date := (p_cursor->>'date')::date;
      cursor_time := (p_cursor->>'time')::timestamptz;
      cursor_text := p_cursor->>'text';
      if (p_indicator not in ('members','prospects') and cursor_number is not null)
        or (p_indicator not in ('fee_outstanding','expiring_documents') and cursor_date is not null)
        or (p_indicator not in ('open_events','pending_approvals') and cursor_time is not null)
        or (p_indicator = 'pending_approvals' and cursor_text is not null) then
        raise exception 'Cursor inválido para este indicador.' using errcode = '22023';
      end if;
    exception
      when invalid_text_representation or invalid_datetime_format
        or datetime_field_overflow or numeric_value_out_of_range then
        raise exception 'Cursor inválido para este indicador.' using errcode = '22023';
    end;
  end if;

  denied := jsonb_build_object(
    'indicator',p_indicator, 'authorized',false, 'complete',false,
    'rows','[]'::jsonb, 'total_rows',null, 'monetary_total',null,
    'next_cursor',null
  );
  allowed := case p_indicator
    when 'members' then public.has_club_permission(target_club,'viewMembers')
    when 'prospects' then public.has_club_permission(target_club,'viewMembers')
    when 'total_balance' then public.has_club_permission(target_club,'viewTreasury')
    when 'fee_outstanding' then
      public.has_club_permission(target_club,'viewTreasury')
      and public.has_club_permission(target_club,'manageFees')
    when 'open_events' then public.has_club_permission(target_club,'viewEvents')
    when 'low_stock' then
      public.has_club_permission(target_club,'viewInventory')
      or public.has_club_permission(target_club,'viewBar')
    when 'expiring_documents' then
      public.has_club_permission(target_club,'viewDocuments')
      or public.has_club_permission(target_club,'manageDocuments')
      or public.has_club_permission(target_club,'viewSensitiveDocuments')
    when 'pending_approvals' then public.financial_manager_v1(target_club)
    else false
  end;
  if not coalesce(allowed,false) then return denied; end if;

  -- The existing SECURITY DEFINER summary supplies aggregates only. It never
  -- supplies privileged rows to this RPC. The rows below remain SECURITY
  -- INVOKER and subject to the existing RLS. Compare BEFORE returning any page:
  -- matching money alone is insufficient (hidden balances can cancel out).
  -- STABLE functions share the invoking statement's MVCC snapshot.
  aggregate_summary := public.dashboard_summary_rc1(target_club);
  expected_count :=
    (aggregate_summary->'indicator_row_counts'->>p_indicator)::bigint;
  if p_indicator in ('total_balance','fee_outstanding') then
    expected_money := (aggregate_summary->>p_indicator)::numeric;
  end if;

  -- Unused keys are NULL for an indicator. This shared order implements:
  -- members/prospects: member_number NULLS LAST, full_name, id
  -- balance/stock: name, id; fees: due_date NULLS LAST, member_name, id
  -- events: starts_at, name, id; documents: expires_at, name, id
  -- approvals: created_at, id. ASC has explicit NULLS LAST throughout.
  -- Boolean null flags and neutral values make tuple comparison null-safe;
  -- the flags distinguish real zero/empty values from NULL. Text comparisons
  -- use the same database collation as ORDER BY. ID is always the final key.
  with source as materialized (
    select r.* from bob_dashboard_private.indicator_rows_v1(target_club,p_indicator) r
  ), page as (
    select s.* from source s
    where p_cursor is null or row(
      s.sort_number is null, coalesce(s.sort_number,0),
      s.sort_date is null, coalesce(s.sort_date,'-infinity'::date),
      s.sort_time is null, coalesce(s.sort_time,'-infinity'::timestamptz),
      s.sort_text is null, coalesce(s.sort_text,''), s.id
    ) > row(
      cursor_number is null, coalesce(cursor_number,0),
      cursor_date is null, coalesce(cursor_date,'-infinity'::date),
      cursor_time is null, coalesce(cursor_time,'-infinity'::timestamptz),
      cursor_text is null, coalesce(cursor_text,''), cursor_id
    )
    order by s.sort_number asc nulls last, s.sort_date asc nulls last,
      s.sort_time asc nulls last, s.sort_text asc nulls last, s.id asc
    limit p_limit + 1
  ), displayed as (
    select p.* from page p
    order by p.sort_number asc nulls last, p.sort_date asc nulls last,
      p.sort_time asc nulls last, p.sort_text asc nulls last, p.id asc
    limit p_limit
  )
  select
    (select count(*) from source),
    (select coalesce(sum(s.monetary_value),0) from source s),
    (select coalesce(jsonb_agg(d.row_data order by
      d.sort_number asc nulls last, d.sort_date asc nulls last,
      d.sort_time asc nulls last, d.sort_text asc nulls last, d.id asc
    ),'[]'::jsonb) from displayed d),
    case when (select count(*) from page) > p_limit then (
      select jsonb_build_object(
        'v',1, 'club_id',target_club, 'indicator',p_indicator,
        'number',d.sort_number, 'date',d.sort_date, 'time',d.sort_time,
        'text',d.sort_text, 'id',d.id
      )
      from displayed d
      -- Exact reverse of the forward order, including NULL placement.
      order by d.sort_number desc nulls first, d.sort_date desc nulls first,
        d.sort_time desc nulls first, d.sort_text desc nulls first, d.id desc
      limit 1
    ) else null end
  into visible_count,visible_money,page_rows,cursor_value;

  if visible_count is distinct from expected_count
    or (p_indicator in ('total_balance','fee_outstanding')
      and visible_money is distinct from expected_money) then
    return denied;
  end if;
  return jsonb_build_object(
    'indicator',p_indicator, 'authorized',true, 'complete',true,
    'rows',page_rows, 'total_rows',visible_count,
    'monetary_total',case when p_indicator in ('total_balance','fee_outstanding')
      then visible_money else null end,
    'next_cursor',cursor_value
  );
end;
$$;
revoke all on function public.dashboard_indicator_details_v1(uuid,text,integer,jsonb)
  from public, anon;
grant execute on function public.dashboard_indicator_details_v1(uuid,text,integer,jsonb)
  to authenticated;
