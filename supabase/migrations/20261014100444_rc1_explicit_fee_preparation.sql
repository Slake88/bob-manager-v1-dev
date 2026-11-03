begin;
create schema if not exists bob_fees_private;
revoke all on schema bob_fees_private from public, anon, authenticated, service_role;
create or replace function bob_fees_private.generate_member_fees(
  p_member uuid,
  p_year integer
) returns void
language plpgsql
security invoker
set search_path=pg_catalog, public, pg_temp
as $$
declare
  m public.members%rowtype;
  entry_date date;
  start_month integer;
  month_no integer;
  due_day integer := 8;
  monthly_amount numeric := 25;
  registration_amount numeric := 0;
  plan_id uuid;
begin
  if p_year is null or p_year < extract(year from current_timestamp at time zone 'Europe/Lisbon')::integer or p_year > 2100 then
    raise exception 'Ano de preparação inválido.' using errcode='22023';
  end if;
  select * into m from public.members where id=p_member;
  if not found then return; end if;
  if m.status::text not in ('prospect','full_color','active') then return; end if;

  entry_date := coalesce(m.prospect_joined_at, m.joined_at, m.created_at::date);
  if entry_date is null then return; end if;

  select coalesce(max(case when key='fee_due_day' then value::integer end),8),
         coalesce(max(case when key='monthly_fee_amount' then value::numeric end),25),
         coalesce(max(case when key='registration_fee_amount' then value::numeric end),0)
    into due_day, monthly_amount, registration_amount
  from public.club_settings
  where club_id=m.club_id and key in ('fee_due_day','monthly_fee_amount','registration_fee_amount');

  if monthly_amount is null or registration_amount is null or monthly_amount < 0 or registration_amount < 0 then
    raise exception 'Configuração de quotas inválida.' using errcode='22023';
  end if;
  due_day := greatest(1, least(due_day,28));

  select id into plan_id
  from public.fee_plans
  where club_id=m.club_id and active=true and frequency='monthly'
  order by created_at desc
  limit 1;

  if p_year >= extract(year from entry_date)::integer and monthly_amount > 0 then
    start_month := case
      when p_year = extract(year from entry_date)::integer then extract(month from entry_date)::integer
      else 1
    end;

    for month_no in start_month..12 loop
      insert into public.fee_obligations(
        club_id, member_id, fee_plan_id, reference_year, reference_month,
        due_date, amount, paid_amount, status, obligation_type
      ) values (
        m.club_id, m.id, plan_id, p_year, month_no,
        make_date(p_year,month_no,due_day), monthly_amount, 0, 'pending', 'monthly'
      )
      on conflict (club_id, member_id, reference_year, reference_month) do nothing;
    end loop;
  end if;

  -- Never reconstruct an old registration using current prices.
  if extract(year from entry_date)::integer = p_year and registration_amount > 0 and not exists (
    select 1 from public.fee_obligations
    where club_id=m.club_id and member_id=m.id and obligation_type='registration'
  ) then
    insert into public.fee_obligations(
      club_id, member_id, reference_year, reference_month,
      due_date, amount, paid_amount, status, obligation_type, notes
    ) values (
      m.club_id, m.id, extract(year from entry_date)::integer, null,
      entry_date, registration_amount, 0, 'pending', 'registration', 'Inscrição de entrada'
    );
  end if;
end;
$$;


revoke all on function bob_fees_private.generate_member_fees(uuid,integer) from public,anon,authenticated,service_role;

create or replace function public.prepare_member_fees_year_v1(target_club uuid,p_year integer)
returns void language plpgsql security definer
set search_path=pg_catalog, public, pg_temp as $$
declare r record;
begin
  if auth.uid() is null or public.has_club_access(target_club) is not true
    or public.has_club_permission(target_club,'manageFees') is not true then
    raise exception 'Sem autorização para preparar quotas.' using errcode='42501';
  end if;
  if p_year is null or p_year < extract(year from current_timestamp at time zone 'Europe/Lisbon')::integer or p_year > 2100 then
    raise exception 'A preparação só permite o ano atual e anos futuros até 2100.' using errcode='22023';
  end if;
  -- Serialize all preparations for the club, including registration creation.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('fees:'||target_club::text,0));
  for r in select id from public.members where club_id=target_club
    and status::text in ('prospect','full_color','active') order by id
  loop
    perform bob_fees_private.generate_member_fees(r.id,p_year);
  end loop;
end $$;
revoke all on function public.prepare_member_fees_year_v1(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.prepare_member_fees_year_v1(uuid,integer) to authenticated;

-- Keep signatures for compatibility diagnostics, but no alternative writer.
create or replace function public.sync_member_fee_obligations_v1(target_club uuid,p_year integer default null,p_member uuid default null)
returns void language plpgsql security invoker set search_path=pg_catalog, public, pg_temp as $$
begin raise exception 'Usa a preparação explícita de quotas.' using errcode='42501'; end $$;
create or replace function public.generate_monthly_fees(target_club uuid,target_year integer,plan_ref uuid)
returns integer language plpgsql security invoker set search_path=pg_catalog, public, pg_temp as $$
begin raise exception 'Usa a preparação explícita de quotas.' using errcode='42501'; end $$;
create or replace function public.generate_member_fees_internal(p_member uuid,p_year integer)
returns void language plpgsql security invoker set search_path=pg_catalog, public, pg_temp as $$
begin raise exception 'Usa a preparação explícita de quotas.' using errcode='42501'; end $$;
-- Member creation/import/status/date edits must never create debt implicitly.
drop trigger if exists trg_member_fee_autogenerate on public.members;
create or replace function public.member_fee_autogenerate_trigger()
returns trigger language plpgsql security invoker set search_path=pg_catalog, public, pg_temp as $$
begin return new; end $$;
revoke all on function public.sync_member_fee_obligations_v1(uuid,integer,uuid) from public,anon,authenticated,service_role;
revoke all on function public.generate_monthly_fees(uuid,integer,uuid) from public,anon,authenticated,service_role;
revoke all on function public.generate_member_fees_internal(uuid,integer) from public,anon,authenticated,service_role;
revoke all on function public.member_fee_autogenerate_trigger() from public,anon,authenticated,service_role;
commit;
