create or replace function public.list_audit_log_v2(
  target_club uuid,
  p_limit integer default 100
)
returns table(
  id bigint,
  actor_id uuid,
  actor_name text,
  actor_email text,
  action text,
  entity_type text,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  data jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path='public'
as $$
begin
  if auth.uid() is null
     or not public.has_club_permission(target_club, 'manageSettings') then
    raise exception 'Sem autorização para consultar a auditoria.';
  end if;

  return query
  select
    a.id,
    a.actor_id,
    p.full_name as actor_name,
    p.email as actor_email,
    a.action,
    a.entity_type,
    a.entity_id,
    a.before_data,
    a.after_data,
    a.data,
    a.created_at
  from public.audit_log a
  left join public.profiles p on p.id=a.actor_id
  where a.club_id=target_club
  order by a.created_at desc
  limit least(greatest(coalesce(p_limit,100),1),500);
end;
$$;

revoke all on function public.list_audit_log_v2(uuid,integer) from public, anon;
grant execute on function public.list_audit_log_v2(uuid,integer) to authenticated;
