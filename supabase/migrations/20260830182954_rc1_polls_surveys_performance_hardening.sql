create index if not exists poll_options_poll_club_idx on public.poll_options(poll_id,club_id);
create index if not exists poll_votes_poll_club_idx on public.poll_votes(poll_id,club_id);
create index if not exists poll_votes_option_poll_club_idx on public.poll_votes(option_id,poll_id,club_id);
create index if not exists poll_result_counts_poll_club_idx on public.poll_result_counts(poll_id,club_id);
create index if not exists poll_result_counts_option_poll_club_idx on public.poll_result_counts(option_id,poll_id,club_id);
create index if not exists polls_created_by_idx on public.polls(created_by) where created_by is not null;
