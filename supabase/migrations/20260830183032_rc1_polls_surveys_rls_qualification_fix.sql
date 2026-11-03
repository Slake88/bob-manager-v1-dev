drop policy if exists poll_options_select on public.poll_options;
create policy poll_options_select on public.poll_options for select to authenticated using (
  exists(select 1 from public.polls p where p.id=poll_options.poll_id and p.club_id=poll_options.club_id)
);

drop policy if exists poll_options_insert on public.poll_options;
create policy poll_options_insert on public.poll_options for insert to authenticated with check (
  public.has_club_permission(poll_options.club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_options.poll_id and p.club_id=poll_options.club_id and p.status='draft')
);

drop policy if exists poll_options_update on public.poll_options;
create policy poll_options_update on public.poll_options for update to authenticated using (
  public.has_club_permission(poll_options.club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_options.poll_id and p.club_id=poll_options.club_id and p.status='draft')
) with check (
  public.has_club_permission(poll_options.club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_options.poll_id and p.club_id=poll_options.club_id and p.status='draft')
);

drop policy if exists poll_options_delete on public.poll_options;
create policy poll_options_delete on public.poll_options for delete to authenticated using (
  public.has_club_permission(poll_options.club_id,'manageCommunication') and
  exists(select 1 from public.polls p where p.id=poll_options.poll_id and p.club_id=poll_options.club_id and p.status='draft')
);

drop policy if exists poll_votes_select on public.poll_votes;
create policy poll_votes_select on public.poll_votes for select to authenticated using (
  poll_votes.profile_id=(select auth.uid()) or
  (public.has_club_permission(poll_votes.club_id,'manageCommunication') and exists(
    select 1 from public.polls p where p.id=poll_votes.poll_id and p.club_id=poll_votes.club_id and p.anonymous=false
  ))
);

drop policy if exists poll_result_counts_select on public.poll_result_counts;
create policy poll_result_counts_select on public.poll_result_counts for select to authenticated using (
  exists(
    select 1 from public.polls p
    where p.id=poll_result_counts.poll_id and p.club_id=poll_result_counts.club_id
      and (
        public.has_club_permission(p.club_id,'manageCommunication') or
        (public.has_club_permission(p.club_id,'viewCommunication') and not public.has_club_role(p.club_id,array['prospect']) and (
          p.status='closed' or
          (p.status='published' and (p.show_results_before_close=true or (p.ends_at is not null and p.ends_at<=now())))
        ))
      )
  )
);
