-- NEVER run in production. Fixed-loopback harness restores schema, no real data.
begin;
do $$ begin
  if current_database() not like 'bob_phase2c4_%' or inet_server_addr() is distinct from inet '127.0.0.1' then
    raise exception 'Local Phase 2C.4 harness required';
  end if;
end $$;

insert into auth.users(id) select ('10000000-0000-0000-0000-00000000000'||n)::uuid from generate_series(1,3) n;
insert into clubs(id,name,slug) values ('00000000-0000-0000-0000-000000000001','Fixture','fixture'),('00000000-0000-0000-0000-000000000002','Other','other');
insert into profiles(id,full_name,email) select id,'Fixture',id||'@example.invalid' from auth.users;
insert into club_memberships(club_id,profile_id,active,access_role)
select '00000000-0000-0000-0000-000000000001',id,true,'member' from auth.users where id<>'10000000-0000-0000-0000-000000000003';
insert into club_memberships(club_id,profile_id,active,access_role) values ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000003',true,'member');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into club_role_permissions(club_id,role_key,permission_key,allowed)
select id,'member',p,true from clubs cross join unnest(array['viewMembers','editOwnMemberProfile']) p where id='00000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into members(id,club_id,profile_id,full_name,status,tax_number,emergency_contact) values
('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Own','active','123456789','{"custom":"keep","contact_name":"legacy"}'),
('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001',null,'Other','active',null,'{}');

-- Exercise each exact signature as the API role. Checks errors AND messages.
create function pg_temp.call_profile(version integer) returns uuid language plpgsql as $$ begin
  if version=1 then
    return public.update_own_member_profile_v1('00000000-0000-0000-0000-000000000001',' email@example.invalid ',' phone ',' address ',' postal ',' locality ',' name ',' relation ',' emergency ',' O+ ',' allergy ',' note ');
  end if;
  return public.update_own_member_profile_v2('00000000-0000-0000-0000-000000000001',' email@example.invalid ',' phone ',' address ',' postal ',' locality ',' 987654321 ',' name ',' relation ',' emergency ',' O+ ',' allergy ',' note ');
end $$;
create function pg_temp.expect_profile_error(code text,message text) returns void language plpgsql as $$ declare v integer; begin
  for v in 1..2 loop
    begin
      perform pg_temp.call_profile(v);
      raise exception 'RPC v% unexpectedly accepted request',v;
    exception when others then
      if sqlstate<>code or sqlerrm<>message then raise; end if;
    end;
  end loop;
end $$;
do $$ declare s text; begin
  foreach s in array array[
    'public.update_own_member_profile_v1(uuid,text,text,text,text,text,text,text,text,text,text,text)',
    'public.update_own_member_profile_v2(uuid,text,text,text,text,text,text,text,text,text,text,text,text)'] loop
    if not has_function_privilege('authenticated',s,'EXECUTE') or not has_function_privilege('service_role',s,'EXECUTE')
      or has_function_privilege('anon',s,'EXECUTE') then raise exception 'ACL regression: %',s; end if;
    if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=s::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE') then raise exception 'PUBLIC execute'; end if;
    if not exists(select 1 from pg_proc where oid=s::regprocedure and prosecdef and 'search_path=pg_catalog, public, pg_temp'=any(proconfig)) then raise exception 'Function security regression'; end if;
  end loop;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.expect_profile_error('42501','Authentication required');
reset role;
set local role service_role;
select pg_temp.expect_profile_error('42501','Authentication required');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
set local role authenticated;
select pg_temp.expect_profile_error('42501','Club access denied');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update club_role_permissions set allowed=false where permission_key='editOwnMemberProfile';
-- manageMembers never substitutes for the own-profile permission.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into club_role_permissions(club_id,role_key,permission_key,allowed) values ('00000000-0000-0000-0000-000000000001','member','manageMembers',true);
set local role authenticated;
select pg_temp.expect_profile_error('42501','Own member profile edit permission denied');
reset role;
insert into user_permission_overrides(club_id,profile_id,permission_key,allowed) values ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','editOwnMemberProfile',true);
set local role authenticated;
select pg_temp.call_profile(1);
reset role;
do $$ begin
  if not exists(select 1 from members where full_name='Own' and tax_number='123456789' and email='email@example.invalid' and phone='phone' and address='address' and postal_code='postal' and locality='locality' and updated_by=auth.uid()
    and emergency_contact='{"custom":"keep","name":"name","relation":"relation","phone":"emergency","blood_type":"O+","allergies":"allergy","medical_notes":"note"}'::jsonb)
    then raise exception 'v1 field contract'; end if;
end $$;
set local role authenticated;
select pg_temp.call_profile(2);
reset role;
do $$ begin
  if not exists(select 1 from members where full_name='Own' and tax_number='987654321' and email='email@example.invalid' and phone='phone' and address='address' and postal_code='postal' and locality='locality' and updated_by=auth.uid()
    and emergency_contact='{"custom":"keep","name":"name","relation":"relation","phone":"emergency","blood_type":"O+","allergies":"allergy","medical_notes":"note"}'::jsonb)
    or exists(select 1 from members where full_name='Other' and email is not null) then raise exception 'v2 field/isolation contract'; end if;
end $$;
update club_role_permissions set allowed=true where permission_key='editOwnMemberProfile';
update user_permission_overrides set allowed=false;
set local role authenticated;
select pg_temp.expect_profile_error('42501','Own member profile edit permission denied');
reset role;
delete from user_permission_overrides;
update club_memberships set active=false where profile_id=auth.uid();
set local role authenticated;
select pg_temp.expect_profile_error('42501','Club access denied');
reset role;
update club_memberships set active=true where profile_id=auth.uid();
set local role service_role;
do $$ begin
  if pg_temp.call_profile(1)<>'20000000-0000-0000-0000-000000000001'::uuid
    or pg_temp.call_profile(2)<>'20000000-0000-0000-0000-000000000001'::uuid then raise exception 'RPC return contract'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.expect_profile_error('42501','No member profile linked to current user');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update members set profile_id=auth.uid() where full_name='Other';
set local role authenticated;
select pg_temp.expect_profile_error('21000','Multiple member profiles linked to current user in this club');
reset role;
do $$ begin
  if exists(select 1 from members where full_name='Other' and email is not null) then raise exception 'Duplicate path wrote a row'; end if;
end $$;
update members set profile_id=null where full_name='Other';
set local role authenticated;
select public.update_own_member_profile_v1('00000000-0000-0000-0000-000000000001',null,' ',null,' ',null,null,null,null,null,null,null);
select public.update_own_member_profile_v2('00000000-0000-0000-0000-000000000001',null,' ',null,' ',null,' ',null,null,null,null,null,null);
reset role;
do $$ begin
  if not exists(select 1 from members where full_name='Own' and email is null and phone is null and address is null and postal_code is null and locality is null and tax_number is null and emergency_contact='{"custom":"keep"}'::jsonb) then raise exception 'Null/blank clearing contract'; end if;
end $$;
rollback;
