begin;

-- These helpers are called by SECURITY DEFINER RPCs and trigger functions.
-- Their owners retain implicit EXECUTE; API roles must not invoke them directly.
revoke all on function public.audit_event(uuid,text,text,text,jsonb,jsonb,text)
  from public, anon, authenticated;
revoke all on function public.emit_domain_event(uuid,text,text,uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.profile_has_club_permission(uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function public.treasury_account_balance_v1(uuid)
  from public, anon, authenticated;

-- These legacy RPCs are present in deployed schemas but have no definitions in
-- this repository's migration history. Revoke them when present without making
-- a clean migration replay depend on out-of-band objects.
do $$
declare
  function_signature text;
  function_oid regprocedure;
begin
  foreach function_signature in array array[
    'public.dashboard_summary_v1(uuid)',
    'public.alerts_v1(uuid)',
    'public.member_milestones(uuid,integer)'
  ] loop
    function_oid := to_regprocedure(function_signature);
    if function_oid is not null then
      execute format(
        'revoke all on function %s from public, anon, authenticated',
        function_oid
      );
    else
      raise notice 'Skipping absent legacy function %', function_signature;
    end if;
  end loop;
end;
$$;

-- Preserve the deployed four-column account-balance RPC contract while
-- enforcing permission in the SECURITY DEFINER function itself, independently
-- of RLS.
create or replace function public.treasury_account_balances_v1(target_club uuid)
returns table(id uuid, name text, account_type text, balance numeric)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.' using errcode = '42501';
  end if;
  if not public.has_club_permission(target_club, 'viewTreasury') then
    raise exception 'Sem autorização para consultar a tesouraria.' using errcode = '42501';
  end if;

  return query
  select
    account.id,
    account.name::text,
    account.account_type::text,
    account.opening_balance
    + coalesce(
        sum(
          case
            when tx.kind = 'income'
              and tx.account_id = account.id
              then tx.amount
            when tx.kind = 'expense'
              and tx.account_id = account.id
              then -tx.amount
            when tx.kind = 'transfer'
              and tx.account_id = account.id
              then -tx.amount
            when tx.kind = 'transfer'
              and tx.destination_account_id = account.id
              then tx.amount
            else 0
          end
        ),
        0
      ) as balance
  from public.treasury_accounts account
  left join public.treasury_transactions tx
    on tx.club_id = account.club_id
   and (
     tx.account_id = account.id
     or tx.destination_account_id = account.id
   )
  where account.club_id = target_club
    and account.active = true
  group by
    account.id,
    account.name,
    account.account_type,
    account.opening_balance
  order by account.name;
end;
$function$;

revoke all on function public.treasury_account_balances_v1(uuid) from public, anon;
grant execute on function public.treasury_account_balances_v1(uuid) to authenticated;

-- Preserve the production dashboard_summary contract and calculations while
-- withholding treasury values from members without viewTreasury.
create or replace function public.dashboard_summary(target_club uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  total_balance numeric(14,2);
  month_income numeric(14,2);
  month_expense numeric(14,2);
  pending_fees integer;
  active_members integer;
  unread_notifications integer;
  next_event jsonb;
  account_rows jsonb := '[]'::jsonb;
  can_financial boolean;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.' using errcode = '42501';
  end if;
  can_financial := public.has_club_permission(target_club, 'viewTreasury');

  if can_financial then
    select coalesce(sum(
      a.opening_balance
      + coalesce((
        select sum(
          case
            when t.kind = 'income' then t.amount
            when t.kind = 'expense' then -t.amount
            when t.kind = 'transfer' and t.account_id = a.id then -t.amount
            when t.kind = 'transfer' and t.destination_account_id = a.id then t.amount
            when t.kind = 'reversal' then 0
            else 0
          end
        )
        from public.treasury_transactions t
        where t.club_id = target_club
          and (t.account_id = a.id or t.destination_account_id = a.id)
      ), 0)
    ), 0)
    into total_balance
    from public.treasury_accounts a
    where a.club_id = target_club
      and a.active = true;

    select coalesce(sum(amount), 0)
    into month_income
    from public.treasury_transactions
    where club_id = target_club
      and kind = 'income'
      and date_trunc('month', transaction_date::timestamp)
        = date_trunc('month', now());

    select coalesce(sum(amount), 0)
    into month_expense
    from public.treasury_transactions
    where club_id = target_club
      and kind = 'expense'
      and date_trunc('month', transaction_date::timestamp)
        = date_trunc('month', now());

    select count(*)
    into pending_fees
    from public.fee_obligations
    where club_id = target_club
      and status in ('pending', 'partial')
      and (due_date is null or due_date <= current_date);

    select coalesce(jsonb_agg(row_data order by name), '[]'::jsonb)
    into account_rows
    from (
      select
        a.id,
        a.name,
        a.account_type,
        (
          a.opening_balance
          + coalesce((
            select sum(
              case
                when t.kind = 'income' then t.amount
                when t.kind = 'expense' then -t.amount
                when t.kind = 'transfer' and t.account_id = a.id then -t.amount
                when t.kind = 'transfer' and t.destination_account_id = a.id then t.amount
                else 0
              end
            )
            from public.treasury_transactions t
            where t.club_id = target_club
              and (t.account_id = a.id or t.destination_account_id = a.id)
          ), 0)
        ) as balance
      from public.treasury_accounts a
      where a.club_id = target_club
        and a.active = true
    ) row_data;
  end if;

  select count(*)
  into active_members
  from public.members
  where club_id = target_club
    and status = 'active';

  select count(*)
  into unread_notifications
  from public.notifications
  where club_id = target_club
    and (profile_id is null or profile_id = auth.uid())
    and read_at is null;

  select to_jsonb(e)
  into next_event
  from (
    select id, name, location, starts_at, status
    from public.events
    where club_id = target_club
      and starts_at >= now()
      and status in ('draft', 'published', 'active')
    order by starts_at
    limit 1
  ) e;

  return jsonb_build_object(
    'total_balance', total_balance,
    'month_income', month_income,
    'month_expense', month_expense,
    'month_result', month_income - month_expense,
    'pending_fees', pending_fees,
    'active_members', active_members,
    'unread_notifications', unread_notifications,
    'next_event', next_event,
    'accounts', account_rows
  );
end;
$function$;

revoke all on function public.dashboard_summary(uuid) from public, anon;
grant execute on function public.dashboard_summary(uuid) to authenticated;

commit;
