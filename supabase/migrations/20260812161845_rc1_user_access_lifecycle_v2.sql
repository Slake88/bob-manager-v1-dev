-- Commit 17 — Gestão de contas e acessos

alter table public.club_memberships
  drop constraint if exists club_memberships_access_role_check;

alter table public.club_memberships
  add constraint club_memberships_access_role_check
  check (
    access_role = any (
      array[
        'member'::text,
        'prospect'::text,
        'treasurer'::text,
        'secretary'::text,
        'road_captain'::text,
        'event_manager'::text,
        'events_manager'::text,
        'inventory_manager'::text,
        'euromillions_manager'::text,
        'president'::text,
        'vice_president'::text,
        'admin'::text,
        'administrator'::text,
        'super_admin'::text
      ]
    )
  );

-- O seed de uma nova permission_key é técnico e corre fora de uma sessão Auth.
-- Suspender apenas a produção de Activity Feed evita que o trigger tente emitir
-- um domain event sem auth.uid(); os triggers de auditoria/stamp permanecem ativos.
alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions (
  club_id,
  role_key,
  permission_key,
  allowed,
  updated_at
)
select
  c.id,
  roles.role_key,
  'manageUserAccess',
  roles.allowed,
  now()
from public.clubs c
cross join (
  values
    ('president'::text, true),
    ('vice_president'::text, true),
    ('admin'::text, true),
    ('administrator'::text, true),
    ('treasurer'::text, false),
    ('secretary'::text, false),
    ('road_captain'::text, false),
    ('inventory_manager'::text, false),
    ('event_manager'::text, false),
    ('events_manager'::text, false),
    ('euromillions_manager'::text, false),
    ('prospect'::text, false),
    ('member'::text, false)
) as roles(role_key, allowed)
on conflict (club_id, role_key, permission_key)
do update set
  allowed = excluded.allowed,
  updated_at = now();

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;
