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
  elsif tg_table_name = 'event_task_assignees' then
    select t.event_id, t.club_id into v_event, v_club
    from public.event_tasks t
    where t.id = new.task_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'A tarefa não pertence a este evento.';
    end if;
    select m.club_id into v_member_club
    from public.members m
    where m.id = new.member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro atribuído não pertence ao clube do evento.';
    end if;
  elsif tg_table_name = 'event_shift_members' then
    select s.event_id, s.club_id into v_event, v_club
    from public.event_shifts s
    where s.id = new.shift_id;
    if v_event is distinct from new.event_id or v_club is distinct from new.club_id then
      raise exception 'O turno não pertence a este evento.';
    end if;
    select m.club_id into v_member_club
    from public.members m
    where m.id = new.member_id;
    if v_member_club is distinct from new.club_id then
      raise exception 'O membro atribuído não pertence ao clube do evento.';
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
