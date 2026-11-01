-- Order the existing operational choices by distance in days from today.
-- Future dinners precede past dinners at the same distance; no association
-- rules, eligibility filters or returned columns change.
begin;

create or replace function public.bar_weekly_dinner_choices_v1(target_club uuid)
returns table(id uuid,dinner_date date,dish text,status text)
language plpgsql stable security definer set search_path=public as $$ begin
  if auth.uid() is null or not public.has_club_access(target_club)
    or not public.has_club_permission(target_club,'viewBar') then
    raise exception 'Sem autorização BAR.' using errcode='42501'; end if;
  return query select d.id,d.dinner_date,d.dish,d.status from public.weekly_dinners d
    where d.club_id=target_club and d.status not in ('cancelled','closed')
      and not exists(select 1 from public.weekly_dinner_finances f
        where f.dinner_id=d.id and f.financial_status='closed')
    order by abs(d.dinner_date - current_date),
      case when d.dinner_date >= current_date then 0 else 1 end,
      d.dinner_date,d.id;
end $$;

-- CREATE OR REPLACE preserves existing privileges; keep the public API explicit.
revoke all on function public.bar_weekly_dinner_choices_v1(uuid) from public,anon;
grant execute on function public.bar_weekly_dinner_choices_v1(uuid) to authenticated;

commit;
