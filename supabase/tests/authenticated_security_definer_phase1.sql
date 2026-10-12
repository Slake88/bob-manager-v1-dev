-- LOCAL ONLY: run against a disposable Supabase database after applying the
-- migration. Supply a member without viewTreasury and one with that permission:
-- psql LOCAL_URL -v club_id=... -v member_profile_id=... \
--   -v treasury_profile_id=... -f supabase/tests/authenticated_security_definer_phase1.sql
-- This test makes no persistent application changes and must never run on production.
\set ON_ERROR_STOP on
begin;
select set_config('phase1_security.club', :'club_id', true);
select set_config('phase1_security.member_profile', :'member_profile_id', true);
select set_config('phase1_security.treasury_profile', :'treasury_profile_id', true);
select set_config('request.jwt.claim.sub', :'member_profile_id', true);
select set_config('request.jwt.claims',
  json_build_object('sub', :'member_profile_id', 'role','authenticated')::text, true);
set local role authenticated;

do $$
declare
  signature text;
  function_oid regprocedure;
  summary jsonb;
  actual_accounts jsonb;
  expected_accounts jsonb;
  actual_account_names text[];
  expected_account_names text[];
  expected_dashboard_keys text[] := array[
    'total_balance', 'month_income', 'month_expense', 'month_result',
    'pending_fees', 'active_members', 'unread_notifications', 'next_event', 'accounts'
  ];
  treasury_result text;
  target uuid := current_setting('phase1_security.club')::uuid;
  member_profile uuid := current_setting('phase1_security.member_profile')::uuid;
  treasury_profile uuid := current_setting('phase1_security.treasury_profile')::uuid;
  caller record;
  required_functions text[] := array[
    'public.audit_event(uuid,text,text,text,jsonb,jsonb,text)',
    'public.emit_domain_event(uuid,text,text,uuid,jsonb)',
    'public.profile_has_club_permission(uuid,uuid,text)',
    'public.treasury_account_balance_v1(uuid)',
    'public.dashboard_summary_v1(uuid)',
    'public.alerts_v1(uuid)',
    'public.member_milestones(uuid,integer)'
  ];
begin
  foreach signature in array required_functions loop
    function_oid := to_regprocedure(signature);
    if function_oid is null then
      raise notice 'Legacy function absent from this schema: %', signature;
    elsif has_function_privilege('anon', function_oid, 'EXECUTE')
       or has_function_privilege('authenticated', function_oid, 'EXECUTE') then
      raise exception 'API role still has EXECUTE on %', signature;
    end if;
  end loop;

  if not has_function_privilege(
      'authenticated','public.treasury_account_balances_v1(uuid)','EXECUTE')
    or not has_function_privilege(
      'authenticated','public.dashboard_summary(uuid)','EXECUTE') then
    raise exception 'authenticated must retain EXECUTE on the public summary RPCs.';
  end if;
  if has_function_privilege('anon','public.treasury_account_balances_v1(uuid)','EXECUTE')
    or has_function_privilege('anon','public.dashboard_summary(uuid)','EXECUTE') then
    raise exception 'anon must not execute treasury or dashboard summary RPCs.';
  end if;

  treasury_result := pg_get_function_result(
    'public.treasury_account_balances_v1(uuid)'::regprocedure);
  if regexp_replace(lower(treasury_result), '\s+', '', 'g')
      <> 'table(iduuid,nametext,account_typetext,balancenumeric)' then
    raise exception 'Unexpected treasury_account_balances_v1 return contract: %', treasury_result;
  end if;

  -- SECURITY DEFINER callers keep their owner's ability to invoke these helpers.
  for caller in
    select p.proname, p.proowner, target_fn.oid as target_oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_proc target_fn on target_fn.oid = any(array[
      to_regprocedure('public.audit_event(uuid,text,text,text,jsonb,jsonb,text)')::oid,
      to_regprocedure('public.emit_domain_event(uuid,text,text,uuid,jsonb)')::oid,
      to_regprocedure('public.profile_has_club_permission(uuid,uuid,text)')::oid,
      to_regprocedure('public.treasury_account_balance_v1(uuid)')::oid
    ])
    where n.nspname = 'public'
      and p.prosecdef
      and position(lower(target_fn.proname) in lower(p.prosrc)) > 0
  loop
    if not has_function_privilege(caller.proowner, caller.target_oid, 'EXECUTE') then
      raise exception 'SECURITY DEFINER caller % lost EXECUTE on an internal helper.', caller.proname;
    end if;
  end loop;

  -- Demonstrate rejection without viewTreasury, then success with it.
  perform set_config('request.jwt.claim.sub', member_profile::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',member_profile,'role','authenticated')::text, true);
  if not public.has_club_access(target) then
    raise exception 'Fixture member must belong to the target club.';
  end if;
  if public.has_club_permission(target,'viewTreasury') then
    raise exception 'Fixture member must not have viewTreasury.';
  end if;
  begin
    perform 1 from public.treasury_account_balances_v1(target);
    raise exception 'treasury_account_balances_v1 accepted a member without viewTreasury.';
  exception when insufficient_privilege then
    null;
  end;
  summary := public.dashboard_summary(target);
  if jsonb_object_length(summary) <> 9
    or not (summary ?& expected_dashboard_keys) then
    raise exception 'dashboard_summary must preserve exactly the 9 deployed keys; got %', summary;
  end if;
  if summary->'total_balance' is distinct from 'null'::jsonb
    or summary->'month_income' is distinct from 'null'::jsonb
    or summary->'month_expense' is distinct from 'null'::jsonb
    or summary->'month_result' is distinct from 'null'::jsonb
    or summary->'pending_fees' is distinct from 'null'::jsonb
    or summary->'accounts' is distinct from '[]'::jsonb then
    raise exception 'dashboard_summary exposed financial metrics to a member without viewTreasury.';
  end if;
  if summary->'active_members' is not distinct from 'null'::jsonb
    or summary->'unread_notifications' is not distinct from 'null'::jsonb then
    raise exception 'dashboard_summary hid non-financial metrics from a club member.';
  end if;

  perform set_config('request.jwt.claim.sub', treasury_profile::text, true);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub',treasury_profile,'role','authenticated')::text, true);
  if not public.has_club_access(target) then
    raise exception 'Fixture treasury user must belong to the target club.';
  end if;
  if not public.has_club_permission(target,'viewTreasury') then
    raise exception 'Fixture treasury user must have viewTreasury.';
  end if;
  select coalesce(jsonb_agg(to_jsonb(account_row) order by account_row.name, account_row.id), '[]'::jsonb)
  into actual_accounts
  from public.treasury_account_balances_v1(target) account_row;
  select coalesce(array_agg(account_row.name order by account_row.ordinality), array[]::text[])
  into actual_account_names
  from public.treasury_account_balances_v1(target) with ordinality as account_row;
  select coalesce(array_agg(account.name::text order by account.name), array[]::text[])
  into expected_account_names
  from public.treasury_accounts account
  where account.club_id = target
    and account.active = true;
  select coalesce(jsonb_agg(to_jsonb(account_row) order by account_row.name, account_row.id), '[]'::jsonb)
  into expected_accounts
  from (
    select
      account.id,
      account.name::text as name,
      account.account_type::text as account_type,
      account.opening_balance
      + coalesce(
          sum(
            case
              when tx.kind = 'income' and tx.account_id = account.id then tx.amount
              when tx.kind = 'expense' and tx.account_id = account.id then -tx.amount
              when tx.kind = 'transfer' and tx.account_id = account.id then -tx.amount
              when tx.kind = 'transfer' and tx.destination_account_id = account.id then tx.amount
              else 0
            end
          ),
          0
        ) as balance
    from public.treasury_accounts account
    left join public.treasury_transactions tx
      on tx.club_id = account.club_id
     and (tx.account_id = account.id or tx.destination_account_id = account.id)
    where account.club_id = target
      and account.active = true
    group by account.id, account.name, account.account_type, account.opening_balance
  ) account_row;
  if actual_accounts is distinct from expected_accounts
    or actual_account_names is distinct from expected_account_names then
    raise exception 'treasury_account_balances_v1 changed its active-account balances or name ordering.';
  end if;
  summary := public.dashboard_summary(target);
  if jsonb_object_length(summary) <> 9
    or not (summary ?& expected_dashboard_keys) then
    raise exception 'dashboard_summary did not preserve its exact deployed key set for an authorized user.';
  end if;
  if summary->'total_balance' = 'null'::jsonb
    or summary->'month_income' = 'null'::jsonb
    or summary->'month_expense' = 'null'::jsonb
    or summary->'month_result' = 'null'::jsonb
    or summary->'pending_fees' = 'null'::jsonb
    or jsonb_typeof(summary->'accounts') is distinct from 'array' then
    raise exception 'dashboard_summary hid financial metrics from a viewTreasury user.';
  end if;
end;
$$;
rollback;
select 'authenticated_security_definer_phase1: all assertions passed' as result;
