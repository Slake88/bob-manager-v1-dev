-- RC1: individual status, check-in and operational notes for event companions.

alter table public.event_registration_guests
  add column if not exists status text not null default 'confirmed',
  add column if not exists checked_in_at timestamptz,
  add column if not exists notes text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.event_registration_guests'::regclass
      and conname = 'event_registration_guests_status_check'
  ) then
    alter table public.event_registration_guests
      add constraint event_registration_guests_status_check
      check (status in ('confirmed', 'pending'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.event_registration_guests'::regclass
      and conname = 'event_registration_guests_checkin_status_check'
  ) then
    alter table public.event_registration_guests
      add constraint event_registration_guests_checkin_status_check
      check (checked_in_at is null or status = 'confirmed');
  end if;
end
$$;

create or replace function public.guard_event_registration_guest_attendance_v1()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_club uuid;
begin
  if new.status is not distinct from old.status
     and new.checked_in_at is not distinct from old.checked_in_at
     and new.notes is not distinct from old.notes then
    return new;
  end if;

  select e.club_id
    into v_club
  from public.event_registrations er
  join public.events e on e.id = er.event_id
  where er.id = new.registration_id;

  if v_club is null then
    raise exception 'guest_registration_not_found' using errcode = 'P0001';
  end if;

  if not public.has_club_permission(v_club, 'manageEventParticipants') then
    raise exception 'guest_attendance_permission_denied' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_event_registration_guests_attendance_guard
  on public.event_registration_guests;

create trigger trg_event_registration_guests_attendance_guard
before update of status, checked_in_at, notes
on public.event_registration_guests
for each row
execute function public.guard_event_registration_guest_attendance_v1();

create or replace function public.update_event_guest_attendance_v1(
  p_event uuid,
  p_guest uuid,
  p_status text,
  p_notes text,
  p_checked_in_at timestamptz
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_club uuid;
begin
  if p_status not in ('confirmed', 'pending') then
    raise exception 'guest_status_invalid' using errcode = 'P0001';
  end if;

  if p_status <> 'confirmed' and p_checked_in_at is not null then
    raise exception 'guest_checkin_requires_confirmed_status' using errcode = 'P0001';
  end if;

  select e.club_id
    into v_club
  from public.event_registration_guests g
  join public.event_registrations er on er.id = g.registration_id
  join public.events e on e.id = er.event_id
  where g.id = p_guest
    and er.event_id = p_event;

  if v_club is null then
    raise exception 'guest_not_found_for_event' using errcode = 'P0001';
  end if;

  if not public.has_club_permission(v_club, 'manageEventParticipants') then
    raise exception 'guest_attendance_permission_denied' using errcode = '42501';
  end if;

  update public.event_registration_guests
  set status = p_status,
      notes = nullif(btrim(coalesce(p_notes, '')), ''),
      checked_in_at = p_checked_in_at
  where id = p_guest;
end;
$$;

revoke all on function public.update_event_guest_attendance_v1(uuid, uuid, text, text, timestamptz) from public;
grant execute on function public.update_event_guest_attendance_v1(uuid, uuid, text, text, timestamptz) to authenticated;
