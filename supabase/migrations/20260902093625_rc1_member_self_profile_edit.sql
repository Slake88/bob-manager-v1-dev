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
security definer
set search_path = 'public'
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

revoke all on function public.update_own_member_profile_v1(
  uuid, text, text, text, text, text, text, text, text, text, text, text
) from public;

revoke all on function public.update_own_member_profile_v1(
  uuid, text, text, text, text, text, text, text, text, text, text, text
) from anon;

grant execute on function public.update_own_member_profile_v1(
  uuid, text, text, text, text, text, text, text, text, text, text, text
) to authenticated;
