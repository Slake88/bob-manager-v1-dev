create table if not exists public.event_volunteers (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null,
  event_id uuid not null references public.events(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  function_name text not null,
  status text not null default 'confirmed',
  created_at timestamptz not null default now(),
  unique (event_id, member_id, function_name)
);

alter table public.event_volunteers enable row level security;

drop policy if exists events_access on public.events;
drop policy if exists events_manage on public.events;
drop policy if exists events_read on public.events;

create policy events_select on public.events
for select to authenticated
using (public.has_club_access(club_id));

create policy events_insert on public.events
for insert to authenticated
with check (public.has_club_role(club_id, array['secretary','event_manager','admin','super_admin']));

create policy events_update on public.events
for update to authenticated
using (public.has_club_role(club_id, array['secretary','event_manager','admin','super_admin']))
with check (public.has_club_role(club_id, array['secretary','event_manager','admin','super_admin']));

create policy events_delete on public.events
for delete to authenticated
using (public.has_club_role(club_id, array['secretary','event_manager','admin','super_admin']));

alter table public.event_registrations enable row level security;
drop policy if exists event_registrations_access on public.event_registrations;
drop policy if exists event_registrations_select on public.event_registrations;
drop policy if exists event_registrations_insert on public.event_registrations;
drop policy if exists event_registrations_update on public.event_registrations;
drop policy if exists event_registrations_delete on public.event_registrations;

create policy event_registrations_select on public.event_registrations
for select to authenticated
using (exists (
  select 1 from public.events e
  where e.id = event_id and public.has_club_access(e.club_id)
));

create policy event_registrations_insert on public.event_registrations
for insert to authenticated
with check (exists (
  select 1 from public.events e
  where e.id = event_id
    and public.has_club_role(e.club_id, array['secretary','road_captain','event_manager','admin','super_admin'])
));

create policy event_registrations_update on public.event_registrations
for update to authenticated
using (exists (
  select 1 from public.events e
  where e.id = event_id
    and public.has_club_role(e.club_id, array['secretary','road_captain','event_manager','admin','super_admin'])
))
with check (exists (
  select 1 from public.events e
  where e.id = event_id
    and public.has_club_role(e.club_id, array['secretary','road_captain','event_manager','admin','super_admin'])
));

create policy event_registrations_delete on public.event_registrations
for delete to authenticated
using (exists (
  select 1 from public.events e
  where e.id = event_id
    and public.has_club_role(e.club_id, array['secretary','road_captain','event_manager','admin','super_admin'])
));

create policy event_volunteers_select on public.event_volunteers
for select to authenticated
using (public.has_club_access(club_id));

create policy event_volunteers_insert on public.event_volunteers
for insert to authenticated
with check (public.has_club_role(club_id, array['secretary','road_captain','event_manager','admin','super_admin']));

create policy event_volunteers_update on public.event_volunteers
for update to authenticated
using (public.has_club_role(club_id, array['secretary','road_captain','event_manager','admin','super_admin']))
with check (public.has_club_role(club_id, array['secretary','road_captain','event_manager','admin','super_admin']));

create policy event_volunteers_delete on public.event_volunteers
for delete to authenticated
using (public.has_club_role(club_id, array['secretary','road_captain','event_manager','admin','super_admin']));
