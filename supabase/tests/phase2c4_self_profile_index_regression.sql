-- NEVER run in production; synthetic fixtures only.
begin;
do $$ begin
  if current_database() not like 'bob_phase2c4_%' or inet_server_addr() is distinct from inet '127.0.0.1' then raise exception 'Local Phase 2C.4 harness required'; end if;
end $$;
do $$ begin
  begin
    update members set profile_id='10000000-0000-0000-0000-000000000001' where full_name='B';
    raise exception 'Duplicate link accepted';
  exception when unique_violation then null; end;
end $$;
insert into members(club_id,full_name,status) select '00000000-0000-0000-0000-000000000001',x,'active' from unnest(array['Null 1','Null 2']) x;
insert into clubs(id,name,slug) values ('00000000-0000-0000-0000-000000000002','Other','other');
insert into club_memberships(club_id,profile_id,active,access_role) values ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001',true,'member');
insert into members(club_id,profile_id,full_name,status) values ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Same user other club','active');
do $$ begin
  if not exists(select 1 from pg_index where indexrelid='public.members_club_profile_unique'::regclass and indisunique and indisvalid and pg_get_expr(indpred,indrelid)='(profile_id IS NOT NULL)') then raise exception 'Index contract'; end if;
end $$;
rollback;
