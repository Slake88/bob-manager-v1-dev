with ranked as (
  select
    id,
    row_number() over (
      partition by event_id, member_id
      order by created_at nulls last, id
    ) as rn
  from public.event_volunteers
  where member_id is not null
)
delete from public.event_volunteers v
using ranked r
where v.id = r.id
  and r.rn > 1;

alter table public.event_volunteers
  drop constraint if exists event_volunteers_event_id_member_id_function_name_key;

create unique index if not exists event_volunteers_event_member_unique
  on public.event_volunteers(event_id, member_id)
  where member_id is not null;
