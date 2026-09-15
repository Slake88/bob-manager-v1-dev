create or replace function public.activity_document_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path='public'
as $$
begin
  if tg_op='INSERT' then
    perform public.emit_domain_event(
      new.club_id,
      'DocumentCreated',
      'document',
      new.id,
      jsonb_build_object(
        'title','Novo documento',
        'description',coalesce(nullif(trim(new.name),''),'Documento'),
        'route','documents',
        'priority',case when new.sensitive then 'high' else 'normal' end,
        'push',true
      )
    );
  end if;
  return new;
end;
$$;

revoke all on function public.activity_document_trigger_v1() from public, anon, authenticated;
grant execute on function public.activity_document_trigger_v1() to service_role;
