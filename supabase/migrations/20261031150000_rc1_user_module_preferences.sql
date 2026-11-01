-- Per-user navigation order. This is presentation state, not authorization.
create table if not exists public.user_module_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  module_order jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  constraint user_module_preferences_order_is_array
    check (jsonb_typeof(module_order) = 'array')
);

alter table public.user_module_preferences enable row level security;

revoke all on table public.user_module_preferences from public, anon, authenticated;
grant select, insert, update, delete on table public.user_module_preferences to authenticated;

drop policy if exists user_module_preferences_self on public.user_module_preferences;
create policy user_module_preferences_self
  on public.user_module_preferences
  for all
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

notify pgrst, 'reload schema';
