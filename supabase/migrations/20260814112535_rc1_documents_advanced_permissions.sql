alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions (club_id, role_key, permission_key, allowed)
select roles.club_id, roles.role_key, perms.permission_key,
  case perms.permission_key
    when 'approveDocuments' then roles.role_key in ('president','vice_president','secretary','admin','administrator')
    when 'runDocumentOcr' then roles.role_key in ('president','vice_president','secretary','admin','administrator')
    when 'manageEventGallery' then roles.role_key in ('president','vice_president','secretary','event_manager','events_manager','admin','administrator')
    when 'manageAnnualBooks' then roles.role_key in ('president','vice_president','secretary','admin','administrator')
    else false
  end
from (select distinct club_id, role_key from public.club_role_permissions) roles
cross join (values
  ('approveDocuments'),('runDocumentOcr'),('manageEventGallery'),('manageAnnualBooks')
) perms(permission_key)
on conflict (club_id, role_key, permission_key) do nothing;

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;
