-- Commit 12 — nunca fabricar histórico de anos anteriores.
create or replace function public.ensure_weekly_officer_schedule_v1(target_club uuid,p_year integer)
returns integer language plpgsql security definer set search_path=public as $$
declare v_start date; v_end date; v_first date; v_inserted integer:=0; v_current_year integer;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if p_year<2020 or p_year>2100 then raise exception 'Ano inválido.'; end if;

  v_current_year:=extract(year from current_date)::int;
  if p_year<v_current_year then return 0; end if;

  v_start:=make_date(p_year,1,1);
  v_end:=make_date(p_year,12,31);
  if p_year=v_current_year then v_start:=greatest(v_start,current_date); end if;
  v_first:=v_start + ((4-extract(dow from v_start)::int+7)%7);

  insert into public.weekly_dinners(club_id,dinner_date,dinner_kind,status,assignment_source,generated)
  select target_club,gs::date,'regular','planned','auto',true
  from generate_series(v_first::timestamp,v_end::timestamp,interval '7 day') gs
  on conflict (club_id,dinner_date,dinner_kind) do nothing;
  get diagnostics v_inserted=row_count;
  perform public.rebuild_weekly_officer_schedule_internal_v1(target_club,v_first,v_end);
  return v_inserted;
end;
$$;

revoke execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) from public,anon;
grant execute on function public.ensure_weekly_officer_schedule_v1(uuid,integer) to authenticated;
