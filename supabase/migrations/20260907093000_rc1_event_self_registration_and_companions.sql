begin;

create table if not exists public.event_registration_guests (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references public.event_registrations(id) on delete cascade,
  guest_name text not null,
  created_at timestamptz not null default now(),
  constraint event_registration_guests_name_check
    check (char_length(btrim(guest_name)) between 1 and 120)
);

create index if not exists event_registration_guests_registration_id_idx
  on public.event_registration_guests(registration_id);

alter table public.event_registration_guests enable row level security;

insert into public.event_registration_guests(registration_id, guest_name, created_at)
select er.id, btrim(er.guest_name), er.created_at
from public.event_registrations er
where nullif(btrim(er.guest_name), '') is not null
  and not exists (
    select 1
    from public.event_registration_guests g
    where g.registration_id = er.id
      and lower(btrim(g.guest_name)) = lower(btrim(er.guest_name))
  );

with ranked as (
  select
    id,
    first_value(id) over (
      partition by event_id, member_id
      order by created_at, id
    ) as keep_id
  from public.event_registrations
  where member_id is not null
)
update public.event_registration_guests g
set registration_id = r.keep_id
from ranked r
where g.registration_id = r.id
  and r.id <> r.keep_id;

with ranked as (
  select
    id,
    row_number() over (
      partition by event_id, member_id
      order by created_at, id
    ) as rn
  from public.event_registrations
  where member_id is not null
)
delete from public.event_registrations er
using ranked r
where er.id = r.id
  and r.rn > 1;

update public.event_registrations
set guest_name = null
where guest_name is not null;

create unique index if not exists event_registrations_event_member_unique
  on public.event_registrations(event_id, member_id)
  where member_id is not null;

drop policy if exists event_registrations_insert on public.event_registrations;
create policy event_registrations_insert
on public.event_registrations
for insert
to authenticated
with check (
  exists (
    select 1
    from public.events e
    join public.members m on m.id = event_registrations.member_id
    where e.id = event_registrations.event_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

drop policy if exists event_registrations_update on public.event_registrations;
create policy event_registrations_update
on public.event_registrations
for update
to authenticated
using (
  exists (
    select 1
    from public.events e
    join public.members m on m.id = event_registrations.member_id
    where e.id = event_registrations.event_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.events e
    join public.members m on m.id = event_registrations.member_id
    where e.id = event_registrations.event_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

drop policy if exists event_registrations_delete on public.event_registrations;
create policy event_registrations_delete
on public.event_registrations
for delete
to authenticated
using (
  exists (
    select 1
    from public.events e
    join public.members m on m.id = event_registrations.member_id
    where e.id = event_registrations.event_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

drop policy if exists event_registration_guests_select on public.event_registration_guests;
create policy event_registration_guests_select
on public.event_registration_guests
for select
to authenticated
using (
  exists (
    select 1
    from public.event_registrations er
    join public.events e on e.id = er.event_id
    where er.id = event_registration_guests.registration_id
      and has_club_access(e.club_id)
  )
);

drop policy if exists event_registration_guests_insert on public.event_registration_guests;
create policy event_registration_guests_insert
on public.event_registration_guests
for insert
to authenticated
with check (
  exists (
    select 1
    from public.event_registrations er
    join public.events e on e.id = er.event_id
    join public.members m on m.id = er.member_id
    where er.id = event_registration_guests.registration_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

drop policy if exists event_registration_guests_update on public.event_registration_guests;
create policy event_registration_guests_update
on public.event_registration_guests
for update
to authenticated
using (
  exists (
    select 1
    from public.event_registrations er
    join public.events e on e.id = er.event_id
    join public.members m on m.id = er.member_id
    where er.id = event_registration_guests.registration_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
)
with check (
  exists (
    select 1
    from public.event_registrations er
    join public.events e on e.id = er.event_id
    join public.members m on m.id = er.member_id
    where er.id = event_registration_guests.registration_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

drop policy if exists event_registration_guests_delete on public.event_registration_guests;
create policy event_registration_guests_delete
on public.event_registration_guests
for delete
to authenticated
using (
  exists (
    select 1
    from public.event_registrations er
    join public.events e on e.id = er.event_id
    join public.members m on m.id = er.member_id
    where er.id = event_registration_guests.registration_id
      and m.club_id = e.club_id
      and (
        has_club_permission(e.club_id, 'manageEventParticipants')
        or (
          m.profile_id = auth.uid()
          and e.status in ('published', 'active')
          and has_club_access(e.club_id)
        )
      )
  )
);

commit;
