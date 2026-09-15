drop policy if exists poll_result_counts_select on public.poll_result_counts;
create policy poll_result_counts_select on public.poll_result_counts for select to authenticated using (
  exists(
    select 1 from public.polls p
    where p.id=poll_result_counts.poll_id
      and p.club_id=poll_result_counts.club_id
      and (
        public.has_club_permission(p.club_id,'manageCommunication') or
        (public.has_club_permission(p.club_id,'viewCommunication') and not public.has_club_role(p.club_id,array['prospect']))
      )
      and (
        p.status='closed' or
        (p.status='published' and (p.show_results_before_close=true or (p.ends_at is not null and p.ends_at<=now())))
      )
  )
);
