begin;

alter table public.event_volunteers
  add column guest_id uuid;
alter table public.event_volunteers
  alter column member_id drop not null;
alter table public.event_volunteers
  add constraint event_volunteers_guest_id_fkey
  foreign key (guest_id) references public.event_registration_guests(id) on delete cascade;
alter table public.event_volunteers
  add constraint event_volunteers_subject_check
  check ((member_id is not null) <> (guest_id is not null));
create unique index event_volunteers_event_guest_unique
  on public.event_volunteers(event_id, guest_id)
  where guest_id is not null;
create index event_volunteers_guest_id_idx
  on public.event_volunteers(guest_id)
  where guest_id is not null;

alter table public.event_task_assignees
  add column guest_id uuid;
alter table public.event_task_assignees
  alter column member_id drop not null;
alter table public.event_task_assignees
  add constraint event_task_assignees_guest_id_fkey
  foreign key (guest_id) references public.event_registration_guests(id) on delete cascade;
alter table public.event_task_assignees
  add constraint event_task_assignees_subject_check
  check ((member_id is not null) <> (guest_id is not null));
create unique index event_task_assignees_task_guest_unique
  on public.event_task_assignees(task_id, guest_id)
  where guest_id is not null;
create index event_task_assignees_guest_idx
  on public.event_task_assignees(guest_id)
  where guest_id is not null;

alter table public.event_shift_members
  add column guest_id uuid;
alter table public.event_shift_members
  alter column member_id drop not null;
alter table public.event_shift_members
  add constraint event_shift_members_guest_id_fkey
  foreign key (guest_id) references public.event_registration_guests(id) on delete cascade;
alter table public.event_shift_members
  add constraint event_shift_members_subject_check
  check ((member_id is not null) <> (guest_id is not null));
create unique index event_shift_members_shift_guest_unique
  on public.event_shift_members(shift_id, guest_id)
  where guest_id is not null;
create index event_shift_members_guest_idx
  on public.event_shift_members(guest_id)
  where guest_id is not null;

create or replace function public.validate_event_advanced_relation_v1()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  v_event uuid;
  v_club uuid;
  v_member_club uuid;
begin
  if tg_table_name = 'event_guests' then
    select m.club_id into v_member_club
    from public.members m
    where m.id = new.host_member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro anfitrião não pertence ao clube do evento.';
    end if;
    if new.registration_id is not null then
      select r.event_id into v_event
      from public.event_registrations r
      where r.id = new.registration_id
        and r.member_id = new.host_member_id;
      if v_event is distinct from new.event_id then
        raise exception 'A inscrição não corresponde ao membro e evento indicados.';
      end if;
    end if;
  elsif tg_table_name = 'event_route_stops' then
    select r.event_id, r.club_id into v_event, v_club
    from public.event_routes r
    where r.id = new.route_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'A paragem não pertence ao roadbook deste evento.';
    end if;
  elsif tg_table_name = 'event_volunteers' then
    select e.id, e.club_id into v_event, v_club
    from public.events e
    where e.id = new.event_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'O voluntário não pertence a este evento.';
    end if;
    if new.member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro voluntário não pertence ao clube do evento.';
      end if;
    elsif new.guest_id is not null then
      select er.event_id, e.club_id into v_event, v_club
      from public.event_registration_guests g
      join public.event_registrations er on er.id = g.registration_id
      join public.events e on e.id = er.event_id
      where g.id = new.guest_id;
      if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
        raise exception 'O acompanhante voluntário não pertence a este evento.';
      end if;
    end if;
  elsif tg_table_name = 'event_task_assignees' then
    select t.event_id, t.club_id into v_event, v_club
    from public.event_tasks t
    where t.id = new.task_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'A tarefa não pertence a este evento.';
    end if;
    if new.member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro atribuído não pertence ao clube do evento.';
      end if;
    elsif new.guest_id is not null then
      select er.event_id, e.club_id into v_event, v_club
      from public.event_registration_guests g
      join public.event_registrations er on er.id = g.registration_id
      join public.events e on e.id = er.event_id
      where g.id = new.guest_id;
      if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
        raise exception 'O acompanhante atribuído não pertence a este evento.';
      end if;
    end if;
    if not exists (
      select 1
      from public.event_volunteers v
      where v.event_id = new.event_id
        and v.club_id = new.club_id
        and (
          (new.member_id is not null and v.member_id = new.member_id)
          or (new.guest_id is not null and v.guest_id = new.guest_id)
        )
    ) then
      raise exception 'A pessoa atribuída não está registada como voluntária neste evento.';
    end if;
  elsif tg_table_name = 'event_shift_members' then
    select s.event_id, s.club_id into v_event, v_club
    from public.event_shifts s
    where s.id = new.shift_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'O turno não pertence a este evento.';
    end if;
    if new.member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro atribuído não pertence ao clube do evento.';
      end if;
    elsif new.guest_id is not null then
      select er.event_id, e.club_id into v_event, v_club
      from public.event_registration_guests g
      join public.event_registrations er on er.id = g.registration_id
      join public.events e on e.id = er.event_id
      where g.id = new.guest_id;
      if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
        raise exception 'O acompanhante atribuído não pertence a este evento.';
      end if;
    end if;
    if not exists (
      select 1
      from public.event_volunteers v
      where v.event_id = new.event_id
        and v.club_id = new.club_id
        and (
          (new.member_id is not null and v.member_id = new.member_id)
          or (new.guest_id is not null and v.guest_id = new.guest_id)
        )
    ) then
      raise exception 'A pessoa atribuída não está registada como voluntária neste evento.';
    end if;
  elsif tg_table_name = 'event_program' then
    if new.responsible_member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.responsible_member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O responsável não pertence ao clube do evento.';
      end if;
    end if;
  elsif tg_table_name = 'event_incidents' then
    if new.reported_by_member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.reported_by_member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro que reportou não pertence ao clube do evento.';
      end if;
    end if;
    if new.assigned_member_id is not null then
      select m.club_id into v_member_club
      from public.members m
      where m.id = new.assigned_member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro responsável não pertence ao clube do evento.';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_event_volunteers_relation on public.event_volunteers;
create trigger trg_event_volunteers_relation
before insert or update on public.event_volunteers
for each row execute function public.validate_event_advanced_relation_v1();

create or replace function public.acknowledge_event_task_v1(
  p_assignment uuid,
  p_complete boolean default false
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v public.event_task_assignees%rowtype;
  v_profile uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticação necessária.';
  end if;
  select * into v
  from public.event_task_assignees
  where id = p_assignment
  for update;
  if not found then
    raise exception 'Atribuição não encontrada.';
  end if;
  if v.member_id is not null then
    select m.profile_id into v_profile
    from public.members m
    where m.id = v.member_id;
    if v_profile is distinct from (select auth.uid())
       and not public.has_club_permission(v.club_id, 'manageEventOperations') then
      raise exception 'Sem permissão para atualizar esta tarefa.';
    end if;
  elsif not public.has_club_permission(v.club_id, 'manageEventOperations') then
    raise exception 'Sem permissão para atualizar esta tarefa.';
  end if;
  update public.event_task_assignees
  set acknowledged_at = coalesce(acknowledged_at, now()),
      completed_at = case when p_complete then now() else completed_at end
  where id = p_assignment;
  if p_complete then
    update public.event_tasks
    set status = 'done',
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where id = v.task_id;
  end if;
end;
$$;

create or replace function public.set_event_shift_member_status_v1(
  p_assignment uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v public.event_shift_members%rowtype;
  v_profile uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticação necessária.';
  end if;
  if p_status not in ('assigned','confirmed','present','absent','cancelled') then
    raise exception 'Estado inválido.';
  end if;
  select * into v
  from public.event_shift_members
  where id = p_assignment
  for update;
  if not found then
    raise exception 'Atribuição não encontrada.';
  end if;
  if v.member_id is not null then
    select m.profile_id into v_profile
    from public.members m
    where m.id = v.member_id;
    if v_profile is distinct from (select auth.uid())
       and not public.has_club_permission(v.club_id, 'manageEventOperations') then
      raise exception 'Sem permissão para atualizar este turno.';
    end if;
  elsif not public.has_club_permission(v.club_id, 'manageEventOperations') then
    raise exception 'Sem permissão para atualizar este turno.';
  end if;
  update public.event_shift_members
  set status = p_status,
      checked_in_at = case
        when p_status = 'present' then coalesce(checked_in_at, now())
        else checked_in_at
      end,
      checked_out_at = case
        when p_status in ('absent','cancelled') then coalesce(checked_out_at, now())
        else checked_out_at
      end
  where id = p_assignment;
end;
$$;

commit;
