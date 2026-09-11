create or replace function public.reorder_event_route_stops_v1(
  p_event uuid,
  p_route uuid,
  p_stop_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_club_id uuid;
  v_expected integer;
  v_received integer;
  v_offset integer;
begin
  select er.club_id
    into v_club_id
  from public.event_routes er
  where er.id = p_route
    and er.event_id = p_event;

  if not found then
    raise exception 'Roadbook não encontrado.' using errcode = 'P0001';
  end if;

  if not public.has_club_permission(v_club_id, 'manageEventRoadbook') then
    raise exception 'Sem permissão para gerir o Roadbook.' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_expected
  from public.event_route_stops s
  where s.event_id = p_event
    and s.route_id = p_route
    and s.club_id = v_club_id;

  v_received := coalesce(cardinality(p_stop_ids), 0);

  if v_received <> v_expected then
    raise exception 'A lista de paragens está desatualizada. Atualiza o Roadbook e tenta novamente.' using errcode = 'P0001';
  end if;

  if v_expected = 0 then
    return;
  end if;

  if exists (
    select 1
    from unnest(p_stop_ids) as x(stop_id)
    group by x.stop_id
    having count(*) > 1
  ) then
    raise exception 'A ordem das paragens contém registos repetidos.' using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.event_route_stops s
    where s.event_id = p_event
      and s.route_id = p_route
      and s.club_id = v_club_id
      and s.id = any(p_stop_ids)
  ) <> v_expected then
    raise exception 'A ordem das paragens contém registos inválidos.' using errcode = 'P0001';
  end if;

  select coalesce(max(s.sequence_no), 0) + v_expected + 1000
    into v_offset
  from public.event_route_stops s
  where s.event_id = p_event
    and s.route_id = p_route
    and s.club_id = v_club_id;

  update public.event_route_stops
  set sequence_no = sequence_no + v_offset
  where event_id = p_event
    and route_id = p_route
    and club_id = v_club_id;

  update public.event_route_stops s
  set sequence_no = ordered.position::integer
  from unnest(p_stop_ids) with ordinality as ordered(stop_id, position)
  where s.id = ordered.stop_id
    and s.event_id = p_event
    and s.route_id = p_route
    and s.club_id = v_club_id;
end;
$$;

revoke all on function public.reorder_event_route_stops_v1(uuid, uuid, uuid[]) from public;
grant execute on function public.reorder_event_route_stops_v1(uuid, uuid, uuid[]) to authenticated;
