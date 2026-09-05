-- Commit 13 — helpers apenas internos.
revoke execute on function public.agenda_current_member_v1(uuid)
  from public,anon,authenticated;
revoke execute on function public.can_view_direction_agenda_v1(uuid)
  from public,anon,authenticated;
