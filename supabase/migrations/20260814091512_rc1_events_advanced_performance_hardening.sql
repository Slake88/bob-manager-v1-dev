create index if not exists event_proposals_approved_event_idx on public.event_proposals(approved_event_id);
create index if not exists event_route_stops_event_idx on public.event_route_stops(event_id);
create index if not exists event_task_assignees_event_idx on public.event_task_assignees(event_id);
create index if not exists event_shift_members_event_idx on public.event_shift_members(event_id);

-- Completa também os índices das relações do módulo Eventos já existentes.
create index if not exists event_partners_event_id_idx on public.event_partners(event_id);
create index if not exists event_registrations_event_id_idx on public.event_registrations(event_id);
create index if not exists event_registrations_member_id_idx on public.event_registrations(member_id);
create index if not exists event_volunteers_member_id_idx on public.event_volunteers(member_id);

-- Evita políticas permissivas duplicadas em SELECT: leitura e escrita ficam separadas.
drop policy if exists event_bands_write on public.event_bands;
create policy event_bands_insert on public.event_bands for insert to authenticated
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_bands_update on public.event_bands for update to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'))
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_bands_delete on public.event_bands for delete to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));

drop policy if exists event_exhibitors_write on public.event_exhibitors;
create policy event_exhibitors_insert on public.event_exhibitors for insert to authenticated
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_exhibitors_update on public.event_exhibitors for update to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'))
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_exhibitors_delete on public.event_exhibitors for delete to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));

drop policy if exists event_sponsors_write on public.event_sponsors;
create policy event_sponsors_insert on public.event_sponsors for insert to authenticated
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_sponsors_update on public.event_sponsors for update to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'))
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_sponsors_delete on public.event_sponsors for delete to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));

drop policy if exists event_octane_configs_write on public.event_octane_configs;
create policy event_octane_configs_insert on public.event_octane_configs for insert to authenticated
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_octane_configs_update on public.event_octane_configs for update to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'))
with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_octane_configs_delete on public.event_octane_configs for delete to authenticated
using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));

drop policy if exists event_tasks_write on public.event_tasks;
create policy event_tasks_insert on public.event_tasks for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_tasks_update on public.event_tasks for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_tasks_delete on public.event_tasks for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));

drop policy if exists event_task_assignees_write on public.event_task_assignees;
create policy event_task_assignees_insert on public.event_task_assignees for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_task_assignees_update on public.event_task_assignees for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_task_assignees_delete on public.event_task_assignees for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));

drop policy if exists event_shifts_write on public.event_shifts;
create policy event_shifts_insert on public.event_shifts for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shifts_update on public.event_shifts for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shifts_delete on public.event_shifts for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));

drop policy if exists event_shift_members_write on public.event_shift_members;
create policy event_shift_members_insert on public.event_shift_members for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shift_members_update on public.event_shift_members for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shift_members_delete on public.event_shift_members for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));

drop policy if exists event_program_write on public.event_program;
create policy event_program_insert on public.event_program for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_program_update on public.event_program for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_program_delete on public.event_program for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));