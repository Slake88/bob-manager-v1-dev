begin;

-- Technical hardening only: retain each RPC's contract and authorization logic.
create or replace function public.sync_euromillions_players_v1(target_club uuid)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.' using errcode = '42501';
  end if;
  if not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  insert into public.euromillions_players (club_id,member_id,status)
  select m.club_id,m.id,'non_player'
  from public.members m
  where m.club_id=target_club
  on conflict (club_id,member_id) do nothing;
end;
$$;

revoke execute on function public.sync_euromillions_players_v1(uuid) from public;
revoke execute on function public.sync_euromillions_players_v1(uuid) from anon;
grant execute on function public.sync_euromillions_players_v1(uuid) to authenticated;
-- Retains the effective service_role access previously inherited through PUBLIC.
grant execute on function public.sync_euromillions_players_v1(uuid) to service_role;

create or replace function public.generate_euromillions_charges_v1(
  target_club uuid,
  p_year integer,
  p_month integer
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_amount numeric;
  d date;
  monday date;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.' using errcode = '42501';
  end if;
  if not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  perform public.sync_euromillions_players_v1(target_club);
  select coalesce(
    (select value::numeric from public.club_settings
      where club_id=target_club and key='euromillions_draw_amount'),
    2.20
  ) into v_amount;
  d := make_date(p_year,p_month,1);
  while extract(month from d)=p_month loop
    if extract(isodow from d) in (2,5) then
      monday := d - (extract(isodow from d)::integer - 1);
      insert into public.euromillions_draw_charges
        (club_id,player_id,week_start,draw_date,amount)
      select target_club,p.id,monday,d,v_amount
      from public.euromillions_players p
      where p.club_id=target_club and p.status='active'
      on conflict (club_id,player_id,draw_date) do nothing;
    end if;
    d := d + 1;
  end loop;
end;
$$;

revoke execute on function public.generate_euromillions_charges_v1(uuid,integer,integer) from public;
revoke execute on function public.generate_euromillions_charges_v1(uuid,integer,integer) from anon;
grant execute on function public.generate_euromillions_charges_v1(uuid,integer,integer) to authenticated;
-- Retains the effective service_role access previously inherited through PUBLIC.
grant execute on function public.generate_euromillions_charges_v1(uuid,integer,integer) to service_role;

create or replace function public.ensure_weekly_officer_schedule_v1(
  target_club uuid,
  p_year integer
)
returns integer
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_start date;
  v_end date;
  v_first date;
  v_inserted integer := 0;
  v_current_year integer;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if p_year < 2020 or p_year > 2100 then
    raise exception 'Ano inválido.';
  end if;

  v_current_year := extract(year from current_date)::integer;
  if p_year < v_current_year then
    return 0;
  end if;

  v_start := make_date(p_year,1,1);
  v_end := make_date(p_year,12,31);
  if p_year=v_current_year then
    v_start := greatest(v_start,current_date);
  end if;
  v_first := v_start + ((4-extract(dow from v_start)::integer+7)%7);

  insert into public.weekly_dinners
    (club_id,dinner_date,dinner_kind,status,assignment_source,generated)
  select target_club,gs::date,'regular','planned','auto',true
  from generate_series(v_first::timestamp,v_end::timestamp,interval '7 day') gs
  on conflict (club_id,dinner_date,dinner_kind) do nothing;
  get diagnostics v_inserted=row_count;
  perform public.rebuild_weekly_officer_schedule_internal_v1(target_club,v_first,v_end);
  return v_inserted;
end;
$$;

revoke execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) from public;
revoke execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) from anon;
grant execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) to authenticated;
grant execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) to service_role;

create or replace function public.update_own_member_profile_v1(
  target_club uuid,
  p_email text,
  p_phone text,
  p_address text,
  p_postal_code text,
  p_locality text,
  p_emergency_name text,
  p_emergency_relation text,
  p_emergency_phone text,
  p_blood_type text,
  p_allergies text,
  p_medical_notes text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_member uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.has_club_access(target_club) then
    raise exception 'Club access denied' using errcode = '42501';
  end if;

  select m.id
    into v_member
  from public.members m
  where m.club_id = target_club
    and m.profile_id = auth.uid()
  order by m.created_at
  limit 1;

  if v_member is null then
    raise exception 'No member profile linked to current user' using errcode = '42501';
  end if;

  update public.members
  set
    email = nullif(trim(coalesce(p_email, '')), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    postal_code = nullif(trim(coalesce(p_postal_code, '')), ''),
    locality = nullif(trim(coalesce(p_locality, '')), ''),
    emergency_contact =
      (coalesce(emergency_contact, '{}'::jsonb) - array[
        'name', 'contact_name', 'relation', 'phone',
        'blood_type', 'allergies', 'medical_notes'
      ]) || jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(trim(coalesce(p_emergency_name, '')), ''),
        'relation', nullif(trim(coalesce(p_emergency_relation, '')), ''),
        'phone', nullif(trim(coalesce(p_emergency_phone, '')), ''),
        'blood_type', nullif(trim(coalesce(p_blood_type, '')), ''),
        'allergies', nullif(trim(coalesce(p_allergies, '')), ''),
        'medical_notes', nullif(trim(coalesce(p_medical_notes, '')), '')
      )),
    updated_at = now(),
    updated_by = auth.uid()
  where id = v_member
    and club_id = target_club;

  return v_member;
end
$function$;

revoke execute on function public.update_own_member_profile_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text
) from public;
revoke execute on function public.update_own_member_profile_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text
) from anon;
grant execute on function public.update_own_member_profile_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text
) to authenticated;
grant execute on function public.update_own_member_profile_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text
) to service_role;

create or replace function public.update_own_member_profile_v2(
  target_club uuid,
  p_email text,
  p_phone text,
  p_address text,
  p_postal_code text,
  p_locality text,
  p_tax_number text,
  p_emergency_name text,
  p_emergency_relation text,
  p_emergency_phone text,
  p_blood_type text,
  p_allergies text,
  p_medical_notes text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_member uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if not public.has_club_access(target_club) then
    raise exception 'Club access denied' using errcode = '42501';
  end if;

  select m.id
    into v_member
  from public.members m
  where m.club_id = target_club
    and m.profile_id = auth.uid()
  order by m.created_at
  limit 1;

  if v_member is null then
    raise exception 'No member profile linked to current user' using errcode = '42501';
  end if;

  update public.members
  set
    email = nullif(trim(coalesce(p_email, '')), ''),
    phone = nullif(trim(coalesce(p_phone, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    postal_code = nullif(trim(coalesce(p_postal_code, '')), ''),
    locality = nullif(trim(coalesce(p_locality, '')), ''),
    tax_number = nullif(trim(coalesce(p_tax_number, '')), ''),
    emergency_contact =
      (coalesce(emergency_contact, '{}'::jsonb) - array[
        'name', 'contact_name', 'relation', 'phone',
        'blood_type', 'allergies', 'medical_notes'
      ]) || jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(trim(coalesce(p_emergency_name, '')), ''),
        'relation', nullif(trim(coalesce(p_emergency_relation, '')), ''),
        'phone', nullif(trim(coalesce(p_emergency_phone, '')), ''),
        'blood_type', nullif(trim(coalesce(p_blood_type, '')), ''),
        'allergies', nullif(trim(coalesce(p_allergies, '')), ''),
        'medical_notes', nullif(trim(coalesce(p_medical_notes, '')), '')
      )),
    updated_at = now(),
    updated_by = auth.uid()
  where id = v_member
    and club_id = target_club;

  return v_member;
end
$$;

revoke execute on function public.update_own_member_profile_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text
) from public;
revoke execute on function public.update_own_member_profile_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text
) from anon;
grant execute on function public.update_own_member_profile_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text
) to authenticated;
grant execute on function public.update_own_member_profile_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text
) to service_role;

commit;
