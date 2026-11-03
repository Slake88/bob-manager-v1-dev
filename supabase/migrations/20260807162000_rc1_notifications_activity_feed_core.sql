-- RC1 - Notificações + Activity Feed
alter table public.notifications
  add column if not exists module_code text,
  add column if not exists priority text not null default 'normal',
  add column if not exists entity_type text,
  add column if not exists entity_id uuid,
  add column if not exists action_route text,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists domain_event_id uuid references public.domain_events(id) on delete set null,
  add column if not exists archived_at timestamptz;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='notifications_priority_check') then
    alter table public.notifications add constraint notifications_priority_check check(priority in ('low','normal','high','urgent'));
  end if;
end $$;

create index if not exists idx_notifications_profile_unread on public.notifications(profile_id,read_at,created_at desc);
create index if not exists idx_notifications_club_module on public.notifications(club_id,module_code,created_at desc);
create index if not exists idx_activity_feed_club_created on public.activity_feed(club_id,created_at desc);

create table if not exists public.notification_preferences (
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  module_code text not null,
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key(club_id,profile_id,module_code)
);

create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check(platform in ('android','ios','web')),
  device_id text not null,
  push_token text,
  active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique(profile_id,device_id)
);

alter table public.notification_preferences enable row level security;
alter table public.push_devices enable row level security;

drop policy if exists notification_preferences_self on public.notification_preferences;
create policy notification_preferences_self on public.notification_preferences for all to authenticated
using(profile_id=auth.uid() and public.has_club_access(club_id))
with check(profile_id=auth.uid() and public.has_club_access(club_id));

drop policy if exists push_devices_self on public.push_devices;
create policy push_devices_self on public.push_devices for all to authenticated
using(profile_id=auth.uid() and public.has_club_access(club_id))
with check(profile_id=auth.uid() and public.has_club_access(club_id));

drop policy if exists notifications_read on public.notifications;
drop policy if exists notifications_self_read on public.notifications;
create policy notifications_self_read on public.notifications for select to authenticated
using(profile_id=auth.uid() and public.has_club_access(club_id));
drop policy if exists notifications_self_update on public.notifications;
create policy notifications_self_update on public.notifications for update to authenticated
using(profile_id=auth.uid() and public.has_club_access(club_id))
with check(profile_id=auth.uid() and public.has_club_access(club_id));

create or replace function public.profile_has_club_permission(target_club uuid,target_profile uuid,p_permission text)
returns boolean language plpgsql stable security definer set search_path='public' as $$
declare v_role text; v_override boolean; v_base boolean;
begin
  select access_role into v_role from public.club_memberships
   where club_id=target_club and profile_id=target_profile and active=true limit 1;
  if v_role is null then return false; end if;
  if v_role='super_admin' then return true; end if;
  select allowed into v_override from public.user_permission_overrides
   where club_id=target_club and profile_id=target_profile and permission_key=p_permission;
  if found then return v_override; end if;
  select allowed into v_base from public.club_role_permissions
   where club_id=target_club and role_key=v_role and permission_key=p_permission;
  return coalesce(v_base,false);
end; $$;

create or replace function public.notification_module_permission(p_aggregate_type text)
returns text language sql immutable as $$
  select case lower(coalesce(p_aggregate_type,''))
    when 'member' then 'viewMembers' when 'fee' then 'viewFees'
    when 'transaction' then 'viewTreasury' when 'treasury' then 'viewTreasury'
    when 'event' then 'viewEvents' when 'lottery' then 'viewLottery'
    when 'euromillions' then 'viewLottery' when 'inventory' then 'viewInventory'
    when 'product' then 'viewInventory' when 'document' then 'viewDocuments'
    when 'announcement' then 'viewCommunication' when 'communication' then 'viewCommunication'
    when 'emergency' then 'viewEmergencyData' when 'settings' then 'manageSettings'
    when 'permission' then 'manageSettings' else null end;
$$;

create or replace function public.notification_module_code(p_aggregate_type text)
returns text language sql immutable as $$
  select case lower(coalesce(p_aggregate_type,''))
    when 'member' then 'members' when 'fee' then 'fees'
    when 'transaction' then 'treasury' when 'treasury' then 'treasury'
    when 'event' then 'events' when 'lottery' then 'lottery'
    when 'euromillions' then 'lottery' when 'inventory' then 'inventory'
    when 'product' then 'inventory' when 'document' then 'documents'
    when 'announcement' then 'communication' when 'communication' then 'communication'
    when 'emergency' then 'emergency' when 'settings' then 'settings'
    when 'permission' then 'settings' else 'general' end;
$$;

create or replace function public.emit_domain_event(target_club uuid,event_name text,aggregate_type text,aggregate_id uuid,payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path='public' as $$
declare new_id uuid; v_module text; v_permission text; v_title text; v_body text; v_priority text; r record;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  v_module:=public.notification_module_code(aggregate_type);
  v_permission:=public.notification_module_permission(aggregate_type);
  v_title:=coalesce(nullif(payload->>'title',''),event_name);
  v_body:=coalesce(nullif(payload->>'description',''),v_title);
  v_priority:=case when payload->>'priority' in ('low','normal','high','urgent') then payload->>'priority' else 'normal' end;
  insert into public.domain_events(club_id,event_name,aggregate_type,aggregate_id,actor_id,payload)
  values(target_club,event_name,aggregate_type,aggregate_id,auth.uid(),coalesce(payload,'{}'::jsonb)) returning id into new_id;
  insert into public.activity_feed(club_id,actor_id,activity_type,title,description,entity_type,entity_id,metadata)
  values(target_club,auth.uid(),v_module,v_title,payload->>'description',aggregate_type,aggregate_id,
    coalesce(payload,'{}'::jsonb)||jsonb_build_object('event_name',event_name,'module_code',v_module,'domain_event_id',new_id));
  for r in select cm.profile_id from public.club_memberships cm where cm.club_id=target_club and cm.active=true loop
    if v_permission is null or public.profile_has_club_permission(target_club,r.profile_id,v_permission) then
      if coalesce((select np.in_app_enabled from public.notification_preferences np where np.club_id=target_club and np.profile_id=r.profile_id and np.module_code=v_module),true) then
        insert into public.notifications(club_id,profile_id,title,body,notification_type,module_code,priority,entity_type,entity_id,action_route,metadata,domain_event_id)
        values(target_club,r.profile_id,v_title,v_body,event_name,v_module,v_priority,aggregate_type,aggregate_id,payload->>'route',coalesce(payload,'{}'::jsonb),new_id);
      end if;
    end if;
  end loop;
  insert into public.audit_log(club_id,actor_id,entity_type,entity_id,action,after_data)
  values(target_club,auth.uid(),aggregate_type,aggregate_id::text,event_name,payload);
  return new_id;
end; $$;

create or replace function public.mark_notification_read_v1(p_notification uuid,p_read boolean default true)
returns void language sql security definer set search_path='public' as $$
 update public.notifications set read_at=case when p_read then now() else null end
 where id=p_notification and profile_id=auth.uid();
$$;

create or replace function public.mark_all_notifications_read_v1(target_club uuid)
returns integer language plpgsql security definer set search_path='public' as $$
declare n integer;
begin
 update public.notifications set read_at=now() where club_id=target_club and profile_id=auth.uid() and read_at is null;
 get diagnostics n=row_count; return n;
end; $$;
