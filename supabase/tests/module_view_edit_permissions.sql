-- Local-only behaviour test. All synthetic data and changes roll back.
-- Expected sandbox address is parameterized; default is the isolated authcopy DB.
\set ON_ERROR_STOP on
\if :{?expected_server_ip}
\else
  \set expected_server_ip '192.168.80.2'
\endif
begin;
select set_config('module_test.expected_ip', :'expected_server_ip', true);
do $$ begin
  if current_database()<>'postgres'
    or (current_setting('module_test.expected_ip')='socket'
        and inet_server_addr() is not null)
    or (current_setting('module_test.expected_ip')<>'socket'
        and host(inet_server_addr())<>current_setting('module_test.expected_ip')) then
    raise exception 'Expected isolated local permission-test database';
  end if;
end $$;

select gen_random_uuid() as club_id \gset module_
select gen_random_uuid() as admin_id \gset module_
select gen_random_uuid() as user_id \gset module_
select gen_random_uuid() as unknown_id \gset module_
select gen_random_uuid() as member_id \gset module_
select gen_random_uuid() as request_id \gset module_
insert into auth.users(id,email,raw_user_meta_data) values
  (:'module_admin_id',:'module_admin_id'||'@example.invalid','{"full_name":"Synthetic permission admin"}'::jsonb),
  (:'module_user_id',:'module_user_id'||'@example.invalid','{"full_name":"Synthetic permission user"}'::jsonb),
  (:'module_unknown_id',:'module_unknown_id'||'@example.invalid','{"full_name":"Synthetic default-role user"}'::jsonb);
insert into public.profiles(id,full_name,email) values
  (:'module_admin_id','Synthetic permission admin',:'module_admin_id'||'@example.invalid'),
  (:'module_user_id','Synthetic permission user',:'module_user_id'||'@example.invalid'),
  (:'module_unknown_id','Synthetic default-role user',:'module_unknown_id'||'@example.invalid')
on conflict(id) do nothing;
insert into public.clubs(id,name,slug)
values (:'module_club_id','Synthetic module permissions',:'module_club_id');
select set_config('request.jwt.claim.sub',:'module_admin_id',true);
select set_config('request.jwt.claims',json_build_object('sub',:'module_admin_id','role','authenticated')::text,true);
insert into public.club_memberships(club_id,profile_id,active,access_role) values
  (:'module_club_id',:'module_admin_id',true,'super_admin'),
  (:'module_club_id',:'module_user_id',true,'member'),
  (:'module_club_id',:'module_unknown_id',true,'road_captain');
insert into public.members(id,club_id,profile_id,full_name,status,joined_at)
values (:'module_member_id',:'module_club_id',:'module_user_id','Synthetic member','active',current_date);
insert into public.club_role_permissions(club_id,role_key,permission_key,allowed)
select :'module_club_id','member',p,true from unnest(array[
 'viewDashboard','viewActivity','viewFinancialRequests','manageOwnFinancialRequests',
 'approveExpenseRequests','viewWeeklyOfficer','manageWeeklyOfficer','viewAgenda','manageAgenda'
]) p on conflict(club_id,role_key,permission_key) do update set allowed=excluded.allowed;
insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed)
select :'module_club_id',:'module_user_id',p,false from unnest(array[
 'viewDashboard','viewActivity','viewFinancialRequests','manageOwnFinancialRequests',
 'viewWeeklyOfficer','manageWeeklyOfficer','viewAgenda','manageAgenda','approveExpenseRequests'
]) p on conflict(club_id,profile_id,permission_key) do update set allowed=excluded.allowed;
insert into public.financial_requests(
 id,club_id,member_id,request_type,category,amount,description,status,requested_by
) values (
 :'module_request_id',:'module_club_id',:'module_member_id',
 'reimbursement','reimbursement',12.34,'Synthetic request','draft',:'module_user_id'
);
insert into public.activity_feed(club_id,activity_type,title,metadata,entity_type)
values
 (:'module_club_id','general','Synthetic general','{"module_code":"general"}'::jsonb,'test'),
 (:'module_club_id','financial','Synthetic finance','{"module_code":"financial"}'::jsonb,'financial_request');
insert into public.weekly_dinners(club_id,dinner_date)
values (:'module_club_id',current_date+1);
insert into public.agenda_items(club_id,item_type,title,starts_at,audience)
values (:'module_club_id','meeting','Synthetic agenda',now()+interval '1 day','all');
select set_config('module_test.club',:'module_club_id',true);
select set_config('module_test.admin',:'module_admin_id',true);
select set_config('module_test.user',:'module_user_id',true);
select set_config('module_test.unknown',:'module_unknown_id',true);
select set_config('module_test.request',:'module_request_id',true);

set local role authenticated;
select set_config('request.jwt.claim.sub',:'module_user_id',true);
select set_config('request.jwt.claims',json_build_object('sub',:'module_user_id','role','authenticated')::text,true);
do $$
declare c uuid:=current_setting('module_test.club')::uuid; n bigint; s text; m text;
begin
 if public.module_view_permission('dashboard')<>'viewDashboard'
  or public.module_view_permission('activity')<>'viewActivity'
  or public.module_view_permission('financial_requests')<>'viewFinancialRequests'
  or public.module_view_permission('weekly_officer')<>'viewWeeklyOfficer'
  or public.module_view_permission('agenda')<>'viewAgenda' then raise exception 'Module mapping mismatch'; end if;
 if public.has_club_permission(c,'viewDashboard') or public.has_club_permission(c,'viewActivity')
  or public.has_club_permission(c,'viewFinancialRequests') or public.has_club_permission(c,'viewWeeklyOfficer')
  or public.has_club_permission(c,'viewAgenda') or public.has_club_permission(c,'manageOwnFinancialRequests')
  or public.has_club_permission(c,'manageWeeklyOfficer') or public.has_club_permission(c,'manageAgenda') then
   raise exception 'Per-user deny did not override role allow';
 end if;
 if public.financial_manager_v1(c) then raise exception 'Financial manager ignored module read permission'; end if;
 select count(*) into n from public.activity_feed where club_id=c;
 if n<>0 then raise exception 'Activity RLS leaked without viewActivity'; end if;
 select count(*) into n from public.financial_requests where club_id=c;
 if n<>0 then raise exception 'Financial request RLS leaked without viewFinancialRequests'; end if;
 select count(*) into n from public.weekly_dinners where club_id=c;
 if n<>0 then raise exception 'Weekly Officer RLS leaked without viewWeeklyOfficer'; end if;
 begin perform public.dashboard_summary_rc1(c); raise exception 'Dashboard RPC unexpectedly allowed';
 exception when insufficient_privilege then get stacked diagnostics s=returned_sqlstate; if s<>'42501' then raise; end if; end;
 begin perform * from public.agenda_calendar_v1(c,current_date,current_date+2); raise exception 'Agenda RPC unexpectedly allowed';
 exception when others then get stacked diagnostics m=message_text; if m not like 'Sem permissão para consultar a Agenda%' then raise; end if; end;
 begin
   perform public.save_agenda_item_v1(
     c,null,'meeting','Denied synthetic agenda',null,now()+interval '2 days',null,
     false,null,'all','normal','planned',false
   );
   raise exception 'Agenda edit RPC unexpectedly allowed';
 exception when others then
   get stacked diagnostics s=returned_sqlstate,m=message_text;
   if s<>'P0001' or m<>'Sem autorização para gerir a Agenda.' then raise; end if;
 end;
 begin perform public.create_reimbursement_draft_v1(c,null,10,'Denied'); raise exception 'Own-request RPC unexpectedly allowed';
 exception when insufficient_privilege then get stacked diagnostics s=returned_sqlstate; if s<>'42501' then raise; end if; end;
 begin
   perform public.save_weekly_dinner_v1(
     c,null,current_date+3,null,null,'Denied synthetic dinner',null,'planned'
   );
   raise exception 'Weekly Officer edit RPC unexpectedly allowed';
 exception when insufficient_privilege then
   get stacked diagnostics s=returned_sqlstate;
   if s<>'42501' then raise; end if;
 end;
end $$;

-- A recognized role receives the compatibility default only while no explicit
-- role row exists. The Super Admin can persist a cargo-level block.
select set_config('request.jwt.claim.sub',current_setting('module_test.unknown'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.unknown'),'role','authenticated')::text,true);
do $$
declare c uuid:=current_setting('module_test.club')::uuid;
begin
 if not public.has_club_permission(c,'viewDashboard') then
   raise exception 'Recognized role did not receive its compatibility default';
 end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('module_test.admin'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.admin'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.club_role_permissions(club_id,role_key,permission_key,allowed,updated_by)
values(current_setting('module_test.club')::uuid,'road_captain','viewDashboard',false,current_setting('module_test.admin')::uuid)
on conflict(club_id,role_key,permission_key) do update set allowed=false,updated_by=excluded.updated_by,updated_at=now();
select set_config('request.jwt.claim.sub',current_setting('module_test.unknown'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.unknown'),'role','authenticated')::text,true);
do $$
begin
 if public.has_club_permission(current_setting('module_test.club')::uuid,'viewDashboard') then
   raise exception 'Cargo-level block did not override compatibility default';
 end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('module_test.user'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.user'),'role','authenticated')::text,true);

reset role;
select set_config('request.jwt.claim.sub',current_setting('module_test.admin'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.admin'),'role','authenticated')::text,true);
set local role authenticated;
update public.user_permission_overrides set allowed=true,updated_at=now(),updated_by=current_setting('module_test.admin')::uuid
where club_id=current_setting('module_test.club')::uuid and profile_id=current_setting('module_test.user')::uuid
 and permission_key in ('viewDashboard','viewActivity','viewWeeklyOfficer','viewAgenda');

select set_config('request.jwt.claim.sub',current_setting('module_test.user'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.user'),'role','authenticated')::text,true);
do $$
declare c uuid:=current_setting('module_test.club')::uuid; n bigint; s jsonb; a bigint;
begin
 if not public.has_club_permission(c,'viewDashboard') or not public.has_club_permission(c,'viewActivity')
  or not public.has_club_permission(c,'viewWeeklyOfficer') or not public.has_club_permission(c,'viewAgenda') then
   raise exception 'Per-user allow did not override role deny'; end if;
 s:=public.dashboard_summary_rc1(c); if s is null then raise exception 'Dashboard RPC returned NULL'; end if;
 select count(*) into n from public.activity_feed where club_id=c and title='Synthetic general';
 if n<>1 then raise exception 'Activity fixture missing for authorized user'; end if;
 select count(*) into n from public.activity_feed where club_id=c and title='Synthetic finance';
 if n<>0 then raise exception 'Financial activity bypassed its own view permission'; end if;
 select count(*) into n from public.weekly_dinners where club_id=c;
 if n<>1 then raise exception 'Weekly Officer fixture missing for authorized user'; end if;
 select count(*) into a from public.agenda_calendar_v1(c,current_date,current_date+2);
 if a<1 then raise exception 'Agenda fixture missing for authorized user'; end if;
 if public.can_manage_weekly_officer_v1(c) or public.can_manage_agenda_v1(c) then
  raise exception 'Edit deny override did not block module writes'; end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub',current_setting('module_test.admin'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.admin'),'role','authenticated')::text,true);
set local role authenticated;
update public.user_permission_overrides set allowed=true,updated_at=now(),updated_by=current_setting('module_test.admin')::uuid
where club_id=current_setting('module_test.club')::uuid and profile_id=current_setting('module_test.user')::uuid
 and permission_key in ('viewFinancialRequests','manageOwnFinancialRequests','manageWeeklyOfficer','manageAgenda');

select set_config('request.jwt.claim.sub',current_setting('module_test.user'),true);
select set_config('request.jwt.claims',json_build_object('sub',current_setting('module_test.user'),'role','authenticated')::text,true);
do $$
declare c uuid:=current_setting('module_test.club')::uuid; rid uuid:=current_setting('module_test.request')::uuid;
 n bigint; created uuid; agenda_id uuid; weekly_id uuid;
begin
 select count(*) into n from public.financial_requests where club_id=c;
 if n<>1 then raise exception 'Financial request fixture missing after allow'; end if;
 select count(*) into n from public.activity_feed where club_id=c and title='Synthetic finance';
 if n<>1 then raise exception 'Financial activity fixture missing after allow'; end if;
 if not public.financial_request_edit_access_v1(rid) then raise exception 'Own-request edit allow was not effective'; end if;
 if public.financial_manager_v1(c) then raise exception 'approveExpenseRequests was incorrectly granted'; end if;
 if not public.can_manage_weekly_officer_v1(c) or not public.can_manage_agenda_v1(c) then
  raise exception 'Module edit allow did not reach backend guards'; end if;
 perform public.update_reimbursement_draft_v1(c,rid,13,'Synthetic edit allowed');
 created:=public.create_reimbursement_draft_v1(c,null,10,'Synthetic create allowed');
 if created is null then raise exception 'Own-request create returned no ID'; end if;
 agenda_id:=public.save_agenda_item_v1(
   c,null,'meeting','Allowed synthetic agenda',null,now()+interval '2 days',null,
   false,null,'all','normal','planned',false
 );
 if not exists(select 1 from public.agenda_items where id=agenda_id and club_id=c)
 then raise exception 'Authorized Agenda edit RPC did not persist'; end if;
 weekly_id:=public.save_weekly_dinner_v1(
   c,null,current_date+4,null,null,'Allowed synthetic dinner',null,'planned'
 );
 if not exists(select 1 from public.weekly_dinners where id=weekly_id and club_id=c)
 then raise exception 'Authorized Weekly Officer edit RPC did not persist'; end if;
end $$;
rollback;
