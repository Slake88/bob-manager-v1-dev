alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions (club_id, role_key, permission_key, allowed)
select roles.club_id, roles.role_key, perms.permission_key,
  case perms.permission_key
    when 'proposeEvents' then true
    when 'approveEventProposals' then roles.role_key in ('president','vice_president','secretary','treasurer','admin','administrator')
    when 'manageEventRoadbook' then roles.role_key in ('president','vice_president','secretary','road_captain','event_manager','events_manager','admin','administrator')
    when 'manageEventOperations' then roles.role_key in ('president','vice_president','secretary','road_captain','event_manager','events_manager','admin','administrator')
    when 'manageRockRide' then roles.role_key in ('president','vice_president','secretary','event_manager','events_manager','admin','administrator')
    when 'manageEventFinance' then roles.role_key in ('president','vice_president','treasurer','event_manager','events_manager','admin','administrator')
    else false
  end
from (select distinct club_id, role_key from public.club_role_permissions) roles
cross join (values
  ('proposeEvents'),('approveEventProposals'),('manageEventRoadbook'),
  ('manageEventOperations'),('manageRockRide'),('manageEventFinance')
) perms(permission_key)
on conflict (club_id, role_key, permission_key) do nothing;

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;