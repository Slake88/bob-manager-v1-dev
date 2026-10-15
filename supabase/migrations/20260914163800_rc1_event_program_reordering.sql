create or replace function public.reorder_event_program_v1(
  p_event uuid,
  p_item_ids uuid[]
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
  select e.club_id
    into v_club_id
  from public.events e
  where e.id = p_event;

  if not found then
    raise exception 'Evento não encontrado.' using errcode = 'P0001';
  end if;

  if not public.has_club_permission(v_club_id, 'manageEventOperations') then
    raise exception 'Sem permissão para gerir o programa do evento.' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_expected
  from public.event_program p
  where p.event_id = p_event
    and p.club_id = v_club_id;

  v_received := coalesce(cardinality(p_item_ids), 0);

  if v_received <> v_expected then
    raise exception 'A lista do programa está desatualizada. Atualiza e tenta novamente.' using errcode = 'P0001';
  end if;

  if v_expected = 0 then
    return;
  end if;

  if exists (
    select 1
    from unnest(p_item_ids) as x(item_id)
    group by x.item_id
    having count(*) > 1
  ) then
    raise exception 'A ordem do programa contém registos repetidos.' using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from public.event_program p
    where p.event_id = p_event
      and p.club_id = v_club_id
      and p.id = any(p_item_ids)
  ) <> v_expected then
    raise exception 'A ordem do programa contém registos inválidos.' using errcode = 'P0001';
  end if;

  select coalesce(max(p.sequence_no), 0) + v_expected + 1000
    into v_offset
  from public.event_program p
  where p.event_id = p_event
    and p.club_id = v_club_id;

  update public.event_program
  set sequence_no = sequence_no + v_offset
  where event_id = p_event
    and club_id = v_club_id;

  update public.event_program p
  set sequence_no = ordered.position::integer
  from unnest(p_item_ids) with ordinality as ordered(item_id, position)
  where p.id = ordered.item_id
    and p.event_id = p_event
    and p.club_id = v_club_id;
end;
$$;

revoke all on function public.reorder_event_program_v1(uuid, uuid[]) from public;
grant execute on function public.reorder_event_program_v1(uuid, uuid[]) to authenticated;
