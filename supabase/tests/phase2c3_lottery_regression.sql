-- NEVER run on production. Synthetic fixtures are created by the fixed-loopback harness.
-- Defense in depth: fresh local test database and loopback server are mandatory.
begin;
do $$ begin
  if current_database() not like 'bob_phase2c3_%'
     or inet_server_addr() is distinct from inet '127.0.0.1' then
    raise exception 'This regression test is restricted to the local Phase 2C.3 harness.';
  end if;
end $$;

-- Assert effective ACLs, including inherited PUBLIC grants, for exact signatures.
do $$ declare s text; r text; begin
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    where (n.nspname='bob_lottery_private' or p.proname in
      ('prepare_euromillions_month_v1','register_euromillions_month_payment_v1','generate_euromillions_charges_v1','sync_euromillions_players_v1'))
    and a.grantee=0 and a.privilege_type='EXECUTE') then raise exception 'PUBLIC execute grant'; end if;
  foreach s in array array[
    'public.generate_euromillions_charges_v1(uuid,integer,integer)',
    'public.sync_euromillions_players_v1(uuid)',
    'bob_lottery_private.prepare_month(uuid,integer,integer)'] loop
    foreach r in array array['anon','authenticated','service_role'] loop
      if has_function_privilege(r,s,'EXECUTE') then raise exception 'Unexpected helper grant: % %',r,s; end if;
    end loop;
  end loop;
  foreach s in array array[
    'public.prepare_euromillions_month_v1(uuid,integer,integer)',
    'public.register_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)'] loop
    if not has_function_privilege('authenticated',s,'EXECUTE') then raise exception 'Missing grant: %',s; end if;
    foreach r in array array['anon','service_role'] loop
      if has_function_privilege(r,s,'EXECUTE') then raise exception 'Unexpected entry grant: % %',r,s; end if;
    end loop;
  end loop;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='bob_lottery_private' or p.proname in
      ('prepare_euromillions_month_v1','register_euromillions_month_payment_v1','generate_euromillions_charges_v1','sync_euromillions_players_v1'))
    and not ('search_path=pg_catalog, public, pg_temp'=any(p.proconfig))) then
    raise exception 'Unhardened search_path';
  end if;
end $$;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
set local role authenticated;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',2027,1);
  raise exception 'Viewer prepared month';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform public.register_euromillions_month_payment_v1('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',2020,1,null);
  raise exception 'Viewer paid month';
exception when insufficient_privilege then null; end $$;
do $$ begin
  insert into public.euromillions_players(club_id,member_id) values ('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002');
  raise exception 'Viewer configured player';
exception when insufficient_privilege then null; end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',2027,1);
  raise exception 'Missing JWT accepted';
exception when insufficient_privilege then null; end $$;
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
set local role authenticated;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',2027,1);
  raise exception 'Cross-club preparation accepted';
exception when insufficient_privilege then null; end $$;
reset role;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',2020,1);
  raise exception 'Past month accepted';
exception when invalid_parameter_value then
  if sqlerrm not like 'Meses passados%' then raise; end if;
end $$;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',null,1);
  raise exception 'Null year accepted';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',2027,13);
  raise exception 'Invalid month accepted';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform public.register_euromillions_month_payment_v1('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',2020,2,null);
  raise exception 'Missing history accepted';
exception when invalid_parameter_value then
  if sqlerrm not like 'Não existem cobranças históricas%' then raise; end if;
end $$;
-- Pay precisely the existing historical charge, without manufacturing other draws.
select public.register_euromillions_month_payment_v1('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',2020,1,'Dinheiro');
do $$ begin
  if (select count(*) from public.euromillions_draw_charges where draw_date<'2021-01-01')<>1
    or not exists(select 1 from public.euromillions_draw_charges where draw_date='2020-01-07' and amount=7.77 and paid_amount=7.77) then
    raise exception 'Historical payment reconstructed or changed charges';
  end if;
end $$;
-- No active-player sync: preparing does not create the missing member's row.
do $$ declare d date:=date_trunc('month',now() at time zone 'Europe/Lisbon')::date; n integer; begin
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',extract(year from d)::int,extract(month from d)::int);
  select count(*) into n from public.euromillions_draw_charges where draw_date>=d and draw_date<d+interval '1 month';
  if n<>(select count(*) from generate_series(d,d+interval '1 month'-interval '1 day',interval '1 day') x where extract(isodow from x) in (2,5)) then raise exception 'Incorrect draw count'; end if;
  perform public.prepare_euromillions_month_v1('00000000-0000-0000-0000-000000000001',extract(year from d)::int,extract(month from d)::int);
  if n<>(select count(*) from public.euromillions_draw_charges where draw_date>=d and draw_date<d+interval '1 month') then raise exception 'Preparation not idempotent'; end if;
  if exists(select 1 from public.euromillions_draw_charges where draw_date>=d and draw_date<d+interval '1 month' and amount<>2.20) then raise exception 'Incorrect prepared amount'; end if;
  if (select count(*) from public.euromillions_players)<>1 then raise exception 'Global sync occurred'; end if;
  perform public.register_euromillions_month_payment_v1('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',extract(year from d)::int,extract(month from d)::int,'Dinheiro');
  if exists(select 1 from public.euromillions_draw_charges where draw_date>=d and draw_date<d+interval '1 month' and paid_amount<>amount) then raise exception 'Current payment failed'; end if;
  d:=d+interval '2 months';
  perform public.register_euromillions_month_payment_v1('00000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001',extract(year from d)::int,extract(month from d)::int,'Dinheiro');
  if not exists(select 1 from public.euromillions_draw_charges where draw_date>=d and draw_date<d+interval '1 month' and paid_amount=amount) then raise exception 'Future explicit payment did not prepare'; end if;
end $$;
-- Selective configuration under real RLS, retaining UUID on conflict.
insert into public.euromillions_players(club_id,member_id,status,numbers,stars)
values ('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','active',array[6,7,8,9,10],array[3,4])
on conflict(club_id,member_id) do update set status=excluded.status,numbers=excluded.numbers,stars=excluded.stars;
do $$ begin
  if (select count(*) from public.euromillions_players)<>2 then raise exception 'Selective configuration failed'; end if;
  insert into public.euromillions_players(club_id,member_id) values ('00000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003');
  raise exception 'Cross-club member accepted';
exception when insufficient_privilege then null; end $$;
do $$ begin
  perform public.process_euromillions_official_result_v1('00000000-0000-0000-0000-000000000001','2020-01-07',null,array[1,2,3,4,5],array[1,2],'{}','manual');
  raise exception 'Past manual processing accepted';
exception when invalid_parameter_value then null; end $$;
do $$ begin
  perform public.process_euromillions_result_v1('00000000-0000-0000-0000-000000000001','2020-01-07',array[1,2,3,4,5],array[1,2]);
  raise exception 'Past legacy processing accepted';
exception when invalid_parameter_value then null; end $$;
reset role;
select set_config('request.jwt.claim.role','service_role',true);
select set_config('request.jwt.claim.sub','',true);
set local role service_role;
do $$ begin
  perform public.process_euromillions_official_result_v1('00000000-0000-0000-0000-000000000001','2020-01-07','002/2020',array[1,2,3,4,5],array[1,2],'{}','official');
  raise exception 'Past official processing accepted';
exception when invalid_parameter_value then null; end $$;
reset role;
rollback;
