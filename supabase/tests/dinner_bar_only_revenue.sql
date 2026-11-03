-- LOCAL ONLY: run after bootstrap and the dinner/BAR reversal/BAR-only migrations.
begin;
do $$ begin
  if current_database()<>'bob_dinner_test' or to_regclass('public.fixture_permissions') is null then
    raise exception 'Disposable local fixture database required'; end if;
end $$;
create function pg_temp.assert_true(value boolean,message text) returns void language plpgsql as $$ begin
  if value is distinct from true then raise exception 'Assertion failed: %',message; end if;
end $$;
create function pg_temp.must_fail(statement text,message text) returns void language plpgsql as $$ declare failed boolean:=false; begin
  begin execute statement; exception when others then failed:=true; end;
  if not failed then raise exception 'Expected rejection: %',message; end if;
end $$;
do $$ declare c uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); other_actor uuid:=gen_random_uuid();
  dinner uuid:=gen_random_uuid(); meal uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); opt uuid:=gen_random_uuid();
  sale uuid; other_sale uuid; before_tx bigint; detail jsonb; historic jsonb; begin
  insert into public.clubs(id,name) values(c,'BAR-only local');
  insert into public.profiles(id,full_name) values(actor,'Cashier one'),(other_actor,'Cashier two');
  insert into public.fixture_permissions select actor,c,unnest(array['viewFinancialReports','approveExpenseRequests','viewBar','manageBar','reverseTreasuryMovement']);
  insert into public.fixture_permissions select other_actor,c,unnest(array['viewFinancialReports','approveExpenseRequests','viewBar','manageBar','reverseTreasuryMovement']);
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values(dinner,c,'2026-10-11','TESTE RC1 - fecho financeiro');
  insert into public.treasury_accounts(club_id,name) values(c,'Caixa');
  historic:=jsonb_build_object('meal_quantity',10,'meal_revenue',100,'total_revenue',100,'food_cost',40,
    'other_costs',10,'total_cost',50,'result',50,'margin_percent',50,'meal_mode','manual');
  -- Existing manual snapshot fixture: no writes through the new adjustments RPC.
  insert into public.weekly_dinner_finances(club_id,dinner_id,financial_status,meal_mode,manual_meal_quantity,manual_meal_revenue,
    food_cost_manual,other_cost_manual,snapshot,revision,closed_at,closed_by)
    values(c,dinner,'closed','manual',10,100,40,10,historic,1,now(),actor);
  insert into public.weekly_dinner_financial_snapshots(club_id,dinner_id,revision,snapshot,closed_by)
    values(c,dinner,1,historic,actor);
  perform set_config('request.jwt.claim.sub',actor::text,true);
  detail:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((detail->>'meal_revenue')::numeric=100 and (detail->>'result')::numeric=50,'old manual closed snapshot still readable');
  perform public.set_weekly_dinner_financial_closed_v1(c,dinner,false);
  detail:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=0 and (detail->>'meal_revenue')::numeric=0 and (detail->>'result')::numeric=-50,'reopen ignores manual revenue and preserves additional costs');
  perform pg_temp.assert_true((select snapshot=historic from public.weekly_dinner_financial_snapshots where dinner_id= (select id from public.weekly_dinners where club_id=c) and revision=1),'revision one historical JSON preserved');
  perform pg_temp.assert_true((select snapshot=historic from public.weekly_dinner_finances where dinner_id= (select id from public.weekly_dinners where club_id=c)),'reopen keeps original frozen snapshot');
  select count(*) into before_tx from public.treasury_transactions where club_id=c;
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''manual'',0,0,40,10)',c,dinner),'manual mode rejected');
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''automatic'',1,0,40,10)',c,dinner),'manual quantity rejected');
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''automatic'',0,100,40,10)',c,dinner),'manual revenue rejected');
  perform public.save_weekly_dinner_finance_v1(c,dinner,'automatic',0,0,40,10,'Only costs');
  perform pg_temp.assert_true((select count(*)=before_tx from public.treasury_transactions where club_id=c),'financial adjustments never create income');
  insert into public.bar_sale_presets(id,club_id,name,unit_price,counts_as_dinner_meal) values(meal,c,'Jantar',10,true);
  insert into public.products(id,club_id,name,inventory_area,cost,current_stock) values(product,c,'Beer','bar',.03,1000);
  insert into public.bar_product_sale_options(id,club_id,product_id,name,stock_quantity,public_price,member_price) values(opt,c,product,'50 ml',50,3,3);
  sale:=public.create_bar_sale_v3(c,p_weekly_dinner=>dinner);
  perform public.complete_bar_sale_v3(c,sale,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',3),
    jsonb_build_object('kind','stock','product_id',product,'sale_option_id',opt,'quantity',2)),'cash',p_weekly_dinner=>dinner);
  perform set_config('request.jwt.claim.sub',other_actor::text,true);
  other_sale:=public.create_bar_sale_v3(c,p_weekly_dinner=>dinner);
  perform public.complete_bar_sale_v3(c,other_sale,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',2)),'cash',p_weekly_dinner=>dinner);
  detail:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=5 and (detail->>'meal_revenue')::numeric=50,'two cashiers meal sales sum correctly');
  perform pg_temp.assert_true((detail->>'beverage_revenue')::numeric=6 and (detail->>'beverage_cost')::numeric=3,'beverages and historical dose cost preserved');
  perform public.reverse_bar_sale_v1(c,other_sale,'Duplicated meal sale');
  detail:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=3 and (detail->>'meal_revenue')::numeric=30,'reversed sale excluded');
  perform public.set_weekly_dinner_financial_closed_v1(c,dinner,true);
  perform pg_temp.assert_true((select snapshot=historic from public.weekly_dinner_financial_snapshots where dinner_id= (select id from public.weekly_dinners where club_id=c) and revision=1),'reclosing never rewrites manual revision one');
  perform pg_temp.assert_true((select count(*)=2 from public.weekly_dinner_financial_snapshots s
    where s.dinner_id=dinner),'reclosing keeps exactly two snapshots for this dinner');
  perform pg_temp.assert_true(exists(select 1 from public.weekly_dinner_financial_snapshots s
    where s.dinner_id=dinner and s.revision=2),'reclosing creates revision two');
  perform pg_temp.assert_true((select (s.snapshot->>'meal_quantity')::numeric=3
    and (s.snapshot->>'meal_revenue')::numeric=30
    and (s.snapshot->>'beverage_revenue')::numeric=6
    and (s.snapshot->>'beverage_cost')::numeric=3
    and (s.snapshot->>'total_revenue')::numeric=36
    and (s.snapshot->>'total_cost')::numeric=53
    and (s.snapshot->>'result')::numeric=-17
    from public.weekly_dinner_financial_snapshots s where s.dinner_id=dinner and s.revision=2),
    'revision two freezes the BAR-only totals after the reversed sale');
  perform pg_temp.assert_true((select f.financial_status='closed' and f.revision=2
    from public.weekly_dinner_finances f where f.dinner_id=dinner),'current finances are closed at revision two');
  detail:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true(detail->>'financial_status'='closed' and (detail->>'revision')::integer=2
    and (detail->>'meal_quantity')::numeric=3 and (detail->>'meal_revenue')::numeric=30
    and (detail->>'beverage_revenue')::numeric=6 and (detail->>'beverage_cost')::numeric=3
    and (detail->>'total_revenue')::numeric=36 and (detail->>'total_cost')::numeric=53
    and (detail->>'result')::numeric=-17,
    'current RPC returns closed revision two BAR-only values, not historic manual revenue');
end $$;
rollback;
select 'dinner_bar_only_revenue: all local assertions passed' as result;
