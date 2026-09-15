create extension if not exists unaccent with schema extensions;

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
set search_path = public, extensions
as $$
declare
  q text := btrim(coalesce(search_text, ''));
  nq text;
  max_rows integer := greatest(1, least(coalesce(result_limit, 30), 50));
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
      and public.has_club_permission(target_club, 'viewDocuments')
      and (not d.sensitive or public.has_club_permission(target_club, 'viewSensitiveDocuments'))
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
