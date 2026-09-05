-- Commit 12 — hardening: helper de disponibilidade é apenas interno.
revoke execute on function public.weekly_officer_member_available_v1(uuid,uuid,date)
  from public, anon, authenticated;
