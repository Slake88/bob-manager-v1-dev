-- Align document visibility in the SECURITY DEFINER agenda and global search RPCs with documents_select.
-- No application-facing signatures or non-document behavior are changed.

create or replace function public.agenda_calendar_v1(
  target_club uuid,p_from date,p_to date
)
returns table(
  item_id uuid,source_type text,item_kind text,title text,subtitle text,
  starts_at timestamptz,ends_at timestamptz,all_day boolean,priority text,
  item_status text,action_route text,entity_id uuid,can_edit boolean,metadata jsonb
)
language plpgsql stable security definer set search_path=pg_catalog, public as $$
declare
  v_member uuid;
  v_manage_agenda boolean;
  v_manage_fees boolean;
  v_view_docs boolean;
  v_sensitive_docs boolean;
  v_manage_docs boolean;
  v_profile uuid;
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
  v_manage_docs:=public.has_club_permission(target_club,'manageDocuments');
  v_profile:=(select auth.uid());

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
    -- Keep this visibility predicate aligned with the documents_select policy.
    and (
      (d.scope='personal' and (d.owner_profile_id=v_profile or v_manage_docs))
      or (d.scope='leadership' and v_sensitive_docs)
      or (
        d.scope in ('club','event_gallery','annual_book')
        and v_view_docs
        and (d.sensitive=false or v_sensitive_docs)
      )
    )

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
revoke all on function public.agenda_calendar_v1(uuid,date,date) from public, anon;
grant execute on function public.agenda_calendar_v1(uuid,date,date) to authenticated, service_role;

create or replace function public.global_search_v1(
  target_club uuid,
  search_text text,
  result_limit integer default 30
)
returns table (
  result_type text,
  entity_id uuid,
  parent_id uuid,
  title text,
  subtitle text,
  detail text,
  module_code text,
  score integer
)
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  q text := btrim(coalesce(search_text, ''));
  nq text;
  max_rows integer := greatest(1, least(coalesce(result_limit, 30), 50));
  v_profile uuid;
  v_view_docs boolean;
  v_sensitive_docs boolean;
  v_manage_docs boolean;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not exists (
    select 1
    from public.club_memberships cm
    where cm.club_id = target_club
      and cm.profile_id = auth.uid()
      and cm.active = true
  ) then
    raise exception 'Sem acesso a este clube.';
  end if;

  v_profile := (select auth.uid());
  v_view_docs := public.has_club_permission(target_club, 'viewDocuments');
  v_sensitive_docs := public.has_club_permission(target_club, 'viewSensitiveDocuments');
  v_manage_docs := public.has_club_permission(target_club, 'manageDocuments');

  if char_length(q) < 2 then
    return;
  end if;
  if char_length(q) > 80 then
    q := left(q, 80);
  end if;

  nq := regexp_replace(extensions.unaccent(lower(q)), '[^a-z0-9]+', '', 'g');
  if char_length(nq) < 2 then
    return;
  end if;

  return query
  with candidates as (
    select
      'member'::text as result_type,
      m.id as entity_id,
      null::uuid as parent_id,
      coalesce(nullif(m.nickname, ''), m.full_name) as title,
      concat_ws(' • ', nullif(m.full_name, ''), case when m.member_number is null then null else 'N.º ' || m.member_number::text end, nullif(m.primary_role, '')) as subtitle,
      m.status::text as detail,
      'members'::text as module_code,
      case
        when regexp_replace(extensions.unaccent(lower(coalesce(m.nickname,''))), '[^a-z0-9]+','','g') = nq then 120
        when regexp_replace(extensions.unaccent(lower(coalesce(m.full_name,''))), '[^a-z0-9]+','','g') = nq then 115
        when m.member_number::text = q then 110
        when regexp_replace(extensions.unaccent(lower(coalesce(m.nickname,''))), '[^a-z0-9]+','','g') like nq || '%' then 95
        when regexp_replace(extensions.unaccent(lower(coalesce(m.full_name,''))), '[^a-z0-9]+','','g') like nq || '%' then 90
        else 70
      end as score
    from public.members m
    where m.club_id = target_club
      and public.has_club_permission(target_club, 'viewMembers')
      and (
        regexp_replace(extensions.unaccent(lower(coalesce(m.full_name,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(m.nickname,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(coalesce(m.member_number::text,''), '[^0-9]+','','g') like '%' || nq || '%'
      )

    union all

    select
      'motorcycle',
      mm.id,
      mm.member_id,
      concat_ws(' ', nullif(mm.brand,''), nullif(mm.model,'')) as title,
      concat_ws(' • ', nullif(mm.registration,''), nullif(mm.nickname,''), case when mm.year is null then null else mm.year::text end) as subtitle,
      concat_ws(' • ', coalesce(nullif(m.nickname,''), m.full_name), case when mm.primary_motorcycle then 'Mota principal' else null end) as detail,
      'members',
      case
        when regexp_replace(extensions.unaccent(lower(coalesce(mm.registration,''))), '[^a-z0-9]+','','g') = nq then 130
        when regexp_replace(extensions.unaccent(lower(concat_ws(' ',mm.brand,mm.model))), '[^a-z0-9]+','','g') = nq then 115
        when regexp_replace(extensions.unaccent(lower(coalesce(mm.registration,''))), '[^a-z0-9]+','','g') like nq || '%' then 105
        else 75
      end
    from public.member_motorcycles mm
    join public.members m on m.id = mm.member_id and m.club_id = mm.club_id
    where mm.club_id = target_club
      and mm.active = true
      and public.has_club_permission(target_club, 'viewMembers')
      and (
        regexp_replace(extensions.unaccent(lower(coalesce(mm.brand,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(mm.model,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(mm.registration,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(mm.nickname,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
      )

    union all

    select
      'document',
      d.id,
      null::uuid,
      d.name,
      concat_ws(' • ', nullif(d.category,''), nullif(d.status,''), case when d.document_date is null then null else to_char(d.document_date,'DD/MM/YYYY') end),
      case when d.sensitive then 'Documento sensível' else null end,
      'documents',
      case
        when regexp_replace(extensions.unaccent(lower(coalesce(d.name,''))), '[^a-z0-9]+','','g') = nq then 110
        when regexp_replace(extensions.unaccent(lower(coalesce(d.name,''))), '[^a-z0-9]+','','g') like nq || '%' then 90
        else 65
      end
    from public.documents d
    where d.club_id = target_club
      -- Keep this visibility predicate aligned with the documents_select policy.
      and (
        (d.scope = 'personal' and (d.owner_profile_id = v_profile or v_manage_docs))
        or (d.scope = 'leadership' and v_sensitive_docs)
        or (
          d.scope in ('club','event_gallery','annual_book')
          and v_view_docs
          and (d.sensitive = false or v_sensitive_docs)
        )
      )
      and (
        regexp_replace(extensions.unaccent(lower(coalesce(d.name,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(d.category,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(d.tags,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
      )

    union all

    select
      'product',
      p.id,
      null::uuid,
      p.name,
      concat_ws(' • ', nullif(p.sku,''), nullif(p.category,''), case p.inventory_area when 'bar' then 'Bar' else 'Loja' end),
      case when p.active then 'Ativo' else 'Inativo' end,
      'inventory',
      case
        when regexp_replace(extensions.unaccent(lower(coalesce(p.sku,''))), '[^a-z0-9]+','','g') = nq then 120
        when regexp_replace(extensions.unaccent(lower(coalesce(p.name,''))), '[^a-z0-9]+','','g') = nq then 110
        when regexp_replace(extensions.unaccent(lower(coalesce(p.name,''))), '[^a-z0-9]+','','g') like nq || '%' then 90
        else 65
      end
    from public.products p
    where p.club_id = target_club
      and public.has_club_permission(target_club, 'viewInventory')
      and (
        regexp_replace(extensions.unaccent(lower(coalesce(p.name,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(p.sku,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(p.category,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
      )

    union all

    select
      'event',
      e.id,
      null::uuid,
      e.name,
      concat_ws(' • ', nullif(e.location,''), to_char(e.starts_at at time zone 'Europe/Lisbon','DD/MM/YYYY HH24:MI')),
      e.status::text,
      'events',
      case
        when regexp_replace(extensions.unaccent(lower(coalesce(e.name,''))), '[^a-z0-9]+','','g') = nq then 110
        when regexp_replace(extensions.unaccent(lower(coalesce(e.name,''))), '[^a-z0-9]+','','g') like nq || '%' then 90
        else 65
      end
    from public.events e
    where e.club_id = target_club
      and public.has_club_permission(target_club, 'viewEvents')
      and (
        regexp_replace(extensions.unaccent(lower(coalesce(e.name,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
        or regexp_replace(extensions.unaccent(lower(coalesce(e.location,''))), '[^a-z0-9]+','','g') like '%' || nq || '%'
      )
  )
  select c.result_type, c.entity_id, c.parent_id, c.title, c.subtitle, c.detail, c.module_code, c.score
  from candidates c
  order by c.score desc, c.title asc
  limit max_rows;
end;
$$;
revoke all on function public.global_search_v1(uuid,text,integer) from public, anon;
grant execute on function public.global_search_v1(uuid,text,integer) to authenticated, service_role;
