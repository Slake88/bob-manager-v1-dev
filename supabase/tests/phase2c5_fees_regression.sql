-- Local fixtures only. Never run in production.
begin;
do $$ begin
 if current_database() not like 'bob_phase2c5_%' or inet_server_addr() is distinct from inet '127.0.0.1' then raise exception 'Local harness required'; end if;
end $$;
insert into auth.users(id) values ('10000000-0000-0000-0000-000000000001'),('10000000-0000-0000-0000-000000000002');
insert into clubs(id,name,slug) values ('00000000-0000-0000-0000-000000000001','Fixture','fixture'),('00000000-0000-0000-0000-000000000002','Other','other');
insert into profiles(id,full_name,email) select id,'Fixture',id||'@example.invalid' from auth.users;
insert into club_memberships(club_id,profile_id,active,access_role) values ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'member');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into club_memberships(club_id,profile_id,active,access_role) values ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',true,'member');
insert into club_role_permissions(club_id,role_key,permission_key,allowed) values ('00000000-0000-0000-0000-000000000001','member','manageFees',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
insert into members(id,club_id,full_name,status,joined_at) values
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Current','active',make_date(extract(year from current_timestamp at time zone 'Europe/Lisbon')::int,1,1)),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','Historical','active',date '2020-01-01'),
 ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','Other','active',date '2020-01-01');
insert into club_settings(club_id,key,value) values
 ('00000000-0000-0000-0000-000000000001','monthly_fee_amount','25'),
 ('00000000-0000-0000-0000-000000000001','registration_fee_amount','10');
update members set status=status;
do $$ begin if exists(select 1 from fee_obligations) then raise exception 'Implicit generation'; end if; end $$;
create function pg_temp.prepare(y integer) returns void language sql as $$ select public.prepare_member_fees_year_v1('00000000-0000-0000-0000-000000000001',y) $$;
create function pg_temp.expect_error(y integer,expected text) returns void language plpgsql as $$ begin
 begin perform pg_temp.prepare(y); raise exception 'Unexpected success';
 exception when others then if sqlstate<>expected then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.expect_error(2099,'42501');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
select pg_temp.expect_error(2099,'42501');
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
update club_memberships set active=false;
set local role authenticated;
select pg_temp.expect_error(2099,'42501');
reset role;
update club_memberships set active=true;
update club_role_permissions set allowed=false;
set local role authenticated;
select pg_temp.expect_error(2099,'42501');
reset role;
insert into user_permission_overrides(club_id,profile_id,permission_key,allowed) values ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','manageFees',true);
set local role authenticated;
select pg_temp.expect_error(null,'22023');
select pg_temp.expect_error(2101,'22023');
select pg_temp.expect_error(extract(year from current_timestamp at time zone 'Europe/Lisbon')::int-1,'22023');
select pg_temp.prepare(extract(year from current_timestamp at time zone 'Europe/Lisbon')::int);
reset role;
do $$ begin
 if (select count(*) from fee_obligations where obligation_type='monthly')<>24 or (select count(*) from fee_obligations where obligation_type='registration')<>1 then raise exception 'Generation counts'; end if;
 if exists(select 1 from fee_obligations where member_id='20000000-0000-0000-0000-000000000003') then raise exception 'Cross club write'; end if;
 if exists(select 1 from fee_obligations where reference_year<extract(year from current_timestamp at time zone 'Europe/Lisbon')::int) then raise exception 'Historical registration'; end if;
end $$;
create temp table preserved as select id,to_jsonb(o) as data from fee_obligations o;
update club_settings set value='30' where key='monthly_fee_amount';
set local role authenticated;
select pg_temp.prepare(extract(year from current_timestamp at time zone 'Europe/Lisbon')::int);
select pg_temp.prepare(extract(year from current_timestamp at time zone 'Europe/Lisbon')::int+1);
reset role;
do $$ declare sig text; begin
 if exists(select 1 from preserved p left join fee_obligations o using(id) where p.data is distinct from to_jsonb(o)) then raise exception 'Existing history changed'; end if;
 if (select count(*) from fee_obligations where obligation_type='monthly')<>48 or (select count(*) from fee_obligations where obligation_type='registration')<>1 then raise exception 'Future generation counts'; end if;
 foreach sig in array array['public.sync_member_fee_obligations_v1(uuid,integer,uuid)','public.generate_monthly_fees(uuid,integer,uuid)','public.generate_member_fees_internal(uuid,integer)','public.member_fee_autogenerate_trigger()','bob_fees_private.generate_member_fees(uuid,integer)'] loop
 if has_function_privilege('authenticated',sig,'execute') or has_function_privilege('service_role',sig,'execute') or has_function_privilege('anon',sig,'execute') then raise exception 'Legacy/helper grant: %',sig; end if;
 end loop;
 if has_function_privilege('service_role','public.prepare_member_fees_year_v1(uuid,integer)','execute') or has_function_privilege('anon','public.prepare_member_fees_year_v1(uuid,integer)','execute') then raise exception 'Public ACL'; end if;
 if exists(select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a where p.oid='public.prepare_member_fees_year_v1(uuid,integer)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE') then raise exception 'PUBLIC grant'; end if;
 if not exists(select 1 from pg_proc where oid='public.prepare_member_fees_year_v1(uuid,integer)'::regprocedure and prosecdef and 'search_path=pg_catalog, public, pg_temp'=any(proconfig)) then raise exception 'Security attributes'; end if;
 if exists(select 1 from pg_trigger where tgrelid='public.members'::regclass and tgname='trg_member_fee_autogenerate') then raise exception 'Autogeneration trigger remains'; end if;
end $$;
update user_permission_overrides set allowed=false;
set local role authenticated;
select pg_temp.expect_error(2099,'42501');
reset role;
rollback;
