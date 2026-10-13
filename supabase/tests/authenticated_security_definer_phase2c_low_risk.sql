-- LOCAL/DISCARDABLE DATABASE ONLY. Apply all repository migrations first.
-- This test writes fixtures only inside this transaction and rolls them back.
-- The database-name guard is intentional. Never run this test against production.
\set ON_ERROR_STOP on
begin;

do $$
begin
  if current_database() <> 'bob_dinner_test' then
    raise exception 'Disposable local database bob_dinner_test required; refusing to run.';
  end if;
  if to_regrole('anon') is null or to_regrole('authenticated') is null
    or to_regrole('service_role') is null then
    raise exception 'Supabase local roles anon, authenticated and service_role are required.';
  end if;
end;
$$;

create function pg_temp.assert_true(p_value boolean,p_message text)
returns void language plpgsql as $$
begin
  if p_value is distinct from true then
    raise exception 'Assertion failed: %',p_message;
  end if;
end;
$$;

create function pg_temp.expect_sqlstate(p_statement text,p_expected_state text,p_message text)
returns void language plpgsql as $$
declare
  v_state text;
begin
  begin
    execute p_statement;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    if p_expected_state is not null and v_state <> p_expected_state then
      raise exception 'Expected SQLSTATE %, got % for %: %',p_expected_state,v_state,p_message,sqlerrm;
    end if;
    return;
  end;
  raise exception 'Expected rejection: %',p_message;
end;
$$;
grant execute on function pg_temp.assert_true(boolean,text)
  to anon,authenticated,service_role;
grant execute on function pg_temp.expect_sqlstate(text,text,text)
  to anon,authenticated,service_role;

do $$
declare
  v_members oid := 'public.members'::regclass;
  v_profiles oid := 'public.profiles'::regclass;
  v_profile_att smallint;
  v_club_att smallint;
  v_profiles_id_att smallint;
  v_fk_count integer;
  v_index_ok boolean;
begin
  select attnum into v_profile_att
  from pg_attribute where attrelid=v_members and attname='profile_id' and not attisdropped;
  if v_profile_att is null or not exists (
    select 1 from pg_attribute where attrelid=v_members and attname='profile_id'
      and atttypid='uuid'::regtype and not attnotnull and not attisdropped
  ) then
    raise exception 'members.profile_id must exist as nullable uuid in the migrated schema';
  end if;

  select attnum into v_club_att
  from pg_attribute where attrelid=v_members and attname='club_id' and not attisdropped;
  select attnum into v_profiles_id_att
  from pg_attribute where attrelid=v_profiles and attname='id' and not attisdropped;

  select count(*) into v_fk_count
  from pg_constraint c
  where c.conrelid=v_members and c.contype='f' and c.confrelid=v_profiles
    and cardinality(c.conkey)=1 and c.conkey[1]=v_profile_att
    and cardinality(c.confkey)=1 and c.confkey[1]=v_profiles_id_att
    and c.confdeltype='n' and c.convalidated;
  if v_fk_count <> 1 then
    raise exception 'expected exactly one validated profile_id -> profiles(id) ON DELETE SET NULL FK; got %',v_fk_count;
  end if;

  select exists (
    select 1 from pg_index i
    join pg_class ix on ix.oid=i.indexrelid
    where i.indrelid=v_members and ix.relname='members_profile_id_idx'
      and i.indisvalid and i.indisready and not i.indisunique
      and i.indnkeyatts=1 and i.indkey[0]=v_profile_att
      and i.indpred is not null
      and replace(replace(replace(lower(pg_get_expr(i.indpred,i.indrelid)),' ',''),'(',''),')','')
        ='profile_idisnotnull'
  ) into v_index_ok;
  if not v_index_ok then
    raise exception 'members_profile_id_idx must index (profile_id) where profile_id is not null';
  end if;

  select exists (
    select 1 from pg_index i
    join pg_class ix on ix.oid=i.indexrelid
    where i.indrelid=v_members and ix.relname='members_club_profile_idx'
      and i.indisvalid and i.indisready and not i.indisunique
      and i.indnkeyatts=2 and i.indkey[0]=v_club_att and i.indkey[1]=v_profile_att
      and i.indpred is not null
      and replace(replace(replace(lower(pg_get_expr(i.indpred,i.indrelid)),' ',''),'(',''),')','')
        ='profile_idisnotnull'
  ) into v_index_ok;
  if not v_index_ok then
    raise exception 'members_club_profile_idx must index (club_id, profile_id) where profile_id is not null';
  end if;
end;
$$;

do $$
declare
  v_functions oid[] := array[
    'public.generate_euromillions_charges_v1(uuid,integer,integer)'::regprocedure::oid,
    'public.sync_euromillions_players_v1(uuid)'::regprocedure::oid,
    'public.ensure_weekly_officer_schedule_v1(uuid,integer)'::regprocedure::oid,
    'public.update_own_member_profile_v1(uuid,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure::oid,
    'public.update_own_member_profile_v2(uuid,text,text,text,text,text,text,text,text,text,text,text,text)'::regprocedure::oid
  ];
  v_expected_results text[] := array['void','void','integer','uuid','uuid'];
  v_oid oid;
  v_i integer;
  v_result text;
  v_path text[];
  v_is_definer boolean;
  v_volatility "char";
  v_default_count integer;
  v_public_execute boolean;
  v_expected_service_role boolean;
begin
  for v_i in 1..array_length(v_functions,1) loop
    v_oid := v_functions[v_i];
    select pg_get_function_result(p.oid),p.proconfig,p.prosecdef,p.provolatile,p.pronargdefaults
      into v_result,v_path,v_is_definer,v_volatility,v_default_count
    from pg_proc p where p.oid=v_oid;

    if v_result <> v_expected_results[v_i] then
      raise exception 'Return contract changed for %: %',v_oid,v_result;
    end if;
    if v_is_definer is distinct from true or v_volatility <> 'v' then
      raise exception '% must remain VOLATILE SECURITY DEFINER.',v_oid;
    end if;
    if v_path is distinct from array['search_path=pg_catalog, public, pg_temp']::text[] then
      raise exception 'Unexpected function settings for %: %',v_oid,v_path;
    end if;
    if v_default_count <> 0 then
      raise exception 'Unexpected default arguments for %: %',v_oid,v_default_count;
    end if;
    if has_function_privilege('anon',v_oid,'EXECUTE') then
      raise exception 'anon must not execute %.',v_oid;
    end if;
    if not has_function_privilege('authenticated',v_oid,'EXECUTE') then
      raise exception 'authenticated must retain EXECUTE on %.',v_oid;
    end if;

    select exists (
      select 1
      from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) acl
      where p.oid=v_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    ) into v_public_execute;
    if v_public_execute then
      raise exception 'PUBLIC must not execute %.',v_oid;
    end if;

    v_expected_service_role := true;
    if has_function_privilege('service_role',v_oid,'EXECUTE') is distinct from v_expected_service_role then
      raise exception 'Unexpected service_role EXECUTE state for %: expected %, got %.',
        v_oid,v_expected_service_role,has_function_privilege('service_role',v_oid,'EXECUTE');
    end if;
  end loop;
end;
$$;

do $$
declare
  v_club uuid := gen_random_uuid();
  v_member_profile uuid := gen_random_uuid();
  v_other_profile uuid := gen_random_uuid();
  v_unrelated_profile uuid := gen_random_uuid();
  v_member uuid := gen_random_uuid();
  v_other_member uuid := gen_random_uuid();
begin
  insert into public.clubs(id,name) values(v_club,'Phase 2C.1 disposable fixture');
  insert into public.profiles(id,full_name) values
    (v_member_profile,'Phase 2C.1 member'),
    (v_other_profile,'Phase 2C.1 other member'),
    (v_unrelated_profile,'Phase 2C.1 no club access');
  insert into public.club_memberships(club_id,profile_id,active)
  values(v_club,v_member_profile,true);
  insert into public.members(id,club_id,full_name,status,profile_id,email,tax_number)
  values
    (v_member,v_club,'Phase 2C.1 member','active',v_member_profile,'before@example.test','BEFORE-A'),
    (v_other_member,v_club,'Phase 2C.1 other member','active',v_other_profile,'other@example.test','BEFORE-B');

  perform set_config('phase2c.club',v_club::text,true);
  perform set_config('phase2c.member_profile',v_member_profile::text,true);
  perform set_config('phase2c.unrelated_profile',v_unrelated_profile::text,true);
  perform set_config('phase2c.member',v_member::text,true);
  perform set_config('phase2c.other_member',v_other_member::text,true);
end;
$$;

-- A role with no user identity reaches the new explicit authentication guard.
select set_config('request.jwt.claims',jsonb_build_object('role','authenticated')::text,true);
set local role authenticated;
select pg_temp.expect_sqlstate(
  format('select public.sync_euromillions_players_v1(%L::uuid)',current_setting('phase2c.club')),
  '42501','unauthenticated Euromillions player sync'
);
select pg_temp.expect_sqlstate(
  format('select public.generate_euromillions_charges_v1(%L::uuid,2099,1)',current_setting('phase2c.club')),
  '42501','unauthenticated Euromillions charge generation'
);
reset role;

-- anon has no direct EXECUTE even though the two RPCs retain service_role access.
select set_config('request.jwt.claims',jsonb_build_object('role','anon')::text,true);
set local role anon;
select pg_temp.expect_sqlstate(
  format('select public.sync_euromillions_players_v1(%L::uuid)',current_setting('phase2c.club')),
  '42501','anon player sync is denied by ACL'
);
select pg_temp.expect_sqlstate(
  format('select public.generate_euromillions_charges_v1(%L::uuid,2099,1)',current_setting('phase2c.club')),
  '42501','anon charge generation is denied by ACL'
);
reset role;

-- service_role keeps the existing effective EXECUTE grants, but cannot bypass
-- the RPCs' internal authentication and club authorization checks.
select set_config('request.jwt.claims',jsonb_build_object('role','service_role')::text,true);
set local role service_role;
select pg_temp.expect_sqlstate(
  format('select public.sync_euromillions_players_v1(%L::uuid)',current_setting('phase2c.club')),
  '42501','service_role must not bypass the player-sync auth guard'
);
select pg_temp.expect_sqlstate(
  format('select public.generate_euromillions_charges_v1(%L::uuid,2099,1)',current_setting('phase2c.club')),
  '42501','service_role must not bypass the charge-generation auth guard'
);
select pg_temp.expect_sqlstate(
  format('select public.ensure_weekly_officer_schedule_v1(%L::uuid,2099)',current_setting('phase2c.club')),
  null,'service_role must not bypass weekly schedule authorization'
);
select pg_temp.expect_sqlstate(
  format('select public.update_own_member_profile_v1(%L::uuid,null,null,null,null,null,null,null,null,null,null,null)',current_setting('phase2c.club')),
  '42501','service_role must not bypass profile v1 authentication guard'
);
select pg_temp.expect_sqlstate(
  format('select public.update_own_member_profile_v2(%L::uuid,null,null,null,null,null,null,null,null,null,null,null,null)',current_setting('phase2c.club')),
  '42501','service_role must not bypass profile v2 authentication guard'
);
reset role;

-- A club member retains each previously allowed operation. All writes are rolled back.
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2c.member_profile'),'role','authenticated'
)::text,true);
set local role authenticated;
select public.sync_euromillions_players_v1(current_setting('phase2c.club')::uuid);
select pg_temp.assert_true(
  public.update_own_member_profile_v1(
    target_club => current_setting('phase2c.club')::uuid,
    p_email => 'member-v1@example.test',p_phone => '111',p_address => '{"street":"Rua A"}',
    p_postal_code => '1000-001',p_locality => 'Lisboa',p_emergency_name => 'Contact A',
    p_emergency_relation => 'Friend',p_emergency_phone => '222',p_blood_type => 'O+',
    p_allergies => 'none',p_medical_notes => 'fixture'
  )=current_setting('phase2c.member')::uuid,
  'authenticated member can update own profile through v1'
);
select pg_temp.assert_true(
  public.update_own_member_profile_v2(
    target_club => current_setting('phase2c.club')::uuid,
    p_email => 'member-v2@example.test',p_phone => '333',p_address => '{"street":"Rua B"}',
    p_postal_code => '1000-002',p_locality => 'Porto',p_tax_number => 'AFTER-A',
    p_emergency_name => 'Contact B',p_emergency_relation => 'Family',
    p_emergency_phone => '444',p_blood_type => 'A+',p_allergies => 'none',
    p_medical_notes => 'fixture v2'
  )=current_setting('phase2c.member')::uuid,
  'authenticated member can update own profile through v2'
);
select pg_temp.assert_true(
  public.ensure_weekly_officer_schedule_v1(
    current_setting('phase2c.club')::uuid,
    extract(year from current_date)::integer-1
  )=0,
  'valid historical year remains a no-op'
);
select pg_temp.expect_sqlstate(
  format('select public.ensure_weekly_officer_schedule_v1(%L::uuid,2019)',current_setting('phase2c.club')),
  null,'year below the existing minimum remains rejected'
);
select pg_temp.expect_sqlstate(
  format('select public.ensure_weekly_officer_schedule_v1(%L::uuid,2101)',current_setting('phase2c.club')),
  null,'year above the existing maximum remains rejected'
);
reset role;

-- The charge generator still synchronizes members and creates charges for active players.
update public.euromillions_players set status='active'
where club_id=current_setting('phase2c.club')::uuid;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2c.member_profile'),'role','authenticated'
)::text,true);
set local role authenticated;
select public.generate_euromillions_charges_v1(current_setting('phase2c.club')::uuid,2099,1);
reset role;
select pg_temp.assert_true(
  exists(select 1 from public.euromillions_players where club_id=current_setting('phase2c.club')::uuid)
  and exists(select 1 from public.euromillions_draw_charges where club_id=current_setting('phase2c.club')::uuid),
  'authorized member retains player synchronization and charge generation'
);

-- A signed-in profile without membership remains rejected by all five RPCs.
select set_config('request.jwt.claims',jsonb_build_object(
  'sub',current_setting('phase2c.unrelated_profile'),'role','authenticated'
)::text,true);
set local role authenticated;
select pg_temp.expect_sqlstate(
  format('select public.sync_euromillions_players_v1(%L::uuid)',current_setting('phase2c.club')),
  null,'non-member player sync is denied'
);
select pg_temp.expect_sqlstate(
  format('select public.generate_euromillions_charges_v1(%L::uuid,2099,1)',current_setting('phase2c.club')),
  null,'non-member charge generation is denied'
);
select pg_temp.expect_sqlstate(
  format('select public.ensure_weekly_officer_schedule_v1(%L::uuid,2099)',current_setting('phase2c.club')),
  null,'non-member weekly schedule generation is denied'
);
select pg_temp.expect_sqlstate(
  format('select public.update_own_member_profile_v1(%L::uuid,null,null,null,null,null,null,null,null,null,null,null)',current_setting('phase2c.club')),
  '42501','non-member profile v1 update is denied'
);
select pg_temp.expect_sqlstate(
  format('select public.update_own_member_profile_v2(%L::uuid,null,null,null,null,null,null,null,null,null,null,null,null)',current_setting('phase2c.club')),
  '42501','non-member profile v2 update is denied'
);
reset role;

-- The authenticated profile update never changes another member's row.
select pg_temp.assert_true(
  (select email='member-v2@example.test' and tax_number='AFTER-A'
    from public.members where id=current_setting('phase2c.member')::uuid)
  and
  (select email='other@example.test' and tax_number='BEFORE-B'
    from public.members where id=current_setting('phase2c.other_member')::uuid),
  'profile RPCs update only the row whose profile_id equals auth.uid()'
);

rollback;
