create or replace function public.list_audit_log_page_v1(
  target_club uuid,
  p_created_from timestamptz default null,
  p_created_before timestamptz default null,
  p_entity_types text[] default null,
  p_exclude_entity_types boolean default false,
  p_action text default null,
  p_actor_query text default null,
  p_search text default null,
  p_entity_id text default null,
  p_cursor_created_at timestamptz default null,
  p_cursor_id bigint default null,
  p_limit integer default 50
)
returns table (
  id bigint,
  actor_id uuid,
  actor_name text,
  actor_email text,
  action text,
  entity_type text,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = 'public'
as $$
begin
  if auth.uid() is null
     or not public.has_club_permission(target_club, 'manageSettings') then
    raise exception 'Sem autorização para consultar a auditoria.';
  end if;

  if (p_cursor_created_at is null) <> (p_cursor_id is null) then
    raise exception 'Cursor de auditoria inválido.';
  end if;

  return query
  -- Preserva audit_log integralmente. A supressão é apenas de leitura e ocorre
  -- antes dos filtros, da ordenação e do limite de 50 + 1 registos.
  with visible_audit_log as materialized (
    select technical.*
    from public.audit_log technical
    where technical.club_id = target_club
      and not exists (
        select 1
        from public.audit_log functional
        where technical.entity_type = 'club_memberships'
          and technical.action = 'updated'
          and technical.actor_id is null
          and jsonb_typeof(technical.before_data) = 'object'
          and jsonb_typeof(technical.after_data) = 'object'
          and technical.before_data->>'profile_id'
            = technical.after_data->>'profile_id'
          and technical.before_data->>'access_role'
            is distinct from technical.after_data->>'access_role'
          -- Só o role e os carimbos de atualização podem ter mudado.
          -- active, member_id, created_at, created_by e qualquer outro campo
          -- mantêm-se na comparação: uma alteração adicional não é ocultada.
          and (technical.before_data - array['access_role', 'updated_at', 'updated_by'])
            = (technical.after_data - array['access_role', 'updated_at', 'updated_by'])
          and functional.club_id = technical.club_id
          and functional.entity_type = 'user_access'
          and functional.action = 'change_role'
          and functional.entity_id = technical.after_data->>'profile_id'
          and functional.data->>'from' = technical.before_data->>'access_role'
          and functional.data->>'to' = technical.after_data->>'access_role'
          and functional.actor_id is not null
          -- A Edge Function grava o evento funcional num pedido posterior.
          -- Janela explícita de 5 segundos; timestamp e id devem avançar.
          -- Sem correspondência completa, preserva-se a linha na leitura.
          and functional.created_at > technical.created_at
          and functional.created_at <= technical.created_at + interval '5 seconds'
          and functional.id > technical.id
      )
  )
  select
    a.id,
    a.actor_id,
    p.full_name::text,
    p.email::text,
    a.action,
    a.entity_type,
    a.entity_id,
    a.before_data,
    a.after_data,
    a.created_at
  from visible_audit_log a
  left join public.profiles p on p.id = a.actor_id
  where a.club_id = target_club
    and (p_created_from is null or a.created_at >= p_created_from)
    and (p_created_before is null or a.created_at < p_created_before)
    and (
      p_entity_types is null
      or cardinality(p_entity_types) = 0
      or (
        coalesce(p_exclude_entity_types, false)
        and (a.entity_type is null or not (a.entity_type = any(p_entity_types)))
      )
      or (
        not coalesce(p_exclude_entity_types, false)
        and a.entity_type = any(p_entity_types)
      )
    )
    and (p_action is null or a.action = p_action)
    and (
      p_actor_query is null
      or concat_ws(' ', p.full_name, p.email) ilike '%' || p_actor_query || '%'
    )
    and (
      p_search is null
      or concat_ws(' ', p.full_name, p.email, a.entity_type, a.action, a.entity_id)
        ilike '%' || p_search || '%'
    )
    and (p_entity_id is null or a.entity_id ilike '%' || p_entity_id || '%')
    and (
      p_cursor_created_at is null
      or a.created_at < p_cursor_created_at
      or (a.created_at = p_cursor_created_at and a.id < p_cursor_id)
    )
  order by a.created_at desc, a.id desc
  limit least(greatest(coalesce(p_limit, 50), 1), 50) + 1;
end;
$$;
