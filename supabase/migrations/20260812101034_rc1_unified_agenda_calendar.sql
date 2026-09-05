-- Commit 13 — Agenda / Calendário Unificado

create table if not exists public.agenda_items (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  item_type text not null check (item_type in ('meeting','deadline','reminder')),
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  all_day boolean not null default false,
  location text,
  audience text not null default 'all' check (audience in ('all','direction')),
  priority text not null default 'normal' check (priority in ('low','normal','high')),
  status text not null default 'planned' check (status in ('planned','completed','cancelled')),
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  check (ends_at is null or ends_at >= starts_at)
);

create index if not exists agenda_items_club_starts_idx
  on public.agenda_items(club_id, starts_at);
create index if not exists agenda_items_club_status_idx
  on public.agenda_items(club_id, status, starts_at);

alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions(club_id,role_key,permission_key,allowed)
select distinct club_id,role_key,'viewAgenda',true
from public.club_role_permissions
on conflict (club_id,role_key,permission_key) do nothing;

insert into public.club_role_permissions(club_id,role_key,permission_key,allowed)
select distinct club_id,role_key,'manageAgenda',
  role_key in ('president','vice_president','secretary','admin','administrator')
from public.club_role_permissions
on conflict (club_id,role_key,permission_key) do nothing;

insert into public.club_role_permissions(club_id,role_key,permission_key,allowed)
select distinct club_id,role_key,'viewDirectionAgenda',
  role_key in ('president','vice_president','secretary','treasurer','admin','administrator')
from public.club_role_permissions
on conflict (club_id,role_key,permission_key) do nothing;

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;

create or replace function public.can_manage_agenda_v1(target_club uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_club_permission(target_club,'manageAgenda');
$$;

create or replace function public.can_view_direction_agenda_v1(target_club uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_club_permission(target_club,'viewDirectionAgenda');
$$;

create or replace function public.agenda_current_member_v1(target_club uuid)
returns uuid language sql stable security definer set search_path=public as $$
  select m.id from public.members m
  where m.club_id=target_club and m.profile_id=(select auth.uid()) limit 1;
$$;

create or replace function public.agenda_anniversary_date_v1(p_source date,p_year integer)
returns date language sql immutable set search_path=public as $$
  select make_date(
    p_year,
    extract(month from p_source)::int,
    least(
      extract(day from p_source)::int,
      extract(day from (
        date_trunc('month',make_date(p_year,extract(month from p_source)::int,1))
        + interval '1 month - 1 day'
      ))::int
    )
  );
$$;

create or replace function public.agenda_notify_profiles_v1(
  target_club uuid,p_audience text,p_title text,p_body text,p_entity uuid
)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer:=0;
begin
  insert into public.notifications(
    club_id,profile_id,title,body,notification_type,module_code,priority,
    entity_type,entity_id,action_route,metadata
  )
  select target_club,cm.profile_id,p_title,p_body,'info','agenda','normal',
         'agenda_item',p_entity,'agenda',jsonb_build_object('module_code','agenda')
  from public.club_memberships cm
  left join public.notification_preferences np
    on np.club_id=cm.club_id
   and np.profile_id=cm.profile_id
   and np.module_code='agenda'
  where cm.club_id=target_club
    and cm.active=true
    and coalesce(np.in_app_enabled,true)=true
    and (
      p_audience='all'
      or public.profile_has_club_permission(
        target_club,cm.profile_id,'viewDirectionAgenda'
      )
    );
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function public.save_agenda_item_v1(
  target_club uuid,p_item uuid,p_item_type text,p_title text,p_description text,
  p_starts_at timestamptz,p_ends_at timestamptz,p_all_day boolean,p_location text,
  p_audience text,p_priority text,p_status text,p_notify_now boolean default false
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_old jsonb; v_new jsonb; v_date_label text;
begin
  if not public.can_manage_agenda_v1(target_club) then
    raise exception 'Sem autorização para gerir a Agenda.';
  end if;
  if p_item_type not in ('meeting','deadline','reminder') then
    raise exception 'Tipo inválido.';
  end if;
  if nullif(btrim(coalesce(p_title,'')),'') is null then
    raise exception 'Indica o título.';
  end if;
  if p_starts_at is null then raise exception 'Indica a data/hora.'; end if;
  if p_ends_at is not null and p_ends_at<p_starts_at then
    raise exception 'A data final não pode ser anterior à inicial.';
  end if;
  if p_audience not in ('all','direction') then
    raise exception 'Destinatários inválidos.';
  end if;
  if p_priority not in ('low','normal','high') then
    raise exception 'Prioridade inválida.';
  end if;
  if p_status not in ('planned','completed','cancelled') then
    raise exception 'Estado inválido.';
  end if;

  if p_item is null then
    insert into public.agenda_items(
      club_id,item_type,title,description,starts_at,ends_at,all_day,
      location,audience,priority,status
    )
    values(
      target_club,p_item_type,btrim(p_title),
      nullif(btrim(coalesce(p_description,'')),''),p_starts_at,p_ends_at,
      coalesce(p_all_day,false),nullif(btrim(coalesce(p_location,'')),''),
      p_audience,p_priority,p_status
    )
    returning id into v_id;
  else
    select to_jsonb(a) into v_old
    from public.agenda_items a
    where a.id=p_item and a.club_id=target_club;
    if v_old is null then raise exception 'Item da Agenda não encontrado.'; end if;

    update public.agenda_items
    set item_type=p_item_type,
        title=btrim(p_title),
        description=nullif(btrim(coalesce(p_description,'')),''),
        starts_at=p_starts_at,
        ends_at=p_ends_at,
        all_day=coalesce(p_all_day,false),
        location=nullif(btrim(coalesce(p_location,'')),''),
        audience=p_audience,
        priority=p_priority,
        status=p_status,
        updated_at=now(),
        updated_by=(select auth.uid())
    where id=p_item and club_id=target_club
    returning id into v_id;
  end if;

  select to_jsonb(a) into v_new
  from public.agenda_items a where a.id=v_id;

  perform public.audit_event(
    target_club,
    case when p_item is null then 'agenda_item_created' else 'agenda_item_updated' end,
    'agenda_item',v_id::text,v_old,v_new,null
  );

  if coalesce(p_notify_now,false) and p_status='planned' then
    v_date_label:=to_char(
      p_starts_at at time zone 'Europe/Lisbon','DD/MM/YYYY HH24:MI'
    );
    perform public.agenda_notify_profiles_v1(
      target_club,p_audience,'Agenda: '||btrim(p_title),
      'Novo item na Agenda para '||v_date_label||'.',v_id
    );
  end if;

  return v_id;
end;
$$;

create or replace function public.cancel_agenda_item_v1(
  target_club uuid,p_item uuid,p_reason text default null
)
returns void language plpgsql security definer set search_path=public as $$
declare v_old jsonb; v_new jsonb;
begin
  if not public.can_manage_agenda_v1(target_club) then
    raise exception 'Sem autorização para gerir a Agenda.';
  end if;

  select to_jsonb(a) into v_old
  from public.agenda_items a
  where a.id=p_item and a.club_id=target_club;

  if v_old is null then raise exception 'Item da Agenda não encontrado.'; end if;

  update public.agenda_items
  set status='cancelled',updated_at=now(),updated_by=(select auth.uid())
  where id=p_item and club_id=target_club;

  select to_jsonb(a) into v_new from public.agenda_items a where a.id=p_item;

  perform public.audit_event(
    target_club,'agenda_item_cancelled','agenda_item',
    p_item::text,v_old,v_new,p_reason
  );
end;
$$;

create or replace function public.agenda_calendar_v1(
  target_club uuid,p_from date,p_to date
)
returns table(
  item_id uuid,source_type text,item_kind text,title text,subtitle text,
  starts_at timestamptz,ends_at timestamptz,all_day boolean,priority text,
  item_status text,action_route text,entity_id uuid,can_edit boolean,metadata jsonb
)
language plpgsql stable security definer set search_path=public as $$
declare
  v_member uuid;
  v_manage_agenda boolean;
  v_manage_fees boolean;
  v_view_docs boolean;
  v_sensitive_docs boolean;
  v_manage_events boolean;
begin
  if (select auth.uid()) is null or not public.has_club_access(target_club) then
    raise exception 'Sem acesso ao clube.';
  end if;
  if not public.has_club_permission(target_club,'viewAgenda') then
    raise exception 'Sem permissão para consultar a Agenda.';
  end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>400 then
    raise exception 'Intervalo da Agenda inválido.';
  end if;

  v_member:=public.agenda_current_member_v1(target_club);
  v_manage_agenda:=public.can_manage_agenda_v1(target_club);
  v_manage_fees:=public.has_club_permission(target_club,'manageFees');
  v_view_docs:=public.has_club_permission(target_club,'viewDocuments');
  v_sensitive_docs:=public.has_club_permission(
    target_club,'viewSensitiveDocuments'
  );
  v_manage_events:=public.has_club_permission(target_club,'manageEvents');

  return query
  with years as (
    select generate_series(
      extract(year from p_from)::int,
      extract(year from p_to)::int
    ) as y
  ),
  member_dates as (
    select m.id,'birthday'::text as kind,m.birth_date as src_date,
           'Aniversário — '||coalesce(nullif(m.nickname,''),m.full_name) as label
    from public.members m
    where m.club_id=target_club
      and m.birth_date is not null
      and m.status::text not in ('former','deceased')
    union all
    select m.id,'prospect'::text,m.prospect_joined_at,
           'Prospect — '||coalesce(nullif(m.nickname,''),m.full_name)
    from public.members m
    where m.club_id=target_club
      and m.prospect_joined_at is not null
      and m.status::text not in ('former','deceased')
    union all
    select m.id,'full_colors'::text,m.full_colors_at,
           'Full Colors — '||coalesce(nullif(m.nickname,''),m.full_name)
    from public.members m
    where m.club_id=target_club
      and m.full_colors_at is not null
      and m.status::text not in ('former','deceased')
  ),
  anniversaries as (
    select md.*,public.agenda_anniversary_date_v1(md.src_date,y.y) as agenda_date
    from member_dates md cross join years y
  )
  select
    a.id,'agenda'::text,a.item_type,a.title,
    concat_ws(
      ' · ',
      nullif(a.location,''),
      case when a.audience='direction' then 'Direção' else null end
    ),
    a.starts_at,a.ends_at,a.all_day,a.priority,a.status,
    'agenda'::text,a.id,v_manage_agenda,
    jsonb_build_object('audience',a.audience,'description',a.description)
  from public.agenda_items a
  where a.club_id=target_club
    and a.starts_at < ((p_to+1)::timestamp at time zone 'Europe/Lisbon')
    and coalesce(a.ends_at,a.starts_at) >=
        (p_from::timestamp at time zone 'Europe/Lisbon')
    and (
      a.audience='all'
      or public.can_view_direction_agenda_v1(target_club)
    )

  union all

  select
    e.id,'event'::text,'event'::text,e.name,e.location,
    e.starts_at,e.ends_at,false,'normal'::text,e.status::text,
    'events'::text,e.id,v_manage_events,
    jsonb_build_object('description',e.description)
  from public.events e
  where e.club_id=target_club
    and e.starts_at is not null
    and public.has_club_permission(target_club,'viewEvents')
    and (e.status::text<>'draft' or v_manage_events)
    and e.starts_at < ((p_to+1)::timestamp at time zone 'Europe/Lisbon')
    and coalesce(e.ends_at,e.starts_at) >=
        (p_from::timestamp at time zone 'Europe/Lisbon')

  union all

  select
    an.id,'member'::text,an.kind,an.label,null::text,
    (an.agenda_date::timestamp at time zone 'Europe/Lisbon'),
    null::timestamptz,true,'normal'::text,'active'::text,
    'members'::text,an.id,false,
    jsonb_build_object('original_date',an.src_date,'kind',an.kind)
  from anniversaries an
  where an.agenda_date between p_from and p_to
    and public.has_club_permission(target_club,'viewMembers')

  union all

  select
    wd.id,'weekly_dinner'::text,
    case
      when wd.dinner_kind='extraordinary' then 'dinner_extraordinary'
      else 'dinner'
    end,
    case
      when wd.status='closed' then 'Jantar — Club House fechado'
      else 'Jantar — '||
        coalesce(
          nullif(m.nickname,''),m.full_name,
          nullif(wd.external_name,''),'Por definir'
        )
    end,
    nullif(wd.dish,''),
    (wd.dinner_date::timestamp at time zone 'Europe/Lisbon'),
    null::timestamptz,true,'normal'::text,wd.status,
    'weekly_officer'::text,wd.id,false,
    jsonb_build_object(
      'dinner_kind',wd.dinner_kind,
      'assigned_member_id',wd.assigned_member_id,
      'external_name',wd.external_name
    )
  from public.weekly_dinners wd
  left join public.members m
    on m.id=wd.assigned_member_id and m.club_id=wd.club_id
  where wd.club_id=target_club
    and wd.dinner_date between p_from and p_to

  union all

  select
    d.id,'document'::text,'deadline'::text,
    'Validade — '||d.name,d.category,
    (d.expires_at::timestamp at time zone 'Europe/Lisbon'),
    null::timestamptz,true,
    case when d.expires_at<current_date then 'high' else 'normal' end,
    case when d.expires_at<current_date then 'overdue' else 'planned' end,
    'documents'::text,d.id,false,
    jsonb_build_object('sensitive',d.sensitive,'category',d.category)
  from public.documents d
  where d.club_id=target_club
    and d.expires_at between p_from and p_to
    and v_view_docs
    and (coalesce(d.sensitive,false)=false or v_sensitive_docs)

  union all

  select
    fo.id,'fee'::text,'charge'::text,
    case
      when v_manage_fees then
        'Cobrança — '||coalesce(nullif(m.nickname,''),m.full_name)
      else 'Cobrança pendente'
    end,
    to_char(
      greatest(fo.amount-coalesce(fo.paid_amount,0),0),
      'FM999999990.00'
    )||' €',
    (fo.due_date::timestamp at time zone 'Europe/Lisbon'),
    null::timestamptz,true,
    case when fo.due_date<current_date then 'high' else 'normal' end,
    fo.status::text,'fees'::text,fo.id,false,
    jsonb_build_object(
      'reference_year',fo.reference_year,
      'reference_month',fo.reference_month
    )
  from public.fee_obligations fo
  join public.members m
    on m.id=fo.member_id and m.club_id=fo.club_id
  where fo.club_id=target_club
    and fo.due_date between p_from and p_to
    and fo.status::text in ('pending','partial')
    and (v_manage_fees or fo.member_id=v_member)

  order by starts_at,title;
end;
$$;

alter table public.agenda_items enable row level security;

drop policy if exists agenda_items_select on public.agenda_items;
create policy agenda_items_select
on public.agenda_items
for select to authenticated
using (
  public.has_club_permission(club_id,'viewAgenda')
  and (
    audience='all'
    or public.can_view_direction_agenda_v1(club_id)
  )
);

revoke all on public.agenda_items from anon,authenticated;
grant select on public.agenda_items to authenticated;

revoke execute on function public.can_manage_agenda_v1(uuid)
  from public,anon;
revoke execute on function public.can_view_direction_agenda_v1(uuid)
  from public,anon;
revoke execute on function public.agenda_current_member_v1(uuid)
  from public,anon;
revoke execute on function public.agenda_calendar_v1(uuid,date,date)
  from public,anon;
revoke execute on function public.save_agenda_item_v1(
  uuid,uuid,text,text,text,timestamptz,timestamptz,boolean,
  text,text,text,text,boolean
) from public,anon;
revoke execute on function public.cancel_agenda_item_v1(uuid,uuid,text)
  from public,anon;

grant execute on function public.can_manage_agenda_v1(uuid)
  to authenticated;
grant execute on function public.can_view_direction_agenda_v1(uuid)
  to authenticated;
grant execute on function public.agenda_current_member_v1(uuid)
  to authenticated;
grant execute on function public.agenda_calendar_v1(uuid,date,date)
  to authenticated;
grant execute on function public.save_agenda_item_v1(
  uuid,uuid,text,text,text,timestamptz,timestamptz,boolean,
  text,text,text,text,boolean
) to authenticated;
grant execute on function public.cancel_agenda_item_v1(uuid,uuid,text)
  to authenticated;

revoke execute on function public.agenda_anniversary_date_v1(date,integer)
  from public,anon,authenticated;
revoke execute on function public.agenda_notify_profiles_v1(
  uuid,text,text,text,uuid
) from public,anon,authenticated;

create or replace function public.agenda_touch_updated_v1()
returns trigger language plpgsql set search_path=public as $$
begin
  new.updated_at:=now();
  if (select auth.uid()) is not null then
    new.updated_by:=(select auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_agenda_items_touch on public.agenda_items;
create trigger trg_agenda_items_touch
before update on public.agenda_items
for each row execute function public.agenda_touch_updated_v1();

revoke execute on function public.agenda_touch_updated_v1()
  from public,anon,authenticated;
