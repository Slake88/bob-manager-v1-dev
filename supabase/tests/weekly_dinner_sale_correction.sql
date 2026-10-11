-- LOCAL ONLY: run after the weekly dinner bootstrap and migrations, including
-- 20261011150000_rc1_weekly_dinner_sale_correction.sql. Requires bob_dinner_test.
begin;
do $$ begin
  if current_database()<>'bob_dinner_test' or to_regclass('public.fixture_permissions') is null then
    raise exception 'Disposable local fixture database required'; end if;
end $$;
create function pg_temp.assert_true(value boolean,message text) returns void
language plpgsql as $$ begin if value is distinct from true then raise exception 'Assertion failed: %',message; end if; end $$;
create function pg_temp.must_fail(statement text,message text) returns void
language plpgsql as $$ declare failed boolean:=false; begin
  begin execute statement; exception when others then failed:=true; end;
  if not failed then raise exception 'Expected rejection: %',message; end if;
end $$;
do $$ declare c uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); d1 uuid:=gen_random_uuid(); d2 uuid:=gen_random_uuid();
  meal uuid:=gen_random_uuid(); sale1 uuid; no_dinner uuid; sale2 uuid; result jsonb; choices jsonb;
begin
  insert into public.clubs(id,name) values(c,'Dinner sale correction local');
  insert into public.profiles(id,full_name) values(actor,'Finance admin');
  insert into public.fixture_permissions select actor,c,unnest(array['viewFinancialReports','approveExpenseRequests','viewBar','manageBar']);
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values
    (d1,c,current_date,'Dinner one'),(d2,c,current_date+1,'Dinner two');
  insert into public.treasury_accounts(club_id,name) values(c,'Caixa');
  insert into public.bar_sale_presets(id,club_id,name,unit_price,counts_as_dinner_meal)
    values(meal,c,'Dinner meal',10,true);
  perform set_config('request.jwt.claim.sub',actor::text,true);

  sale1:=public.create_bar_sale_v3(c,p_weekly_dinner=>d1);
  perform public.complete_bar_sale_v3(c,sale1,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',1)),'cash',p_weekly_dinner=>d1);
  no_dinner:=public.create_bar_sale_v3(c);
  perform public.complete_bar_sale_v3(c,no_dinner,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',2)),'cash');
  sale2:=public.create_bar_sale_v3(c,p_weekly_dinner=>d2);
  perform public.complete_bar_sale_v3(c,sale2,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',3)),'cash',p_weekly_dinner=>d2);

  result:=public.weekly_dinner_finance_v1(c,d1);
  perform pg_temp.assert_true((result->>'meal_quantity')::numeric=1 and (result->>'meal_revenue')::numeric=10,
    'only sale created with this dinner contributes');
  perform pg_temp.assert_true((public.weekly_dinner_finance_v1(c,d2)->>'meal_revenue')::numeric=30,
    'sale from another dinner stays in that dinner');
  choices:=public.weekly_dinner_finance_choices_v1(c,d1);
  perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(choices->'sales') s where s->>'id'=no_dinner::text),
    'correction tool can find a completed sale without dinner');
  perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(choices->'sales') s where s->>'id'=sale2::text),
    'correction tool can find a sale associated with another dinner');
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''manual'',10,100,0,0)',c,d1),
    'manual dinner revenue rejected');

  perform public.assign_bar_sale_dinner_v1(c,no_dinner,d1);
  perform pg_temp.assert_true((public.weekly_dinner_finance_v1(c,d1)->>'meal_revenue')::numeric=30,
    'authorized administrative correction updates live BAR totals');
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='bar_sales'
    and entity_id::text=no_dinner::text and actor_id=actor),'association correction is audited');

  perform public.set_weekly_dinner_financial_closed_v1(c,d1,true);
  perform pg_temp.must_fail(format('select public.assign_bar_sale_dinner_v1(%L,%L,%L)',c,sale2,d1),
    'cannot change association into a closed dinner');
  perform public.set_weekly_dinner_financial_closed_v1(c,d1,false);
  perform public.set_weekly_dinner_financial_closed_v1(c,d2,true);
  perform pg_temp.must_fail(format('select public.assign_bar_sale_dinner_v1(%L,%L,%L)',c,sale2,d1),
    'cannot change association away from a closed dinner');
end $$;
rollback;
select 'weekly_dinner_sale_correction: all local assertions passed' as result;
