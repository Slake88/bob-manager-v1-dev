-- Commit 5, parte 2 — apresentação de auditoria com hora oficial de Portugal.
create or replace function public.activity_feed_portugal_v1(
  target_club uuid,
  p_module text default null,
  p_limit integer default 100
)
returns table (
  id uuid,
  activity_type text,
  title text,
  description text,
  entity_type text,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz,
  actor_name text,
  portugal_date text,
  portugal_time text
)
language plpgsql
stable
security invoker
set search_path = 'public'
as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  return query
  select
    a.id, a.activity_type, a.title, a.description, a.entity_type, a.entity_id,
    a.metadata, a.created_at, coalesce(p.full_name, 'Sistema')::text,
    to_char(a.created_at at time zone 'Europe/Lisbon', 'DD/MM/YYYY')::text,
    to_char(a.created_at at time zone 'Europe/Lisbon', 'HH24:MI:SS')::text
  from public.activity_feed a
  left join public.profiles p on p.id = a.actor_id
  where a.club_id = target_club
    and (p_module is null or p_module = '' or p_module = 'all'
      or coalesce(a.metadata->>'module_code', a.activity_type) = p_module)
  order by a.created_at desc
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

revoke all on function public.activity_feed_portugal_v1(uuid,text,integer) from public, anon;
grant execute on function public.activity_feed_portugal_v1(uuid,text,integer) to authenticated;
