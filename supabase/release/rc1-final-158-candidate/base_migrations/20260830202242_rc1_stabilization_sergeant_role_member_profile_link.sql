alter table public.club_memberships
  drop constraint if exists club_memberships_access_role_check;

alter table public.club_memberships
  add constraint club_memberships_access_role_check
  check (access_role = any (array[
    'member'::text,
    'prospect'::text,
    'treasurer'::text,
    'secretary'::text,
    'road_captain'::text,
    'sergeant_at_arms'::text,
    'event_manager'::text,
    'events_manager'::text,
    'inventory_manager'::text,
    'euromillions_manager'::text,
    'president'::text,
    'vice_president'::text,
    'admin'::text,
    'administrator'::text,
    'super_admin'::text
  ]));

alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions (
  club_id,
  role_key,
  permission_key,
  allowed,
  updated_at
)
select
  rp.club_id,
  'sergeant_at_arms',
  rp.permission_key,
  rp.allowed,
  now()
from public.club_role_permissions rp
where rp.role_key = 'member'
on conflict (club_id, role_key, permission_key) do nothing;

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;

alter table public.members disable trigger trg_activity_members;

with unambiguous_matches as (
  select m.id as member_id, p.id as profile_id
  from public.members m
  join public.profiles p
    on lower(trim(p.email)) = lower(trim(m.email))
  join public.club_memberships cm
    on cm.club_id = m.club_id
   and cm.profile_id = p.id
   and cm.active = true
  where m.profile_id is null
    and m.email is not null
    and trim(m.email) <> ''
    and (
      select count(*)
      from public.profiles p2
      where lower(trim(p2.email)) = lower(trim(m.email))
    ) = 1
    and not exists (
      select 1
      from public.members m2
      where m2.club_id = m.club_id
        and m2.profile_id = p.id
    )
)
update public.members m
set profile_id = u.profile_id,
    updated_at = now()
from unambiguous_matches u
where m.id = u.member_id;

alter table public.members enable trigger trg_activity_members;
