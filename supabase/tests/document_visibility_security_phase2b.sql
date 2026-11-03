-- LOCAL/DISCARDABLE DATABASE ONLY. All fixtures and temporary helpers are
-- rolled back. Run after applying the Phase 2B and legacy-policy cleanup migrations locally.
-- Never run this test against production.
\set ON_ERROR_STOP on
begin;

create function pg_temp.assert_document_visibility(
  p_club uuid,
  p_token text,
  p_from date,
  p_to date,
  p_expected uuid[],
  p_forbidden uuid[]
) returns void
language plpgsql
as $$
declare
  v_rls_ids uuid[];
  v_agenda_ids uuid[];
  v_search_ids uuid[];
begin
  if current_user <> 'authenticated' then
    raise exception 'Visibility assertions must execute as PostgreSQL role authenticated.';
  end if;

  select coalesce(array_agg(d.id order by d.id), array[]::uuid[])
    into v_rls_ids
  from public.documents d
  where d.club_id = p_club
    and d.name like p_token || '%'
    and d.expires_at between p_from and p_to;

  select coalesce(array_agg(a.entity_id order by a.entity_id), array[]::uuid[])
    into v_agenda_ids
  from public.agenda_calendar_v1(p_club, p_from, p_to) a
  where a.source_type = 'document'
    and a.title like 'Validade — ' || p_token || '%';

  select coalesce(array_agg(s.entity_id order by s.entity_id), array[]::uuid[])
    into v_search_ids
  from public.global_search_v1(p_club, p_token, 50) s
  where s.result_type = 'document'
    and s.title like p_token || '%';

  -- Compare the same controlled document universe in both directions. Agenda
  -- is already constrained to the fixture expiry window by p_from/p_to; Search
  -- uses the common fixture token passed as p_token.
  if exists (
    select id from unnest(v_agenda_ids) as rpc(id)
    except
    select id from unnest(v_rls_ids) as rls(id)
  ) then
    raise exception 'Agenda returned a fixture document denied by RLS. RLS %, Agenda %',
      v_rls_ids, v_agenda_ids;
  end if;
  if exists (
    select id from unnest(v_rls_ids) as rls(id)
    except
    select id from unnest(v_agenda_ids) as rpc(id)
  ) then
    raise exception 'RLS permits a fixture document omitted by Agenda. RLS %, Agenda %',
      v_rls_ids, v_agenda_ids;
  end if;
  if exists (
    select id from unnest(v_search_ids) as rpc(id)
    except
    select id from unnest(v_rls_ids) as rls(id)
  ) then
    raise exception 'Global Search returned a fixture document denied by RLS. RLS %, Search %',
      v_rls_ids, v_search_ids;
  end if;
  if exists (
    select id from unnest(v_rls_ids) as rls(id)
    except
    select id from unnest(v_search_ids) as rpc(id)
  ) then
    raise exception 'RLS permits a fixture document omitted by Global Search. RLS %, Search %',
      v_rls_ids, v_search_ids;
  end if;
  if not (v_agenda_ids @> coalesce(p_expected, array[]::uuid[]))
    or not (v_search_ids @> coalesce(p_expected, array[]::uuid[]))
    or cardinality(v_agenda_ids) <> cardinality(coalesce(p_expected, array[]::uuid[]))
    or cardinality(v_search_ids) <> cardinality(coalesce(p_expected, array[]::uuid[])) then
    raise exception 'Expected documents were not returned by both RPCs. Expected %, Agenda %, Search %',
      p_expected, v_agenda_ids, v_search_ids;
  end if;
  if v_agenda_ids && coalesce(p_forbidden, array[]::uuid[])
    or v_search_ids && coalesce(p_forbidden, array[]::uuid[]) then
    raise exception 'Forbidden document appeared in an RPC. Forbidden %, Agenda %, Search %',
      p_forbidden, v_agenda_ids, v_search_ids;
  end if;
end;
$$;
grant execute on function pg_temp.assert_document_visibility(uuid,text,date,date,uuid[],uuid[])
  to authenticated;

do $$
declare
  agenda_fn regprocedure := 'public.agenda_calendar_v1(uuid,date,date)'::regprocedure;
  search_fn regprocedure := 'public.global_search_v1(uuid,text,integer)'::regprocedure;
  fn_oid oid;
  target_club uuid := gen_random_uuid();
  event_id uuid := gen_random_uuid();
  user_a uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_sensitive uuid := gen_random_uuid();
  user_manager uuid := gen_random_uuid();
  user_personal_only uuid := gen_random_uuid();
  token text := 'phase2b' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  doc_club uuid := gen_random_uuid();
  doc_sensitive uuid := gen_random_uuid();
  doc_personal_a uuid := gen_random_uuid();
  doc_personal_b uuid := gen_random_uuid();
  doc_leadership uuid := gen_random_uuid();
  doc_gallery uuid := gen_random_uuid();
  doc_annual_book uuid := gen_random_uuid();
  doc_personal_only uuid := gen_random_uuid();
  expected_policy_names text[] := array[
    'documents_delete','documents_insert','documents_select','documents_update'
  ];
  actual_policy_names text[];
  policy_row record;
  normalized_qual text;
  normalized_check text;
begin
  if exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='documents'
      and policyname='documents_tenant'
  ) then
    raise exception 'Schema/history regression: legacy documents_tenant policy must be absent.';
  end if;

  select coalesce(array_agg(policyname order by policyname),array[]::text[])
  into actual_policy_names
  from pg_policies where schemaname='public' and tablename='documents';
  if actual_policy_names <> expected_policy_names then
    raise exception 'Expected exactly the four scoped documents policies %, found %.',
      expected_policy_names,actual_policy_names;
  end if;

  for policy_row in
    select policyname,cmd,roles,qual,with_check
    from pg_policies where schemaname='public' and tablename='documents'
  loop
    if policy_row.roles <> array['authenticated']::name[] then
      raise exception 'Policy % has unexpected roles %.',policy_row.policyname,policy_row.roles;
    end if;
    normalized_qual := regexp_replace(lower(coalesce(policy_row.qual,'')),'\s+','','g');
    normalized_check := regexp_replace(lower(coalesce(policy_row.with_check,'')),'\s+','','g');
    if policy_row.policyname='documents_select' then
      if policy_row.cmd <> 'SELECT' or policy_row.qual is null or policy_row.with_check is not null
        or position('has_club_access(club_id)' in normalized_qual)=0
        or position('scope='||chr(39)||'personal'||chr(39) in normalized_qual)=0
        or position('owner_profile_id=' in normalized_qual)=0
        or position('managedocuments' in normalized_qual)=0
        or position('viewsensitivedocuments' in normalized_qual)=0
        or position('viewdocuments' in normalized_qual)=0
        or position('event_gallery' in normalized_qual)=0
        or position('annual_book' in normalized_qual)=0
        or position('sensitive=false' in normalized_qual)=0 then
        raise exception 'documents_select command/roles/qual/with_check do not match the scoped contract: %',policy_row;
      end if;
    elsif policy_row.policyname='documents_insert' then
      if policy_row.cmd <> 'INSERT' or policy_row.qual is not null or policy_row.with_check is null
        or position('created_by=' in normalized_check)=0
        or position('auth.uid()' in normalized_check)=0
        or position('has_club_access(club_id)' in normalized_check)=0
        or position('managedocuments' in normalized_check)=0
        or position('manageeventgallery' in normalized_check)=0
        or position('scope='||chr(39)||'personal'||chr(39) in normalized_check)=0
        or position('event_gallery' in normalized_check)=0 then
        raise exception 'documents_insert command/roles/qual/with_check do not match the scoped contract: %',policy_row;
      end if;
    elsif policy_row.policyname='documents_update' then
      if policy_row.cmd <> 'UPDATE' or policy_row.qual is null or policy_row.with_check is null
        or position('manageeventgallery' in normalized_qual)=0
        or position('managedocuments' in normalized_qual)=0
        or position('owner_profile_id=' in normalized_qual)=0
        or position('has_club_access(club_id)' in normalized_check)=0
        or position('manageeventgallery' in normalized_check)=0
        or position('managedocuments' in normalized_check)=0
        or position('owner_profile_id=' in normalized_check)=0 then
        raise exception 'documents_update command/roles/qual/with_check do not match the scoped contract: %',policy_row;
      end if;
    elsif policy_row.policyname='documents_delete' then
      if policy_row.cmd <> 'DELETE' or policy_row.qual is null or policy_row.with_check is not null
        or position('manageeventgallery' in normalized_qual)=0
        or position('managedocuments' in normalized_qual)=0
        or position('owner_profile_id=' in normalized_qual)=0 then
        raise exception 'documents_delete command/roles/qual/with_check do not match the scoped contract: %',policy_row;
      end if;
    end if;
  end loop;

  if pg_get_function_result(agenda_fn) <> 'TABLE(item_id uuid, source_type text, item_kind text, title text, subtitle text, starts_at timestamp with time zone, ends_at timestamp with time zone, all_day boolean, priority text, item_status text, action_route text, entity_id uuid, can_edit boolean, metadata jsonb)' then
    raise exception 'agenda_calendar_v1 return contract changed: %', pg_get_function_result(agenda_fn);
  end if;
  if pg_get_function_result(search_fn) <> 'TABLE(result_type text, entity_id uuid, parent_id uuid, title text, subtitle text, detail text, module_code text, score integer)' then
    raise exception 'global_search_v1 return contract changed: %', pg_get_function_result(search_fn);
  end if;

  if (select p.provolatile from pg_proc p where p.oid=agenda_fn) <> 's'
    or (select p.provolatile from pg_proc p where p.oid=search_fn) <> 'v' then
    raise exception 'Agenda must remain STABLE and Global Search must remain VOLATILE.';
  end if;
  if (select not p.prosecdef from pg_proc p where p.oid=agenda_fn)
    or (select not p.prosecdef from pg_proc p where p.oid=search_fn) then
    raise exception 'Both RPCs must remain SECURITY DEFINER.';
  end if;
  if not (select p.proconfig @> array['search_path=pg_catalog, public'] from pg_proc p where p.oid=agenda_fn)
    or not (select p.proconfig @> array['search_path=pg_catalog, public, extensions'] from pg_proc p where p.oid=search_fn) then
    raise exception 'SECURITY DEFINER search_path values do not match the hardened contracts.';
  end if;

  for fn_oid in select agenda_fn::oid union all select search_fn::oid loop
    if not has_function_privilege('authenticated', fn_oid, 'EXECUTE')
      or not has_function_privilege('service_role', fn_oid, 'EXECUTE') then
      raise exception 'authenticated and service_role must retain EXECUTE on %.', fn_oid;
    end if;
    if has_function_privilege('anon', fn_oid, 'EXECUTE') then
      raise exception 'anon must not have EXECUTE on %.', fn_oid;
    end if;
    if exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
      where p.oid=fn_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    ) then
      raise exception 'PUBLIC must not have EXECUTE on %.', fn_oid;
    end if;
  end loop;

  insert into public.clubs(id,name) values(target_club,'Phase 2B visibility fixture');
  insert into public.profiles(id,full_name) values
    (user_a,'Phase 2B User A'),
    (user_b,'Phase 2B User B'),
    (user_sensitive,'Phase 2B Sensitive Reader'),
    (user_manager,'Phase 2B Document Manager'),
    (user_personal_only,'Phase 2B Personal Owner');
  insert into public.club_memberships(club_id,profile_id,access_role,active) values
    (target_club,user_a,'member',true),
    (target_club,user_b,'member',true),
    (target_club,user_sensitive,'member',true),
    (target_club,user_manager,'member',true),
    (target_club,user_personal_only,'member',true);
  insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed)
  values
    (target_club,user_a,'viewAgenda',true),
    (target_club,user_a,'viewDocuments',true),
    (target_club,user_b,'viewAgenda',true),
    (target_club,user_b,'viewDocuments',true),
    (target_club,user_sensitive,'viewAgenda',true),
    (target_club,user_sensitive,'viewDocuments',true),
    (target_club,user_sensitive,'viewSensitiveDocuments',true),
    (target_club,user_manager,'viewAgenda',true),
    (target_club,user_manager,'viewDocuments',true),
    (target_club,user_manager,'manageDocuments',true),
    (target_club,user_personal_only,'viewAgenda',true),
    (target_club,user_personal_only,'viewDocuments',false);

  insert into public.events(id,club_id,name)
  values(event_id,target_club,token || '_gallery_event');

  insert into public.documents(
    id,club_id,name,category,document_date,expires_at,status,sensitive,tags,
    scope,owner_profile_id,event_id
  ) values
    (doc_club,target_club,token || '_club','fixture',current_date,current_date+10,'active',false,token,'club',null,null),
    (doc_sensitive,target_club,token || '_club_sensitive','fixture',current_date,current_date+10,'active',true,token,'club',null,null),
    (doc_personal_a,target_club,token || '_personal_a','fixture',current_date,current_date+10,'active',false,token,'personal',user_a,null),
    (doc_personal_b,target_club,token || '_personal_b','fixture',current_date,current_date+10,'active',false,token,'personal',user_b,null),
    (doc_leadership,target_club,token || '_leadership','fixture',current_date,current_date+10,'active',true,token,'leadership',null,null),
    (doc_gallery,target_club,token || '_event_gallery','fixture',current_date,current_date+10,'active',false,token,'event_gallery',null,event_id),
    (doc_annual_book,target_club,token || '_annual_book','fixture',current_date,current_date+10,'active',false,token,'annual_book',null,null),
    (doc_personal_only,target_club,token || '_personal_owner_only','fixture',current_date,current_date+10,'active',false,token,'personal',user_personal_only,null);

  perform set_config('phase2b.club',target_club::text,true);
  perform set_config('phase2b.token',token,true);
  perform set_config('phase2b.from',current_date::text,true);
  perform set_config('phase2b.to',(current_date+30)::text,true);
  perform set_config('phase2b.user_a',user_a::text,true);
  perform set_config('phase2b.user_b',user_b::text,true);
  perform set_config('phase2b.user_sensitive',user_sensitive::text,true);
  perform set_config('phase2b.user_manager',user_manager::text,true);
  perform set_config('phase2b.user_personal_only',user_personal_only::text,true);
  perform set_config('phase2b.doc_club',doc_club::text,true);
  perform set_config('phase2b.doc_sensitive',doc_sensitive::text,true);
  perform set_config('phase2b.doc_personal_a',doc_personal_a::text,true);
  perform set_config('phase2b.doc_personal_b',doc_personal_b::text,true);
  perform set_config('phase2b.doc_leadership',doc_leadership::text,true);
  perform set_config('phase2b.doc_gallery',doc_gallery::text,true);
  perform set_config('phase2b.doc_annual_book',doc_annual_book::text,true);
  perform set_config('phase2b.doc_personal_only',doc_personal_only::text,true);
end;
$$;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2b.user_a'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.assert_document_visibility(
  current_setting('phase2b.club')::uuid,current_setting('phase2b.token'),
  current_setting('phase2b.from')::date,current_setting('phase2b.to')::date,
  array[
    current_setting('phase2b.doc_club')::uuid,
    current_setting('phase2b.doc_personal_a')::uuid,
    current_setting('phase2b.doc_gallery')::uuid,
    current_setting('phase2b.doc_annual_book')::uuid
  ],
  array[
    current_setting('phase2b.doc_sensitive')::uuid,
    current_setting('phase2b.doc_personal_b')::uuid,
    current_setting('phase2b.doc_leadership')::uuid,
    current_setting('phase2b.doc_personal_only')::uuid
  ]
);
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2b.user_b'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.assert_document_visibility(
  current_setting('phase2b.club')::uuid,current_setting('phase2b.token'),
  current_setting('phase2b.from')::date,current_setting('phase2b.to')::date,
  array[
    current_setting('phase2b.doc_club')::uuid,
    current_setting('phase2b.doc_personal_b')::uuid,
    current_setting('phase2b.doc_gallery')::uuid,
    current_setting('phase2b.doc_annual_book')::uuid
  ],
  array[
    current_setting('phase2b.doc_sensitive')::uuid,
    current_setting('phase2b.doc_personal_a')::uuid,
    current_setting('phase2b.doc_leadership')::uuid,
    current_setting('phase2b.doc_personal_only')::uuid
  ]
);
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2b.user_sensitive'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.assert_document_visibility(
  current_setting('phase2b.club')::uuid,current_setting('phase2b.token'),
  current_setting('phase2b.from')::date,current_setting('phase2b.to')::date,
  array[
    current_setting('phase2b.doc_club')::uuid,
    current_setting('phase2b.doc_sensitive')::uuid,
    current_setting('phase2b.doc_leadership')::uuid,
    current_setting('phase2b.doc_gallery')::uuid,
    current_setting('phase2b.doc_annual_book')::uuid
  ],
  array[
    current_setting('phase2b.doc_personal_a')::uuid,
    current_setting('phase2b.doc_personal_b')::uuid,
    current_setting('phase2b.doc_personal_only')::uuid
  ]
);
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2b.user_manager'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.assert_document_visibility(
  current_setting('phase2b.club')::uuid,current_setting('phase2b.token'),
  current_setting('phase2b.from')::date,current_setting('phase2b.to')::date,
  array[
    current_setting('phase2b.doc_club')::uuid,
    current_setting('phase2b.doc_personal_a')::uuid,
    current_setting('phase2b.doc_personal_b')::uuid,
    current_setting('phase2b.doc_personal_only')::uuid,
    current_setting('phase2b.doc_gallery')::uuid,
    current_setting('phase2b.doc_annual_book')::uuid
  ],
  array[
    current_setting('phase2b.doc_sensitive')::uuid,
    current_setting('phase2b.doc_leadership')::uuid
  ]
);
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2b.user_personal_only'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.assert_document_visibility(
  current_setting('phase2b.club')::uuid,current_setting('phase2b.token'),
  current_setting('phase2b.from')::date,current_setting('phase2b.to')::date,
  array[current_setting('phase2b.doc_personal_only')::uuid],
  array[
    current_setting('phase2b.doc_club')::uuid,
    current_setting('phase2b.doc_sensitive')::uuid,
    current_setting('phase2b.doc_personal_a')::uuid,
    current_setting('phase2b.doc_personal_b')::uuid,
    current_setting('phase2b.doc_leadership')::uuid,
    current_setting('phase2b.doc_gallery')::uuid,
    current_setting('phase2b.doc_annual_book')::uuid
  ]
);
reset role;

rollback;
