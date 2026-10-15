create table if not exists public.club_role_permissions (
  club_id uuid not null references public.clubs(id) on delete cascade,
  role_key text not null,
  permission_key text not null,
  allowed boolean not null default false,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (club_id, role_key, permission_key)
);

create table if not exists public.user_permission_overrides (
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  permission_key text not null,
  allowed boolean not null,
  updated_by uuid,
  updated_at timestamptz not null default now(),
  primary key (club_id, profile_id, permission_key)
);

alter table public.club_role_permissions enable row level security;
alter table public.user_permission_overrides enable row level security;

drop policy if exists club_role_permissions_read on public.club_role_permissions;
create policy club_role_permissions_read on public.club_role_permissions
for select to authenticated using (public.has_club_access(club_id));

drop policy if exists club_role_permissions_manage on public.club_role_permissions;
create policy club_role_permissions_manage on public.club_role_permissions
for all to authenticated
using (public.has_club_role(club_id,array['super_admin']))
with check (public.has_club_role(club_id,array['super_admin']));

drop policy if exists user_permission_overrides_read on public.user_permission_overrides;
create policy user_permission_overrides_read on public.user_permission_overrides
for select to authenticated using (
  profile_id=auth.uid() or public.has_club_role(club_id,array['super_admin'])
);

drop policy if exists user_permission_overrides_manage on public.user_permission_overrides;
create policy user_permission_overrides_manage on public.user_permission_overrides
for all to authenticated
using (public.has_club_role(club_id,array['super_admin']))
with check (public.has_club_role(club_id,array['super_admin']));

create or replace function public.has_club_permission(target_club uuid, requested_permission text)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_role text;
  v_override boolean;
  v_role_allowed boolean;
begin
  select access_role into v_role
  from public.club_memberships
  where club_id=target_club and profile_id=auth.uid() and active=true
  limit 1;

  if v_role is null then return false; end if;
  if lower(v_role) in ('super_admin','super admin') then return true; end if;

  select allowed into v_override
  from public.user_permission_overrides
  where club_id=target_club
    and profile_id=auth.uid()
    and permission_key=requested_permission;
  if found then return v_override; end if;

  select allowed into v_role_allowed
  from public.club_role_permissions
  where club_id=target_club
    and role_key=v_role
    and permission_key=requested_permission;

  return coalesce(v_role_allowed,false);
end;
$$;

grant execute on function public.has_club_permission(uuid,text) to authenticated;

with permissions(permission_key) as (
  values
  ('viewMembers'),('editOwnMemberProfile'),('manageMembers'),('viewEmergencyData'),
  ('viewTreasury'),('createTreasuryMovement'),('transferBetweenAccounts'),('manageFinancialAccounts'),
  ('approveExpenseRequests'),('viewFinancialReports'),('viewFees'),('manageFees'),
  ('viewLottery'),('manageLottery'),('viewEvents'),('manageEvents'),('manageEventParticipants'),
  ('viewInventory'),('manageInventory'),('sellInventory'),('viewDocuments'),('viewSensitiveDocuments'),
  ('manageDocuments'),('viewCommunication'),('manageCommunication'),('acknowledgeCommunication'),('manageSettings')
), roles(role_key) as (
  values
  ('president'),('vice_president'),('admin'),('administrator'),('treasurer'),('secretary'),
  ('road_captain'),('inventory_manager'),('event_manager'),('events_manager'),
  ('euromillions_manager'),('prospect'),('member')
)
insert into public.club_role_permissions(club_id,role_key,permission_key,allowed)
select c.id,r.role_key,p.permission_key,
case
  when r.role_key in ('president','vice_president','admin','administrator') then true
  when p.permission_key in (
    'viewMembers','editOwnMemberProfile','viewEmergencyData','viewLottery','viewEvents',
    'viewInventory','viewDocuments','viewCommunication','acknowledgeCommunication'
  ) then true
  when r.role_key in ('prospect','member') and p.permission_key='viewFees' then true
  when r.role_key='treasurer' and p.permission_key in (
    'viewTreasury','createTreasuryMovement','transferBetweenAccounts','approveExpenseRequests',
    'viewFinancialReports','viewFees','manageFees','manageLottery','sellInventory','viewSensitiveDocuments'
  ) then true
  when r.role_key='secretary' and p.permission_key in (
    'viewFees','manageFees','manageEvents','manageEventParticipants','viewSensitiveDocuments',
    'manageDocuments','manageCommunication','manageMembers'
  ) then true
  when r.role_key='road_captain' and p.permission_key='manageEventParticipants' then true
  when r.role_key='inventory_manager' and p.permission_key in ('manageInventory','sellInventory') then true
  when r.role_key in ('event_manager','events_manager') and p.permission_key in ('manageEvents','manageEventParticipants') then true
  when r.role_key='euromillions_manager' and p.permission_key='manageLottery' then true
  else false
end
from public.clubs c cross join roles r cross join permissions p
on conflict (club_id,role_key,permission_key) do nothing;
