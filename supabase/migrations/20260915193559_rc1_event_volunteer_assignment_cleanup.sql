begin;

create or replace function public.cleanup_event_volunteer_assignments_v1()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  delete from public.event_task_assignees a
  where a.event_id = old.event_id
    and a.club_id = old.club_id
    and (
      (old.member_id is not null and a.member_id = old.member_id)
      or (old.guest_id is not null and a.guest_id = old.guest_id)
    );

  delete from public.event_shift_members s
  where s.event_id = old.event_id
    and s.club_id = old.club_id
    and (
      (old.member_id is not null and s.member_id = old.member_id)
      or (old.guest_id is not null and s.guest_id = old.guest_id)
    );

  return old;
end;
$$;

revoke all on function public.cleanup_event_volunteer_assignments_v1() from public, anon, authenticated;

drop trigger if exists trg_event_volunteers_cleanup_assignments
  on public.event_volunteers;

create trigger trg_event_volunteers_cleanup_assignments
after delete on public.event_volunteers
for each row
execute function public.cleanup_event_volunteer_assignments_v1();

delete from public.event_task_assignees a
where (
  a.member_id is not null
  and not exists (
    select 1
    from public.event_volunteers v
    where v.event_id = a.event_id
      and v.club_id = a.club_id
      and v.member_id = a.member_id
  )
) or (
  a.guest_id is not null
  and not exists (
    select 1
    from public.event_volunteers v
    where v.event_id = a.event_id
      and v.club_id = a.club_id
      and v.guest_id = a.guest_id
  )
);

delete from public.event_shift_members s
where (
  s.member_id is not null
  and not exists (
    select 1
    from public.event_volunteers v
    where v.event_id = s.event_id
      and v.club_id = s.club_id
      and v.member_id = s.member_id
  )
) or (
  s.guest_id is not null
  and not exists (
    select 1
    from public.event_volunteers v
    where v.event_id = s.event_id
      and v.club_id = s.club_id
      and v.guest_id = s.guest_id
  )
);

commit;