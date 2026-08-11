-- Commit 5 — Auditoria Global BOB Manager
-- Regista utilizador autenticado + timestamp absoluto em todos os registos de domínio
-- e mantém um histórico append-only em public.audit_log.
-- Apresentação local deve usar Europe/Lisbon; a base guarda timestamptz (UTC/absoluto).

-- 1) Compatibilidade do audit_log: normaliza os nomes usados pelo RC1 sem quebrar instalações antigas.
alter table public.audit_log
  add column if not exists actor_id uuid,
  add column if not exists before_data jsonb,
  add column if not exists after_data jsonb;

-- Instalações antigas podem ainda ter actor_profile_id/old_data/new_data.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='audit_log' and column_name='actor_profile_id') then
    execute 'update public.audit_log set actor_id=coalesce(actor_id,actor_profile_id) where actor_id is null';
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='audit_log' and column_name='old_data') then
    execute 'update public.audit_log set before_data=coalesce(before_data,old_data) where before_data is null';
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='audit_log' and column_name='new_data') then
    execute 'update public.audit_log set after_data=coalesce(after_data,new_data) where after_data is null';
  end if;
end $$;

create index if not exists idx_audit_log_club_created
  on public.audit_log(club_id, created_at desc);
create index if not exists idx_audit_log_entity
  on public.audit_log(club_id, entity_type, entity_id, created_at desc);
create index if not exists idx_audit_log_actor
  on public.audit_log(club_id, actor_id, created_at desc);

-- 2) Redação defensiva para não duplicar no histórico dados pessoais/sensíveis desnecessários.
create or replace function public.audit_redact_json_v1(p_data jsonb)
returns jsonb
language sql
immutable
set search_path = 'public'
as $$
  select case
    when p_data is null then null
    else p_data
      - 'tax_number'
      - 'birth_date'
      - 'email'
      - 'phone'
      - 'address'
      - 'notes'
      - 'push_token'
      - 'medical_notes'
      - 'emergency_notes'
      - 'health_data'
  end;
$$;

-- 3) Carimbo servidor: o cliente não escolhe quem criou/alterou nem a hora de registo.
create or replace function public.audit_stamp_row_v1()
returns trigger
language plpgsql
security invoker
set search_path = 'public'
as $$
declare
  v_actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    if v_actor is not null then
      new.created_by := v_actor;
      new.updated_by := v_actor;
    end if;
    new.updated_at := now();
    return new;
  end if;

  -- UPDATE: os metadados originais são imutáveis.
  new.created_at := old.created_at;
  new.created_by := old.created_by;
  new.updated_at := now();
  if v_actor is not null then
    new.updated_by := v_actor;
  else
    new.updated_by := old.updated_by;
  end if;
  return new;
end;
$$;

-- 4) Histórico genérico append-only para qualquer tabela de domínio auditada.
create or replace function public.audit_capture_row_v1()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_club uuid;
  v_actor uuid := auth.uid();
  v_entity_id text;
  v_action text;
begin
  v_old := case when tg_op in ('UPDATE','DELETE') then public.audit_redact_json_v1(to_jsonb(old)) else null end;
  v_new := case when tg_op in ('INSERT','UPDATE') then public.audit_redact_json_v1(to_jsonb(new)) else null end;

  v_club := coalesce(
    nullif(v_new->>'club_id','')::uuid,
    nullif(v_old->>'club_id','')::uuid
  );

  if v_club is null then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  v_entity_id := coalesce(
    v_new->>'id', v_old->>'id',
    v_new->>'profile_id', v_old->>'profile_id',
    v_new->>'member_id', v_old->>'member_id',
    v_new->>'permission_key', v_old->>'permission_key',
    v_new->>'module_code', v_old->>'module_code'
  );

  v_action := case tg_op
    when 'INSERT' then 'created'
    when 'UPDATE' then 'updated'
    when 'DELETE' then 'deleted'
    else lower(tg_op)
  end;

  insert into public.audit_log(
    club_id, actor_id, action, entity_type, entity_id,
    before_data, after_data, created_at
  ) values (
    v_club, v_actor, v_action, tg_table_name, v_entity_id,
    v_old, v_new, now()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.audit_capture_row_v1() from public, anon, authenticated;
revoke all on function public.audit_stamp_row_v1() from public, anon;
grant execute on function public.audit_stamp_row_v1() to authenticated;

-- 5) Normaliza automaticamente todas as tabelas de domínio multi-clube.
-- Excluem-se apenas tabelas técnicas cujo próprio propósito já é histórico/notificação.
do $$
declare
  r record;
begin
  for r in
    select t.table_name
    from information_schema.tables t
    where t.table_schema = 'public'
      and t.table_type = 'BASE TABLE'
      and exists (
        select 1
        from information_schema.columns c
        where c.table_schema = t.table_schema
          and c.table_name = t.table_name
          and c.column_name = 'club_id'
      )
      and t.table_name not in (
        'audit_log',
        'activity_feed',
        'domain_events',
        'notifications',
        'notification_preferences',
        'push_devices'
      )
    order by t.table_name
  loop
    -- Adiciona nullable primeiro para NÃO inventar datas/autores em registos históricos.
    execute format('alter table public.%I add column if not exists created_at timestamptz', r.table_name);
    execute format('alter table public.%I add column if not exists created_by uuid', r.table_name);
    execute format('alter table public.%I add column if not exists updated_at timestamptz', r.table_name);
    execute format('alter table public.%I add column if not exists updated_by uuid', r.table_name);

    -- Defaults são apenas uma segunda barreira; os triggers abaixo são a fonte autoritativa.
    execute format('alter table public.%I alter column created_at set default now()', r.table_name);
    execute format('alter table public.%I alter column created_by set default auth.uid()', r.table_name);
    execute format('alter table public.%I alter column updated_at set default now()', r.table_name);
    execute format('alter table public.%I alter column updated_by set default auth.uid()', r.table_name);

    execute format('drop trigger if exists trg_audit_stamp_v1 on public.%I', r.table_name);
    execute format(
      'create trigger trg_audit_stamp_v1 before insert or update on public.%I for each row execute function public.audit_stamp_row_v1()',
      r.table_name
    );

    execute format('drop trigger if exists trg_audit_capture_v1 on public.%I', r.table_name);
    execute format(
      'create trigger trg_audit_capture_v1 after insert or update or delete on public.%I for each row execute function public.audit_capture_row_v1()',
      r.table_name
    );
  end loop;
end $$;

-- 6) emit_domain_event continua a alimentar Activity Feed/Notificações,
-- mas deixa o audit_log ao trigger global para evitar duplicados.
create or replace function public.emit_domain_event(
  target_club uuid,
  event_name text,
  aggregate_type text,
  aggregate_id uuid,
  payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  new_id uuid;
  v_module text;
  v_permission text;
  v_title text;
  v_body text;
  v_priority text;
  r record;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  v_module := public.notification_module_code(aggregate_type);
  v_permission := public.notification_module_permission(aggregate_type);
  v_title := coalesce(nullif(payload->>'title',''), event_name);
  v_body := coalesce(nullif(payload->>'description',''), v_title);
  v_priority := case
    when payload->>'priority' in ('low','normal','high','urgent') then payload->>'priority'
    else 'normal'
  end;

  insert into public.domain_events(club_id,event_name,aggregate_type,aggregate_id,actor_id,payload)
  values(target_club,event_name,aggregate_type,aggregate_id,auth.uid(),coalesce(payload,'{}'::jsonb))
  returning id into new_id;

  insert into public.activity_feed(club_id,actor_id,activity_type,title,description,entity_type,entity_id,metadata)
  values(
    target_club,
    auth.uid(),
    v_module,
    v_title,
    payload->>'description',
    aggregate_type,
    aggregate_id,
    coalesce(payload,'{}'::jsonb) || jsonb_build_object(
      'event_name',event_name,
      'module_code',v_module,
      'domain_event_id',new_id
    )
  );

  for r in
    select cm.profile_id
    from public.club_memberships cm
    where cm.club_id=target_club and cm.active=true
  loop
    if v_permission is null or public.profile_has_club_permission(target_club,r.profile_id,v_permission) then
      if coalesce((
        select np.in_app_enabled
        from public.notification_preferences np
        where np.club_id=target_club
          and np.profile_id=r.profile_id
          and np.module_code=v_module
      ),true) then
        insert into public.notifications(
          club_id,profile_id,title,body,notification_type,module_code,priority,
          entity_type,entity_id,action_route,metadata,domain_event_id
        ) values (
          target_club,r.profile_id,v_title,v_body,event_name,v_module,v_priority,
          aggregate_type,aggregate_id,payload->>'route',coalesce(payload,'{}'::jsonb),new_id
        );
      end if;
    end if;
  end loop;

  return new_id;
end;
$$;

revoke all on function public.emit_domain_event(uuid,text,text,uuid,jsonb) from public, anon;
grant execute on function public.emit_domain_event(uuid,text,text,uuid,jsonb) to authenticated;

-- 7) Mantém compatibilidade com chamadas antigas a audit_event.
create or replace function public.audit_event(
  target_club uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_old jsonb default null,
  p_new jsonb default null,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;

  insert into public.audit_log(
    club_id,actor_id,action,entity_type,entity_id,
    before_data,after_data,created_at
  ) values (
    target_club,auth.uid(),p_action,p_entity_type,p_entity_id,
    public.audit_redact_json_v1(p_old),public.audit_redact_json_v1(p_new),now()
  );
end;
$$;

revoke all on function public.audit_event(uuid,text,text,text,jsonb,jsonb,text) from public, anon;
grant execute on function public.audit_event(uuid,text,text,text,jsonb,jsonb,text) to authenticated;

-- 8) audit_log é append-only para clientes. Só triggers/funções SECURITY DEFINER escrevem.
alter table public.audit_log enable row level security;

drop policy if exists audit_log_access on public.audit_log;
drop policy if exists audit_log_tenant on public.audit_log;
drop policy if exists audit_read on public.audit_log;
drop policy if exists audit_insert on public.audit_log;
drop policy if exists audit_update on public.audit_log;
drop policy if exists audit_delete on public.audit_log;

create policy audit_read on public.audit_log
for select to authenticated
using (public.has_club_permission(club_id,'manageSettings'));

revoke insert, update, delete on table public.audit_log from anon, authenticated;
grant select on table public.audit_log to authenticated;

-- 9) Consulta preparada com hora oficial de Portugal, sem alterar o timestamp armazenado.
create or replace function public.audit_entity_history_v1(
  target_club uuid,
  p_entity_type text,
  p_entity_id text,
  p_limit integer default 100
)
returns table (
  audit_id bigint,
  action text,
  entity_type text,
  entity_id text,
  actor_id uuid,
  actor_name text,
  created_at timestamptz,
  portugal_date text,
  portugal_time text,
  before_data jsonb,
  after_data jsonb
)
language sql
stable
security invoker
set search_path = 'public'
as $$
  select
    a.id,
    a.action,
    a.entity_type,
    a.entity_id,
    a.actor_id,
    coalesce(p.full_name,'Sistema'),
    a.created_at,
    to_char(a.created_at at time zone 'Europe/Lisbon','DD/MM/YYYY'),
    to_char(a.created_at at time zone 'Europe/Lisbon','HH24:MI:SS'),
    a.before_data,
    a.after_data
  from public.audit_log a
  left join public.profiles p on p.id=a.actor_id
  where a.club_id=target_club
    and a.entity_type=p_entity_type
    and a.entity_id=p_entity_id
  order by a.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500));
$$;

grant execute on function public.audit_entity_history_v1(uuid,text,text,integer) to authenticated;
