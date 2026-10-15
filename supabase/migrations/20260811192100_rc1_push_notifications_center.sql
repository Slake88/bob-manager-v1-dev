-- Commit 10: centro persistente de notificacoes + infraestrutura push FCM.

create extension if not exists pg_net with schema extensions;

alter table public.push_devices
  add column if not exists provider text not null default 'fcm',
  add column if not exists app_version text,
  add column if not exists updated_at timestamptz not null default now();

alter table public.push_devices
  drop constraint if exists push_devices_profile_id_device_id_key;
create unique index if not exists push_devices_club_profile_device_uidx
  on public.push_devices(club_id,profile_id,device_id);
create index if not exists push_devices_active_profile_idx
  on public.push_devices(club_id,profile_id,active)
  where active=true and push_token is not null;

create table if not exists public.push_deliveries (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  notification_id uuid not null references public.notifications(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  push_device_id uuid not null references public.push_devices(id) on delete cascade,
  dispatch_token uuid not null default gen_random_uuid(),
  status text not null default 'pending'
    check(status in ('pending','processing','sent','failed','deferred','skipped')),
  attempt_count integer not null default 0,
  provider_message_id text,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(notification_id,push_device_id)
);

create index if not exists push_deliveries_status_idx
  on public.push_deliveries(status,created_at);
create index if not exists push_deliveries_profile_idx
  on public.push_deliveries(club_id,profile_id,created_at desc);

alter table public.push_deliveries enable row level security;
drop policy if exists push_deliveries_self_read on public.push_deliveries;
create policy push_deliveries_self_read on public.push_deliveries
for select to authenticated
using(profile_id=auth.uid() and public.has_club_access(club_id));

create or replace function public.register_push_device_v1(
  target_club uuid,
  p_platform text,
  p_device_id text,
  p_push_token text,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if lower(coalesce(p_platform,'')) not in ('android','ios','web') then
    raise exception 'Plataforma push invalida.';
  end if;
  if btrim(coalesce(p_device_id,''))='' or btrim(coalesce(p_push_token,''))='' then
    raise exception 'Dispositivo ou token push invalido.';
  end if;

  insert into public.push_devices(
    club_id,profile_id,platform,device_id,push_token,provider,active,last_seen_at,app_version,updated_at
  ) values (
    target_club,auth.uid(),lower(p_platform),btrim(p_device_id),btrim(p_push_token),'fcm',true,now(),nullif(btrim(coalesce(p_app_version,'')),''),now()
  )
  on conflict (club_id,profile_id,device_id) do update set
    platform=excluded.platform,
    push_token=excluded.push_token,
    provider='fcm',
    active=true,
    last_seen_at=now(),
    app_version=excluded.app_version,
    updated_at=now()
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.deactivate_push_device_v1(
  target_club uuid,
  p_device_id text
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  update public.push_devices
     set active=false,push_token=null,last_seen_at=now(),updated_at=now()
   where club_id=target_club and profile_id=auth.uid() and device_id=p_device_id;
end;
$$;

create or replace function public.set_notification_preference_v1(
  target_club uuid,
  p_module_code text,
  p_in_app_enabled boolean,
  p_push_enabled boolean
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_module text:=lower(btrim(coalesce(p_module_code,'')));
begin
  if auth.uid() is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if v_module not in ('general','members','treasury','fees','lottery','events','inventory','documents','communication','emergency','settings') then
    raise exception 'Modulo de notificacao invalido.';
  end if;
  insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled,updated_at)
  values(target_club,auth.uid(),v_module,coalesce(p_in_app_enabled,true),coalesce(p_push_enabled,true),now())
  on conflict(club_id,profile_id,module_code) do update set
    in_app_enabled=excluded.in_app_enabled,
    push_enabled=excluded.push_enabled,
    updated_at=now();
end;
$$;

create or replace function public.archive_notification_v1(
  p_notification uuid,
  p_archived boolean default true
)
returns void
language sql
security definer
set search_path=public
as $$
  update public.notifications
     set archived_at=case when coalesce(p_archived,true) then now() else null end
   where id=p_notification and profile_id=auth.uid();
$$;

create or replace function public.enqueue_notification_push_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.profile_id is null then return new; end if;
  if not coalesce((
    select np.push_enabled
      from public.notification_preferences np
     where np.club_id=new.club_id
       and np.profile_id=new.profile_id
       and np.module_code=coalesce(new.module_code,'general')
  ),true) then
    return new;
  end if;

  insert into public.push_deliveries(
    club_id,notification_id,profile_id,push_device_id,status
  )
  select new.club_id,new.id,new.profile_id,d.id,'pending'
    from public.push_devices d
   where d.club_id=new.club_id
     and d.profile_id=new.profile_id
     and d.active=true
     and d.provider='fcm'
     and nullif(btrim(coalesce(d.push_token,'')),'') is not null
  on conflict(notification_id,push_device_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_notifications_enqueue_push_v1 on public.notifications;
create trigger trg_notifications_enqueue_push_v1
after insert on public.notifications
for each row execute function public.enqueue_notification_push_v1();

create or replace function public.claim_push_delivery_v1(
  p_delivery uuid,
  p_dispatch_token uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare d public.push_deliveries%rowtype;
declare n public.notifications%rowtype;
declare dev public.push_devices%rowtype;
declare v_push_enabled boolean;
begin
  select * into d from public.push_deliveries
   where id=p_delivery and dispatch_token=p_dispatch_token
   for update;
  if d.id is null or d.status<>'pending' then return null; end if;

  select * into n from public.notifications where id=d.notification_id;
  select * into dev from public.push_devices where id=d.push_device_id;

  if n.id is null or dev.id is null or not dev.active or nullif(btrim(coalesce(dev.push_token,'')),'') is null then
    update public.push_deliveries set status='skipped',last_error='Dispositivo push indisponivel.',updated_at=now() where id=d.id;
    return null;
  end if;

  select coalesce((
    select np.push_enabled from public.notification_preferences np
     where np.club_id=d.club_id and np.profile_id=d.profile_id and np.module_code=coalesce(n.module_code,'general')
  ),true) into v_push_enabled;
  if not v_push_enabled then
    update public.push_deliveries set status='skipped',last_error='Push desativado nas preferencias.',updated_at=now() where id=d.id;
    return null;
  end if;

  update public.push_deliveries
     set status='processing',attempt_count=attempt_count+1,last_error=null,updated_at=now()
   where id=d.id;

  return jsonb_build_object(
    'delivery_id',d.id,
    'notification_id',n.id,
    'push_device_id',dev.id,
    'push_token',dev.push_token,
    'title',n.title,
    'body',n.body,
    'priority',n.priority,
    'module_code',coalesce(n.module_code,'general'),
    'entity_type',n.entity_type,
    'entity_id',n.entity_id,
    'action_route',n.action_route
  );
end;
$$;

create or replace function public.complete_push_delivery_v1(
  p_delivery uuid,
  p_status text,
  p_provider_message_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_status text:=lower(coalesce(p_status,''));
begin
  if v_status not in ('sent','failed','deferred','skipped') then
    raise exception 'Estado de entrega push invalido.';
  end if;
  update public.push_deliveries
     set status=v_status,
         provider_message_id=nullif(p_provider_message_id,''),
         last_error=nullif(left(coalesce(p_error,''),1000),''),
         sent_at=case when v_status='sent' then now() else sent_at end,
         updated_at=now()
   where id=p_delivery;
end;
$$;

create or replace function public.deactivate_push_device_server_v1(p_device uuid)
returns void
language sql
security definer
set search_path=public
as $$
  update public.push_devices set active=false,push_token=null,updated_at=now() where id=p_device;
$$;

create or replace function public.dispatch_push_delivery_webhook_v1()
returns trigger
language plpgsql
security definer
set search_path=public,net
as $$
begin
  if new.status<>'pending' then return new; end if;
  perform net.http_post(
    url := 'https://vgjwghzypumtxvbuhwwl.supabase.co/functions/v1/push-dispatch',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('delivery_id',new.id,'dispatch_token',new.dispatch_token),
    timeout_milliseconds := 5000
  );
  return new;
end;
$$;

drop trigger if exists trg_push_delivery_dispatch_insert_v1 on public.push_deliveries;
create trigger trg_push_delivery_dispatch_insert_v1
after insert on public.push_deliveries
for each row when (new.status='pending')
execute function public.dispatch_push_delivery_webhook_v1();

drop trigger if exists trg_push_delivery_dispatch_retry_v1 on public.push_deliveries;
create trigger trg_push_delivery_dispatch_retry_v1
after update of status on public.push_deliveries
for each row when (new.status='pending' and old.status is distinct from new.status)
execute function public.dispatch_push_delivery_webhook_v1();

revoke all on function public.enqueue_notification_push_v1() from public,anon,authenticated;
revoke all on function public.dispatch_push_delivery_webhook_v1() from public,anon,authenticated;
revoke all on function public.claim_push_delivery_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function public.complete_push_delivery_v1(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.deactivate_push_device_server_v1(uuid) from public,anon,authenticated;
grant execute on function public.claim_push_delivery_v1(uuid,uuid) to service_role;
grant execute on function public.complete_push_delivery_v1(uuid,text,text,text) to service_role;
grant execute on function public.deactivate_push_device_server_v1(uuid) to service_role;

grant execute on function public.register_push_device_v1(uuid,text,text,text,text) to authenticated;
grant execute on function public.deactivate_push_device_v1(uuid,text) to authenticated;
grant execute on function public.set_notification_preference_v1(uuid,text,boolean,boolean) to authenticated;
grant execute on function public.archive_notification_v1(uuid,boolean) to authenticated;
