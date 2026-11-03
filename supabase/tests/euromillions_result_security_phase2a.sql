-- LOCAL ONLY: run as the local postgres role against a disposable Supabase DB
-- after applying the Phase 2A migration. Fixture club requirements:
--   * an active member with viewLottery but without an elevated role;
--   * an active treasurer;
--   * no active Euromilhões players;
--   * no result rows on the two test Tuesdays selected below.
-- The postgres connection is required to prepare/inspect fixtures and SET ROLE.
-- All database writes are rolled back. Never run against production.
-- psql postgresql://postgres:...@localhost:54322/postgres \
--   -v club_id=... -v member_profile_id=... -v treasurer_profile_id=... \
--   -f supabase/tests/euromillions_result_security_phase2a.sql
\set ON_ERROR_STOP on
begin;
select set_config('phase2a.club', :'club_id', true);
select set_config('phase2a.member_profile', :'member_profile_id', true);
select set_config('phase2a.treasurer_profile', :'treasurer_profile_id', true);

create function pg_temp.expect_rejected(
  p_date date,
  p_draw_number text,
  p_numbers integer[],
  p_stars integer[],
  p_prizes jsonb,
  p_source text,
  assertion text
) returns void language plpgsql as $$
begin
  begin
    perform public.process_euromillions_official_result_v1(
      current_setting('phase2a.club')::uuid,
      p_date,
      p_draw_number,
      p_numbers,
      p_stars,
      p_prizes,
      p_source
    );
  exception when others then
    return;
  end;
  raise exception 'Expected RPC rejection: %', assertion;
end;
$$;

-- Prepare role claims, date settings, and the manual result using the
-- privileged local connection before changing the PostgreSQL role.
do $$
declare
  fn regprocedure := 'public.process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text)'::regprocedure;
  target uuid := current_setting('phase2a.club')::uuid;
  member_profile uuid := current_setting('phase2a.member_profile')::uuid;
  treasurer_profile uuid := current_setting('phase2a.treasurer_profile')::uuid;
  draw_date date;
  new_draw_date date;
  result_id uuid;
begin
  if has_function_privilege('anon', fn, 'EXECUTE') then
    raise exception 'anon must not have EXECUTE on the result RPC.';
  end if;
  if has_function_privilege('authenticated', fn, 'EXECUTE') is not true
    or has_function_privilege('service_role', fn, 'EXECUTE') is not true then
    raise exception 'authenticated and service_role must retain EXECUTE on the result RPC.';
  end if;
  if exists (
    select 1 from pg_proc p
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = fn and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'PUBLIC must not have EXECUTE on the result RPC.';
  end if;

  if not exists (
      select 1 from public.club_memberships cm
      where cm.club_id=target and cm.profile_id=member_profile
        and cm.active is true and lower(cm.access_role) not in ('treasurer','super_admin','super admin')
    ) or not public.has_club_permission(target,'viewLottery') then
    raise exception 'Fixture member must be active, have viewLottery, and lack elevated lottery role.';
  end if;
  if not exists (
      select 1 from public.club_memberships cm
      where cm.club_id=target and cm.profile_id=treasurer_profile
        and cm.active is true and lower(cm.access_role)='treasurer'
    ) then
    raise exception 'Fixture treasurer must have an active treasurer membership.';
  end if;
  if exists (
    select 1 from public.euromillions_players ep
    where ep.club_id=target and ep.status='active'
  ) then
    raise exception 'Use a disposable test club with no active Euromilhões players.';
  end if;

  -- Select a previous Tuesday and require both dates to be unused by this fixture.
  draw_date := current_date - (((extract(isodow from current_date)::integer + 5) % 7) + 7);
  new_draw_date := draw_date - 7;
  if exists (
    select 1 from public.euromillions_results r
    where r.club_id=target and r.draw_date in (draw_date,new_draw_date)
  ) then
    raise exception 'Use a disposable test club with no result on either test date.';
  end if;
  perform set_config('phase2a.update_date',draw_date::text,true);
  perform set_config('phase2a.new_date',new_draw_date::text,true);

  perform set_config('request.jwt.claim.sub',member_profile::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',member_profile,'role','authenticated')::text,true);
  perform pg_temp.expect_rejected(draw_date,'001/' || extract(year from draw_date)::integer::text,
    array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official',
    'a viewLottery member cannot submit official values directly');
  perform pg_temp.expect_rejected(draw_date,null,array[1,2,3,4,5],array[1,2],'{}'::jsonb,'manual',
    'a regular member cannot process a manual result');

  perform set_config('request.jwt.claim.sub',treasurer_profile::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',treasurer_profile,'role','authenticated')::text,true);
  result_id := public.process_euromillions_official_result_v1(
    target,draw_date,null,array[1,2,3,4,5],array[1,2],'{}'::jsonb,'manual');
  if result_id is null then raise exception 'Treasurer manual processing returned no result id.'; end if;
  perform pg_temp.expect_rejected(draw_date,'001/' || extract(year from draw_date)::integer::text,
    array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official',
    'manual RPC call cannot claim official source');
  perform pg_temp.expect_rejected(draw_date,null,array[1,2,3,4,5],array[1,2],'{"1":10}'::jsonb,'manual',
    'manual RPC call cannot provide a prize table');

  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.role','service_role',true);
  perform set_config('request.jwt.claims','{"role":"service_role"}'::text,true);
end;
$$;

-- Exercise the RPC with PostgreSQL current_user actually set to service_role.
-- This is intentionally a top-level call; SET ROLE is not allowed inside DO.
set local role service_role;
select public.process_euromillions_official_result_v1(
  current_setting('phase2a.club')::uuid,
  current_setting('phase2a.update_date')::date,
  '001/' || extract(year from current_setting('phase2a.update_date')::date)::integer::text,
  array[1,2,3,4,5],
  array[1,2],
  '{"1":10}'::jsonb,
  'official-test'
);
select public.process_euromillions_official_result_v1(
  current_setting('phase2a.club')::uuid,
  current_setting('phase2a.new_date')::date,
  '001/' || extract(year from current_setting('phase2a.new_date')::date)::integer::text,
  array[1,2,3,4,5],
  array[1,2],
  '{"1":10}'::jsonb,
  'official-test'
);
reset role;

-- Check the creator behavior and all invalid result/prize inputs.
do $$
declare
  target uuid := current_setting('phase2a.club')::uuid;
  treasurer_profile uuid := current_setting('phase2a.treasurer_profile')::uuid;
  draw_date date := current_setting('phase2a.update_date')::date;
  new_draw_date date := current_setting('phase2a.new_date')::date;
  valid_draw_number text;
  created_by_value uuid;
begin
  select r.created_by into created_by_value
  from public.euromillions_results r
  where r.club_id=target and r.draw_date=draw_date;
  if created_by_value is distinct from treasurer_profile then
    raise exception 'Official update must preserve the manual creator; expected %, got %.',
      treasurer_profile, created_by_value;
  end if;

  select r.created_by into created_by_value
  from public.euromillions_results r
  where r.club_id=target and r.draw_date=new_draw_date;
  if created_by_value is not null then
    raise exception 'A new service_role result must have NULL created_by.';
  end if;

  valid_draw_number := '001/' || extract(year from draw_date)::integer::text;
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4],array[1,2],'{}'::jsonb,'official-test','wrong number count');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,4],array[1,2],'{}'::jsonb,'official-test','duplicate numbers');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[0,2,3,4,5],array[1,2],'{}'::jsonb,'official-test','number outside 1..50');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1],'{}'::jsonb,'official-test','wrong star count');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,1],'{}'::jsonb,'official-test','duplicate stars');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,13],'{}'::jsonb,'official-test','star outside 1..12');
  perform pg_temp.expect_rejected(draw_date + 1,valid_draw_number,array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official-test','non-draw weekday');
  perform pg_temp.expect_rejected(current_date + 7,'001/' || extract(year from current_date + 7)::integer::text,
    array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official-test','future date');
  perform pg_temp.expect_rejected(draw_date,'bad-number',array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official-test','invalid draw number');
  perform pg_temp.expect_rejected(draw_date,'001/' || (extract(year from draw_date)::integer + 1)::text,
    array[1,2,3,4,5],array[1,2],'{}'::jsonb,'official-test','draw number year mismatch');

  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'[]'::jsonb,'official-test','top-level array');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'"{}"'::jsonb,'official-test','top-level string');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":true}'::jsonb,'official-test','boolean prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":null}'::jsonb,'official-test','null prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":[10]}'::jsonb,'official-test','nested array prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":{"amount":10}}'::jsonb,'official-test','nested object prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":"10.00"}'::jsonb,'official-test','numeric string prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":0}'::jsonb,'official-test','zero prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"1":-1}'::jsonb,'official-test','negative prize');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"0":10}'::jsonb,'official-test','category zero');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{"14":10}'::jsonb,'official-test','category fourteen');
  perform pg_temp.expect_rejected(draw_date,valid_draw_number,array[1,2,3,4,5],array[1,2],'{}'::jsonb,'manual','service_role cannot claim manual source');
end;
$$;

rollback;
