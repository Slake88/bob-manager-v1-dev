-- Preserva acompanhantes existentes da estrutura antiga.
insert into public.event_guests (
  club_id,
  event_id,
  host_member_id,
  registration_id,
  name,
  status,
  created_at
)
select
  e.club_id,
  r.event_id,
  r.member_id,
  r.id,
  btrim(r.guest_name),
  'confirmed',
  coalesce(r.created_at, now())
from public.event_registrations r
join public.events e on e.id = r.event_id
where nullif(btrim(r.guest_name), '') is not null
  and not exists (
    select 1
    from public.event_guests g
    where g.registration_id = r.id
      and lower(g.name) = lower(btrim(r.guest_name))
  );