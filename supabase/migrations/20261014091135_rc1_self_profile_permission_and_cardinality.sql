-- Phase 2C.4: preserve both RPC contracts; authorize self-service explicitly.
begin;

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

  if public.has_club_access(target_club) is not true then
    raise exception 'Club access denied' using errcode = '42501';
  end if;

  if public.has_club_permission(target_club, 'editOwnMemberProfile') is not true then
    raise exception 'Own member profile edit permission denied' using errcode = '42501';
  end if;

  begin
    select m.id
      into strict v_member
    from public.members m
    where m.club_id = target_club
      and m.profile_id = auth.uid()
    for update;
  exception
    when no_data_found then
      raise exception 'No member profile linked to current user' using errcode = '42501';
    when too_many_rows then
      raise exception 'Multiple member profiles linked to current user in this club' using errcode = '21000';
  end;

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

  if public.has_club_access(target_club) is not true then
    raise exception 'Club access denied' using errcode = '42501';
  end if;

  if public.has_club_permission(target_club, 'editOwnMemberProfile') is not true then
    raise exception 'Own member profile edit permission denied' using errcode = '42501';
  end if;

  begin
    select m.id
      into strict v_member
    from public.members m
    where m.club_id = target_club
      and m.profile_id = auth.uid()
    for update;
  exception
    when no_data_found then
      raise exception 'No member profile linked to current user' using errcode = '42501';
    when too_many_rows then
      raise exception 'Multiple member profiles linked to current user in this club' using errcode = '21000';
  end;

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
