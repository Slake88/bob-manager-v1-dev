alter table public.fee_obligations
  add column if not exists obligation_type text not null default 'monthly';

alter table public.fee_obligations
  drop constraint if exists fee_obligations_obligation_type_check;
alter table public.fee_obligations
  add constraint fee_obligations_obligation_type_check
  check (obligation_type in ('monthly','registration'));

create unique index if not exists fee_obligations_one_registration_per_member
  on public.fee_obligations(club_id, member_id)
  where obligation_type='registration';

insert into public.club_settings(club_id, key, value)
select c.id, v.key, v.value
from public.clubs c
cross join (values
  ('fee_due_day','8'),
  ('monthly_fee_amount','25'),
  ('registration_fee_amount','0')
) as v(key,value)
on conflict (club_id,key) do nothing;

update public.fee_plans
set due_day=8
where active=true and frequency='monthly';

create or replace function public.generate_member_fees_internal(
  p_member uuid,
  p_year integer
) returns void
language plpgsql
security definer
set search_path=public
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

  if registration_amount > 0 and not exists (
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

create or replace function public.sync_member_fee_obligations_v1(
  target_club uuid,
  p_year integer default null,
  p_member uuid default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  target_year integer := coalesce(p_year, extract(year from current_date)::integer);
  r record;
begin
  if not exists (
    select 1 from public.club_memberships cm
    where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active=true
  ) then
    raise exception 'Sem acesso ao clube.';
  end if;

  for r in
    select id from public.members
    where club_id=target_club
      and status::text in ('prospect','full_color','active')
      and (p_member is null or id=p_member)
  loop
    perform public.generate_member_fees_internal(r.id,target_year);
  end loop;
end;
$$;

create or replace function public.member_fee_autogenerate_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  entry_date date;
begin
  entry_date := coalesce(new.prospect_joined_at,new.joined_at,new.created_at::date,current_date);
  if new.status::text in ('prospect','full_color','active') then
    perform public.generate_member_fees_internal(new.id,extract(year from entry_date)::integer);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_member_fee_autogenerate on public.members;
create trigger trg_member_fee_autogenerate
after insert or update of prospect_joined_at, joined_at, status on public.members
for each row execute function public.member_fee_autogenerate_trigger();

create or replace function public.fee_settings_v1(target_club uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare result jsonb;
begin
  if not exists (
    select 1 from public.club_memberships cm
    where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active=true
  ) then raise exception 'Sem acesso ao clube.'; end if;

  select jsonb_build_object(
    'due_day',coalesce(max(case when key='fee_due_day' then value::integer end),8),
    'monthly_amount',coalesce(max(case when key='monthly_fee_amount' then value::numeric end),25),
    'registration_amount',coalesce(max(case when key='registration_fee_amount' then value::numeric end),0)
  ) into result
  from public.club_settings
  where club_id=target_club and key in ('fee_due_day','monthly_fee_amount','registration_fee_amount');
  return result;
end;
$$;

create or replace function public.update_fee_settings_v1(
  target_club uuid,
  p_due_day integer,
  p_monthly_amount numeric,
  p_registration_amount numeric
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists (
    select 1 from public.club_memberships cm
    where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active=true
      and cm.access_role='super_admin'
  ) then raise exception 'Apenas o Super Admin pode alterar as definições de quotas.'; end if;
  if p_due_day < 1 or p_due_day > 28 then raise exception 'O dia de vencimento deve estar entre 1 e 28.'; end if;
  if p_monthly_amount < 0 or p_registration_amount < 0 then raise exception 'Os valores não podem ser negativos.'; end if;

  insert into public.club_settings(club_id,key,value,updated_by) values
    (target_club,'fee_due_day',p_due_day::text,auth.uid()),
    (target_club,'monthly_fee_amount',p_monthly_amount::text,auth.uid()),
    (target_club,'registration_fee_amount',p_registration_amount::text,auth.uid())
  on conflict (club_id,key) do update
    set value=excluded.value, updated_by=excluded.updated_by, updated_at=now();

  update public.fee_plans set due_day=p_due_day, amount=p_monthly_amount
  where club_id=target_club and active=true and frequency='monthly';
end;
$$;

create or replace function public.delete_fee_obligation_v1(
  target_club uuid,
  p_obligation uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not exists (
    select 1 from public.club_memberships cm
    where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active=true
      and cm.access_role='super_admin'
  ) then raise exception 'Apenas o Super Admin pode apagar quotas.'; end if;

  if exists (select 1 from public.fee_payments where club_id=target_club and obligation_id=p_obligation) then
    raise exception 'Esta quota já tem pagamentos e não pode ser apagada. Deve ser anulada.';
  end if;

  delete from public.fee_obligations
  where id=p_obligation and club_id=target_club;
end;
$$;

revoke all on function public.generate_member_fees_internal(uuid,integer) from public, anon, authenticated;
revoke all on function public.member_fee_autogenerate_trigger() from public, anon, authenticated;
revoke all on function public.sync_member_fee_obligations_v1(uuid,integer,uuid) from public, anon;
revoke all on function public.fee_settings_v1(uuid) from public, anon;
revoke all on function public.update_fee_settings_v1(uuid,integer,numeric,numeric) from public, anon;
revoke all on function public.delete_fee_obligation_v1(uuid,uuid) from public, anon;
grant execute on function public.sync_member_fee_obligations_v1(uuid,integer,uuid) to authenticated;
grant execute on function public.fee_settings_v1(uuid) to authenticated;
grant execute on function public.update_fee_settings_v1(uuid,integer,numeric,numeric) to authenticated;
grant execute on function public.delete_fee_obligation_v1(uuid,uuid) to authenticated;
