with ranked as (
  select id,
         row_number() over (
           partition by registration_id, lower(btrim(guest_name))
           order by created_at, id
         ) as rn
  from public.event_registration_guests
)
delete from public.event_registration_guests g
using ranked r
where g.id = r.id and r.rn > 1;

create unique index if not exists event_registration_guests_registration_name_unique
  on public.event_registration_guests(registration_id, lower(btrim(guest_name)));
