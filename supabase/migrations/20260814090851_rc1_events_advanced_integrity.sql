create or replace function public.enforce_event_child_club_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_club uuid;
begin
  select e.club_id into v_club
  from public.events e
  where e.id = new.event_id;

  if v_club is null then
    raise exception 'Evento inválido ou sem acesso.';
  end if;

  new.club_id := v_club;
  return new;
end;
$$;

create or replace function public.validate_event_advanced_relation_v1()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_event uuid;
  v_club uuid;
  v_member_club uuid;
begin
  if tg_table_name = 'event_guests' then
    select m.club_id into v_member_club from public.members m where m.id = new.host_member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro anfitrião não pertence ao clube do evento.';
    end if;
    if new.registration_id is not null then
      select r.event_id into v_event
      from public.event_registrations r
      where r.id = new.registration_id and r.member_id = new.host_member_id;
      if v_event is distinct from new.event_id then
        raise exception 'A inscrição não corresponde ao membro e evento indicados.';
      end if;
    end if;
  elsif tg_table_name = 'event_route_stops' then
    select r.event_id, r.club_id into v_event, v_club
    from public.event_routes r where r.id = new.route_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'A paragem não pertence ao roadbook deste evento.';
    end if;
  elsif tg_table_name = 'event_task_assignees' then
    select t.event_id, t.club_id into v_event, v_club
    from public.event_tasks t where t.id = new.task_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'A tarefa não pertence a este evento.';
    end if;
    select m.club_id into v_member_club from public.members m where m.id = new.member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro atribuído não pertence ao clube do evento.';
    end if;
  elsif tg_table_name = 'event_shift_members' then
    select s.event_id, s.club_id into v_event, v_club
    from public.event_shifts s where s.id = new.shift_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'O turno não pertence a este evento.';
    end if;
    select m.club_id into v_member_club from public.members m where m.id = new.member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro atribuído não pertence ao clube do evento.';
    end if;
  elsif tg_table_name = 'event_program' and new.responsible_member_id is not null then
    select m.club_id into v_member_club from public.members m where m.id = new.responsible_member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O responsável não pertence ao clube do evento.';
    end if;
  elsif tg_table_name = 'event_incidents' then
    if new.reported_by_member_id is not null then
      select m.club_id into v_member_club from public.members m where m.id = new.reported_by_member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro que reportou não pertence ao clube do evento.';
      end if;
    end if;
    if new.assigned_member_id is not null then
      select m.club_id into v_member_club from public.members m where m.id = new.assigned_member_id;
      if v_member_club is distinct from new.club_id then
        raise exception 'O membro responsável não pertence ao clube do evento.';
      end if;
    end if;
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'event_guests','event_routes','event_route_stops','event_bands','event_exhibitors','event_sponsors',
    'event_octane_configs','event_tasks','event_task_assignees','event_shifts','event_shift_members','event_program','event_incidents'
  ] loop
    execute format('drop trigger if exists trg_%I_club on public.%I', t, t);
    execute format('create trigger trg_%I_club before insert or update of event_id, club_id on public.%I for each row execute function public.enforce_event_child_club_v1()', t, t);
  end loop;
end $$;

drop trigger if exists trg_event_guests_relation on public.event_guests;
create trigger trg_event_guests_relation before insert or update on public.event_guests
for each row execute function public.validate_event_advanced_relation_v1();

drop trigger if exists trg_event_route_stops_relation on public.event_route_stops;
create trigger trg_event_route_stops_relation before insert or update on public.event_route_stops
for each row execute function public.validate_event_advanced_relation_v1();

drop trigger if exists trg_event_task_assignees_relation on public.event_task_assignees;
create trigger trg_event_task_assignees_relation before insert or update on public.event_task_assignees
for each row execute function public.validate_event_advanced_relation_v1();

drop trigger if exists trg_event_shift_members_relation on public.event_shift_members;
create trigger trg_event_shift_members_relation before insert or update on public.event_shift_members
for each row execute function public.validate_event_advanced_relation_v1();

drop trigger if exists trg_event_program_relation on public.event_program;
create trigger trg_event_program_relation before insert or update on public.event_program
for each row execute function public.validate_event_advanced_relation_v1();

drop trigger if exists trg_event_incidents_relation on public.event_incidents;
create trigger trg_event_incidents_relation before insert or update on public.event_incidents
for each row execute function public.validate_event_advanced_relation_v1();

do $$
declare
  t text;
begin
  foreach t in array array[
    'event_proposals','event_guests','event_routes','event_route_stops','event_bands','event_exhibitors','event_sponsors',
    'event_octane_configs','event_tasks','event_shifts','event_program','event_incidents'
  ] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

revoke execute on function public.enforce_event_child_club_v1() from public, anon, authenticated;
revoke execute on function public.validate_event_advanced_relation_v1() from public, anon, authenticated;