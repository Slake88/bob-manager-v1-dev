drop policy if exists polls_select on public.polls;
create policy polls_select on public.polls for select to authenticated using (
  public.has_club_permission(club_id,'manageCommunication') or
  (status in ('published','closed') and public.has_club_permission(club_id,'viewCommunication') and not public.has_club_role(club_id,array['prospect']))
);

drop policy if exists poll_votes_insert on public.poll_votes;
create policy poll_votes_insert on public.poll_votes for insert to authenticated with check (
  profile_id=(select auth.uid()) and
  public.has_club_permission(club_id,'viewCommunication') and
  not public.has_club_role(club_id,array['prospect'])
);

drop policy if exists poll_result_counts_select on public.poll_result_counts;
create policy poll_result_counts_select on public.poll_result_counts for select to authenticated using (
  exists(
    select 1 from public.polls p
    where p.id=poll_id and p.club_id=club_id
      and (
        public.has_club_permission(p.club_id,'manageCommunication') or
        (public.has_club_permission(p.club_id,'viewCommunication') and not public.has_club_role(p.club_id,array['prospect']) and (
          p.status='closed' or
          (p.status='published' and (p.show_results_before_close=true or (p.ends_at is not null and p.ends_at<=now())))
        ))
      )
  )
);

create or replace function public.poll_option_guard_internal_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_poll uuid; v_club uuid; v_status text;
begin
  if tg_op='DELETE' then
    v_poll:=old.poll_id;
    v_club:=old.club_id;
  else
    v_poll:=new.poll_id;
    v_club:=new.club_id;
  end if;
  select status into v_status from public.polls where id=v_poll and club_id=v_club;
  if v_status is null then raise exception 'Votação não encontrada.'; end if;
  if v_status <> 'draft' then raise exception 'As opções só podem ser alteradas enquanto a votação está em rascunho.'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.poll_option_guard_internal_v1() from public,anon,authenticated;
