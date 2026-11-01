revoke insert, update, delete on public.event_proposals from authenticated;
grant select on public.event_proposals to authenticated;

drop policy if exists event_proposals_select on public.event_proposals;
create policy event_proposals_select on public.event_proposals
for select to authenticated
using (
  proposed_by = (select auth.uid())
  or public.has_club_permission(club_id, 'approveEventProposals')
);

create or replace function public.submit_event_proposal_v1(
  target_club uuid,
  p_name text,
  p_description text default null,
  p_location text default null,
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_event_kind text default 'general'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  if not public.has_club_access(target_club) or not public.has_club_permission(target_club, 'proposeEvents') then
    raise exception 'Sem permissão para propor eventos.';
  end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Indica o nome do evento.'; end if;
  if p_event_kind not in ('general','ride','rock_ride_in') then raise exception 'Tipo de evento inválido.'; end if;
  if p_ends_at is not null and p_starts_at is not null and p_ends_at < p_starts_at then
    raise exception 'A data de fim não pode ser anterior ao início.';
  end if;

  insert into public.event_proposals(
    club_id, proposed_by, name, description, location, starts_at, ends_at, event_kind, created_by, updated_by
  ) values (
    target_club, (select auth.uid()), btrim(p_name), nullif(btrim(p_description), ''),
    nullif(btrim(p_location), ''), p_starts_at, p_ends_at, p_event_kind, (select auth.uid()), (select auth.uid())
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.approve_event_proposal_v1(
  p_proposal uuid,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.event_proposals%rowtype;
  v_event uuid;
begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.event_proposals where id = p_proposal for update;
  if not found then raise exception 'Proposta não encontrada.'; end if;
  if not public.has_club_permission(v.club_id, 'approveEventProposals') then
    raise exception 'Sem permissão para aprovar propostas.';
  end if;
  if v.status <> 'submitted' then raise exception 'A proposta já foi processada.'; end if;

  insert into public.events(
    club_id, name, description, location, starts_at, ends_at, status,
    event_mode_enabled, event_kind, is_private, created_by, updated_by
  ) values (
    v.club_id, v.name, v.description, v.location, coalesce(v.starts_at, now()), v.ends_at,
    'draft'::public.event_status, v.event_kind <> 'general', v.event_kind, true,
    (select auth.uid()), (select auth.uid())
  ) returning id into v_event;

  update public.event_proposals
  set status='approved', decision_notes=nullif(btrim(p_notes), ''), decided_by=(select auth.uid()),
      decided_at=now(), approved_event_id=v_event, updated_at=now(), updated_by=(select auth.uid())
  where id=p_proposal;
  return v_event;
end;
$$;

create or replace function public.reject_event_proposal_v1(
  p_proposal uuid,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.event_proposals%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.event_proposals where id = p_proposal for update;
  if not found then raise exception 'Proposta não encontrada.'; end if;
  if not public.has_club_permission(v.club_id, 'approveEventProposals') then
    raise exception 'Sem permissão para rejeitar propostas.';
  end if;
  if v.status <> 'submitted' then raise exception 'A proposta já foi processada.'; end if;
  update public.event_proposals
  set status='rejected', decision_notes=nullif(btrim(p_notes), ''), decided_by=(select auth.uid()),
      decided_at=now(), updated_at=now(), updated_by=(select auth.uid())
  where id=p_proposal;
end;
$$;

create or replace function public.withdraw_event_proposal_v1(p_proposal uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.event_proposals%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.event_proposals where id = p_proposal for update;
  if not found then raise exception 'Proposta não encontrada.'; end if;
  if v.proposed_by <> (select auth.uid()) then raise exception 'Só o autor pode retirar a proposta.'; end if;
  if v.status <> 'submitted' then raise exception 'A proposta já foi processada.'; end if;
  update public.event_proposals
  set status='withdrawn', updated_at=now(), updated_by=(select auth.uid())
  where id=p_proposal;
end;
$$;

revoke execute on function public.submit_event_proposal_v1(uuid,text,text,text,timestamptz,timestamptz,text) from public, anon;
revoke execute on function public.approve_event_proposal_v1(uuid,text) from public, anon;
revoke execute on function public.reject_event_proposal_v1(uuid,text) from public, anon;
revoke execute on function public.withdraw_event_proposal_v1(uuid) from public, anon;
grant execute on function public.submit_event_proposal_v1(uuid,text,text,text,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.approve_event_proposal_v1(uuid,text) to authenticated;
grant execute on function public.reject_event_proposal_v1(uuid,text) to authenticated;
grant execute on function public.withdraw_event_proposal_v1(uuid) to authenticated;

create policy event_guests_select on public.event_guests for select to authenticated using (public.has_club_access(club_id));
create policy event_guests_insert on public.event_guests for insert to authenticated with check (public.has_club_permission(club_id,'manageEventParticipants') or exists (select 1 from public.members m where m.id=host_member_id and m.club_id=club_id and m.profile_id=(select auth.uid())));
create policy event_guests_update on public.event_guests for update to authenticated using (public.has_club_permission(club_id,'manageEventParticipants') or exists (select 1 from public.members m where m.id=host_member_id and m.club_id=club_id and m.profile_id=(select auth.uid()))) with check (public.has_club_permission(club_id,'manageEventParticipants') or exists (select 1 from public.members m where m.id=host_member_id and m.club_id=club_id and m.profile_id=(select auth.uid())));
create policy event_guests_delete on public.event_guests for delete to authenticated using (public.has_club_permission(club_id,'manageEventParticipants') or exists (select 1 from public.members m where m.id=host_member_id and m.club_id=club_id and m.profile_id=(select auth.uid())));

create policy event_routes_select on public.event_routes for select to authenticated using (public.has_club_access(club_id));
create policy event_routes_insert on public.event_routes for insert to authenticated with check (public.has_club_permission(club_id,'manageEventRoadbook'));
create policy event_routes_update on public.event_routes for update to authenticated using (public.has_club_permission(club_id,'manageEventRoadbook')) with check (public.has_club_permission(club_id,'manageEventRoadbook'));
create policy event_routes_delete on public.event_routes for delete to authenticated using (public.has_club_permission(club_id,'manageEventRoadbook'));
create policy event_route_stops_select on public.event_route_stops for select to authenticated using (public.has_club_access(club_id));
create policy event_route_stops_insert on public.event_route_stops for insert to authenticated with check (public.has_club_permission(club_id,'manageEventRoadbook'));
create policy event_route_stops_update on public.event_route_stops for update to authenticated using (public.has_club_permission(club_id,'manageEventRoadbook')) with check (public.has_club_permission(club_id,'manageEventRoadbook'));
create policy event_route_stops_delete on public.event_route_stops for delete to authenticated using (public.has_club_permission(club_id,'manageEventRoadbook'));

create policy event_bands_select on public.event_bands for select to authenticated using (public.has_club_access(club_id));
create policy event_bands_write on public.event_bands for all to authenticated using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance')) with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_exhibitors_select on public.event_exhibitors for select to authenticated using (public.has_club_access(club_id));
create policy event_exhibitors_write on public.event_exhibitors for all to authenticated using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance')) with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_sponsors_select on public.event_sponsors for select to authenticated using (public.has_club_access(club_id));
create policy event_sponsors_write on public.event_sponsors for all to authenticated using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance')) with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));
create policy event_octane_configs_select on public.event_octane_configs for select to authenticated using (public.has_club_access(club_id));
create policy event_octane_configs_write on public.event_octane_configs for all to authenticated using (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance')) with check (public.has_club_permission(club_id,'manageRockRide') or public.has_club_permission(club_id,'manageEventFinance'));

create policy event_tasks_select on public.event_tasks for select to authenticated using (public.has_club_access(club_id));
create policy event_tasks_write on public.event_tasks for all to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_task_assignees_select on public.event_task_assignees for select to authenticated using (public.has_club_access(club_id));
create policy event_task_assignees_write on public.event_task_assignees for all to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shifts_select on public.event_shifts for select to authenticated using (public.has_club_access(club_id));
create policy event_shifts_write on public.event_shifts for all to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_shift_members_select on public.event_shift_members for select to authenticated using (public.has_club_access(club_id));
create policy event_shift_members_write on public.event_shift_members for all to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));
create policy event_program_select on public.event_program for select to authenticated using (public.has_club_access(club_id));
create policy event_program_write on public.event_program for all to authenticated using (public.has_club_permission(club_id,'manageEventOperations')) with check (public.has_club_permission(club_id,'manageEventOperations'));

create policy event_incidents_select on public.event_incidents for select to authenticated using (public.has_club_access(club_id));
create policy event_incidents_insert on public.event_incidents for insert to authenticated with check (public.has_club_permission(club_id,'manageEventOperations') or exists (select 1 from public.members m where m.club_id=club_id and m.profile_id=(select auth.uid()) and (exists (select 1 from public.event_task_assignees a where a.event_id=event_incidents.event_id and a.member_id=m.id) or exists (select 1 from public.event_shift_members s where s.event_id=event_incidents.event_id and s.member_id=m.id))));
create policy event_incidents_update on public.event_incidents for update to authenticated using (public.has_club_permission(club_id,'manageEventOperations') or exists (select 1 from public.members m where m.id=assigned_member_id and m.club_id=club_id and m.profile_id=(select auth.uid()))) with check (public.has_club_permission(club_id,'manageEventOperations') or exists (select 1 from public.members m where m.id=assigned_member_id and m.club_id=club_id and m.profile_id=(select auth.uid())));
create policy event_incidents_delete on public.event_incidents for delete to authenticated using (public.has_club_permission(club_id,'manageEventOperations'));

create or replace function public.acknowledge_event_task_v1(p_assignment uuid, p_complete boolean default false)
returns void language plpgsql security definer set search_path=''
as $$
declare v public.event_task_assignees%rowtype; v_profile uuid; begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.event_task_assignees where id=p_assignment for update;
  if not found then raise exception 'Atribuição não encontrada.'; end if;
  select m.profile_id into v_profile from public.members m where m.id=v.member_id;
  if v_profile <> (select auth.uid()) and not public.has_club_permission(v.club_id,'manageEventOperations') then raise exception 'Sem permissão para atualizar esta tarefa.'; end if;
  update public.event_task_assignees set acknowledged_at=coalesce(acknowledged_at,now()), completed_at=case when p_complete then now() else completed_at end where id=p_assignment;
  if p_complete then update public.event_tasks set status='done', completed_at=coalesce(completed_at,now()), updated_at=now() where id=v.task_id; end if;
end; $$;

create or replace function public.set_event_shift_member_status_v1(p_assignment uuid, p_status text)
returns void language plpgsql security definer set search_path=''
as $$
declare v public.event_shift_members%rowtype; v_profile uuid; begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  if p_status not in ('assigned','confirmed','present','absent','cancelled') then raise exception 'Estado inválido.'; end if;
  select * into v from public.event_shift_members where id=p_assignment for update;
  if not found then raise exception 'Atribuição não encontrada.'; end if;
  select m.profile_id into v_profile from public.members m where m.id=v.member_id;
  if v_profile <> (select auth.uid()) and not public.has_club_permission(v.club_id,'manageEventOperations') then raise exception 'Sem permissão para atualizar este turno.'; end if;
  update public.event_shift_members set status=p_status, checked_in_at=case when p_status='present' then coalesce(checked_in_at,now()) else checked_in_at end, checked_out_at=case when p_status in ('absent','cancelled') then coalesce(checked_out_at,now()) else checked_out_at end where id=p_assignment;
end; $$;

revoke execute on function public.acknowledge_event_task_v1(uuid,boolean) from public, anon;
revoke execute on function public.set_event_shift_member_status_v1(uuid,text) from public, anon;
grant execute on function public.acknowledge_event_task_v1(uuid,boolean) to authenticated;
grant execute on function public.set_event_shift_member_status_v1(uuid,text) to authenticated;