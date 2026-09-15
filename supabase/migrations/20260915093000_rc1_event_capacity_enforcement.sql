begin;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.events'::regclass
      and conname = 'events_capacity_positive_check'
  ) then
    alter table public.events
      add constraint events_capacity_positive_check
      check (capacity is null or capacity > 0) not valid;
  end if;
end;
$$;

alter table public.events
  validate constraint events_capacity_positive_check;

create or replace function public.enforce_event_capacity_seat_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_capacity integer;
  v_occupancy bigint;
  v_required_seats integer := 1;
begin
  if tg_table_name = 'event_registrations' then
    v_event_id := new.event_id;
    if nullif(btrim(new.guest_name), '') is not null then
      v_required_seats := 2;
    end if;
  elsif tg_table_name = 'event_registration_guests' then
    select er.event_id
      into v_event_id
    from public.event_registrations er
    where er.id = new.registration_id;

    if v_event_id is null then
      return new;
    end if;
  else
    raise exception using
      errcode = 'P0001',
      message = 'EVENT_CAPACITY_INVALID_TRIGGER';
  end if;

  select e.capacity
    into v_capacity
  from public.events e
  where e.id = v_event_id
  for update;

  if not found or v_capacity is null then
    return new;
  end if;

  select
    (
      select count(*)
      from public.event_registrations er
      where er.event_id = v_event_id
    )
    + (
      select count(*)
      from public.event_registrations er
      where er.event_id = v_event_id
        and nullif(btrim(er.guest_name), '') is not null
    )
    + (
      select count(*)
      from public.event_registration_guests g
      join public.event_registrations er on er.id = g.registration_id
      where er.event_id = v_event_id
    )
    into v_occupancy;

  if v_occupancy + v_required_seats > v_capacity then
    raise exception using
      errcode = 'P0001',
      message = 'EVENT_CAPACITY_REACHED',
      detail = format(
        'Capacidade: %s; ocupação atual: %s; lugares pedidos: %s.',
        v_capacity,
        v_occupancy,
        v_required_seats
      );
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_event_capacity_seat_v1() from public;

create or replace function public.enforce_event_capacity_floor_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_occupancy bigint;
begin
  if new.capacity is null or new.capacity is not distinct from old.capacity then
    return new;
  end if;

  select
    (
      select count(*)
      from public.event_registrations er
      where er.event_id = new.id
    )
    + (
      select count(*)
      from public.event_registrations er
      where er.event_id = new.id
        and nullif(btrim(er.guest_name), '') is not null
    )
    + (
      select count(*)
      from public.event_registration_guests g
      join public.event_registrations er on er.id = g.registration_id
      where er.event_id = new.id
    )
    into v_occupancy;

  if v_occupancy > new.capacity then
    raise exception using
      errcode = 'P0001',
      message = 'EVENT_CAPACITY_BELOW_OCCUPANCY',
      detail = format(
        'Nova capacidade: %s; ocupação atual: %s.',
        new.capacity,
        v_occupancy
      );
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_event_capacity_floor_v1() from public;

drop trigger if exists trg_event_registrations_capacity
  on public.event_registrations;
create trigger trg_event_registrations_capacity
before insert on public.event_registrations
for each row execute function public.enforce_event_capacity_seat_v1();

drop trigger if exists trg_event_registration_guests_capacity
  on public.event_registration_guests;
create trigger trg_event_registration_guests_capacity
before insert on public.event_registration_guests
for each row execute function public.enforce_event_capacity_seat_v1();

drop trigger if exists trg_events_capacity_floor
  on public.events;
create trigger trg_events_capacity_floor
before update of capacity on public.events
for each row execute function public.enforce_event_capacity_floor_v1();

comment on function public.enforce_event_capacity_seat_v1() is
  'Serializa novas inscrições/acompanhantes pelo registo do evento e impede ultrapassar events.capacity.';
comment on function public.enforce_event_capacity_floor_v1() is
  'Impede reduzir events.capacity abaixo da ocupação já registada.';

commit;
