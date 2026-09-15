create or replace function public.audit_event(
  target_club uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_old jsonb default null::jsonb,
  p_new jsonb default null::jsonb,
  p_reason text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  insert into public.audit_log(
    club_id,
    actor_id,
    action,
    entity_type,
    entity_id,
    before_data,
    after_data,
    data,
    created_at
  )
  values(
    target_club,
    auth.uid(),
    p_action,
    p_entity_type,
    p_entity_id,
    public.audit_redact_json_v1(p_old),
    public.audit_redact_json_v1(p_new),
    case
      when nullif(btrim(p_reason), '') is null then null
      else jsonb_build_object('reason', btrim(p_reason))
    end,
    now()
  );
end
$function$;
