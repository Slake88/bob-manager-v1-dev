-- LOCAL ONLY. Run against a disposable bob_dinner_test PostgreSQL database:
-- 1. fixtures/weekly_dinner_finance_bootstrap.sql
-- 2. migrations/20261010210110_rc1_weekly_dinner_finance.sql
-- 3. migrations/20261010215624_rc1_bar_dinner_choices_proximity.sql
-- 4. this script (psql -v ON_ERROR_STOP=1 -f ...).
-- The bootstrap imports committed V2/audit code; unrelated integrations are
-- fixture dependencies. This does not replace a full local Supabase reset.
-- Every application fixture is rolled back. Never run on production.
begin;
do $$ begin
  if current_database()<>'bob_dinner_test' or not exists(
    select 1 from pg_tables where schemaname='public' and tablename='fixture_permissions') then
    raise exception 'Disposable local fixture database required';
  end if;
end $$;
create function pg_temp.assert_true(value boolean,message text) returns void
language plpgsql as $$ begin if value is distinct from true then raise exception 'Assertion failed: %',message; end if; end $$;
create function pg_temp.must_fail(statement text,message text) returns void
language plpgsql as $$ declare failed boolean:=false; begin
  begin execute statement; exception when others then failed:=true; end;
  if not failed then raise exception 'Expected rejection: %',message; end if;
end $$;

do $$ declare c uuid:=gen_random_uuid(); foreign_c uuid:=gen_random_uuid(); manager uuid:=gen_random_uuid();
  member uuid:=gen_random_uuid(); reader uuid:=gen_random_uuid(); d uuid:=gen_random_uuid(); foreign_d uuid:=gen_random_uuid();
  p uuid:=gen_random_uuid(); dose uuid:=gen_random_uuid(); preset uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); a uuid:=gen_random_uuid();
  food uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); stock_expense uuid:=gen_random_uuid(); foreign_tx uuid:=gen_random_uuid();
  old_sale uuid:=gen_random_uuid(); old_dinner uuid:=gen_random_uuid();
begin
  insert into public.clubs(id,name) values(c,'Local fixture'),(foreign_c,'Foreign fixture');
  insert into public.profiles(id,full_name) values(manager,'Manager fixture'),(member,'Member fixture'),(reader,'Read-only fixture');
  insert into public.fixture_permissions select manager,c,unnest(array['viewFinancialReports','approveExpenseRequests','manageBar','viewBar','selectBarFinancialAccount']);
  insert into public.fixture_permissions values(member,c,'viewBar'),(reader,c,'viewFinancialReports');
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values(d,c,'2026-10-15','Local dinner'),(foreign_d,foreign_c,'2026-10-15','Foreign dinner'),(old_dinner,c,'2025-10-16','Historical dinner');
  insert into public.products(id,club_id,name,inventory_area,cost,current_stock,consumption_unit)
    values(p,c,'Dose fixture','bar',.03,1000,'ml');
  insert into public.bar_product_sale_options(id,club_id,product_id,name,stock_quantity,public_price,member_price)
    values(dose,c,p,'50 ml',50,4,3);
  insert into public.bar_sale_presets(id,club_id,name,unit_price,counts_as_dinner_meal) values(preset,c,'Meal fixture',10,true);
  insert into public.events(id,club_id,name) values(ev,c,'Independent event');
  insert into public.treasury_accounts(id,club_id,name) values(a,c,'Caixa');
  insert into public.treasury_transactions(id,club_id,kind,account_id,amount,description,source_type)
    values(food,c,'expense',a,10,'Food',null),(other,c,'expense',a,2,'Other',null),(stock_expense,c,'expense',a,100,'Inventory purchase','bar'),(foreign_tx,foreign_c,'expense',null,5,'Foreign',null);
  -- Simulate a pre-migration sale without inventing historical costs.
  insert into public.bar_sales(id,club_id,status) values(old_sale,c,'draft');
  alter table public.bar_sale_items disable trigger trg_dinner_line_snapshot;
  insert into public.bar_sale_items(club_id,sale_id,item_kind,description,quantity,unit_price,line_total) values(c,old_sale,'stock','Legacy no snapshot',1,4,4);
  alter table public.bar_sale_items enable trigger trg_dinner_line_snapshot;
  update public.bar_sales set status='completed' where id=old_sale;
  perform set_config('dinner_test.club',c::text,true); perform set_config('dinner_test.foreign_club',foreign_c::text,true);
  perform set_config('dinner_test.manager',manager::text,true); perform set_config('dinner_test.member',member::text,true); perform set_config('dinner_test.reader',reader::text,true);
  perform set_config('dinner_test.dinner',d::text,true); perform set_config('dinner_test.foreign_dinner',foreign_d::text,true);
  perform set_config('dinner_test.product',p::text,true); perform set_config('dinner_test.option',dose::text,true); perform set_config('dinner_test.preset',preset::text,true);
  perform set_config('dinner_test.event',ev::text,true); perform set_config('dinner_test.account',a::text,true);
  perform set_config('dinner_test.food',food::text,true); perform set_config('dinner_test.other',other::text,true); perform set_config('dinner_test.stock_expense',stock_expense::text,true); perform set_config('dinner_test.foreign_tx',foreign_tx::text,true);
  perform set_config('dinner_test.old_sale',old_sale::text,true); perform set_config('dinner_test.old_dinner',old_dinner::text,true);
  perform set_config('request.jwt.claim.sub',manager::text,true);
end $$;
set local role authenticated;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.dinner')::uuid;
  foreign_d uuid:=current_setting('dinner_test.foreign_dinner')::uuid; ev uuid:=current_setting('dinner_test.event')::uuid;
  p uuid:=current_setting('dinner_test.product')::uuid; o uuid:=current_setting('dinner_test.option')::uuid;
  preset uuid:=current_setting('dinner_test.preset')::uuid; sale uuid; draft uuid; plain uuid; legacy_client uuid; output jsonb; detail jsonb; lines jsonb;
begin
  perform pg_temp.must_fail(format('select public.create_bar_sale_v3(%L,p_weekly_dinner=>%L)',c,foreign_d),'cross-club dinner');
  perform pg_temp.must_fail(format('select public.weekly_dinner_finance_v1(%L,%L)',c,foreign_d),'cross-club finance detail');
  perform pg_temp.assert_true(not has_function_privilege('anon','public.weekly_dinner_finance_v1(uuid,uuid)','execute'),'anon cannot execute finance');
  perform pg_temp.assert_true(not has_schema_privilege('authenticated','bob_dinner_private','usage'),'private helper schema is inaccessible');
  perform pg_temp.must_fail('select unit_cost_snapshot from public.bar_sale_items','direct financial cost SELECT denied');
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''manual'',1,''NaN''::numeric,0,0)',c,d),'NaN must not enter financial snapshots');
  -- Draft blocks financial close, but operational status is independently kept.
  sale:=public.create_bar_sale_v3(c,p_event=>ev,p_weekly_dinner=>d);
  perform pg_temp.must_fail(format('select public.set_weekly_dinner_financial_closed_v1(%L,%L,true)',c,d),'draft prevents premature close');
  lines:=jsonb_build_array(jsonb_build_object('kind','stock','product_id',p,'sale_option_id',o,'quantity',2),jsonb_build_object('kind','preset','preset_id',preset,'quantity',2));
  output:=public.complete_bar_sale_v3(c,sale,lines,'cash',p_customer_type=>'member',p_customer_label=>'Group fixture',p_weekly_dinner=>d);
  perform pg_temp.assert_true((output->>'total')::numeric=26,'member prices preserved');
  perform pg_temp.assert_true(output->>'weekly_dinner_id'=d::text,'dinner associated');
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=2 and (detail->>'meal_revenue')::numeric=20,'meal preset classification');
  perform pg_temp.assert_true((detail->>'beverage_cost')::numeric=3,'dose cost = 2*50*.03');
  perform public.link_weekly_dinner_expense_v1(c,d,current_setting('dinner_test.food')::uuid,'food');
  perform public.link_weekly_dinner_expense_v1(c,d,current_setting('dinner_test.other')::uuid,'other');
  perform pg_temp.must_fail(format('select public.link_weekly_dinner_expense_v1(%L,%L,%L,''other'')',c,d,current_setting('dinner_test.food')),'duplicate expense');
  perform pg_temp.must_fail(format('select public.link_weekly_dinner_expense_v1(%L,%L,%L,''food'')',c,d,current_setting('dinner_test.foreign_tx')),'cross-club expense');
  perform pg_temp.must_fail(format('select public.link_weekly_dinner_expense_v1(%L,%L,%L,''other'')',c,d,current_setting('dinner_test.stock_expense')),'stock purchase would double count');
  perform public.save_weekly_dinner_finance_v1(c,d,'automatic',0,0,1,2,'Explicit additional adjustments');
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'total_revenue')::numeric=26 and (detail->>'total_cost')::numeric=18 and (detail->>'result')::numeric=8,'automatic direct result');
  perform public.save_weekly_dinner_finance_v1(c,d,'manual',3,40,1,2,null);
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=3 and (detail->>'total_revenue')::numeric=46,'manual overrides rather than adds');
  perform public.save_weekly_dinner_finance_v1(c,d,'automatic',0,0,1,2,null);
  detail:=public.set_weekly_dinner_financial_closed_v1(c,d,true);
  perform pg_temp.assert_true(detail->>'financial_status'='closed' and (detail->>'result')::numeric=8,'close snapshot result');
  perform pg_temp.must_fail(format('select public.save_weekly_dinner_finance_v1(%L,%L,''automatic'',0,0,0,0)',c,d),'closed adjustments rejected');
  perform pg_temp.must_fail(format('select public.create_bar_sale_v3(%L,p_weekly_dinner=>%L)',c,d),'closed dinner new sale rejected');
  perform pg_temp.must_fail(format('insert into public.weekly_dinner_finances(club_id,dinner_id) values(%L,%L)',c,foreign_d),'direct financial DML denied');
  -- BAR without a dinner and older V2 clients retain their behavior.
  plain:=public.create_bar_sale_v3(c,p_event=>ev);
  perform public.complete_bar_sale_v3(c,plain,jsonb_build_array(jsonb_build_object('kind','other','description','Other','unit_price',1,'quantity',1)),'cash');
  legacy_client:=public.create_bar_sale_v2(c,p_event=>ev);
  perform public.complete_bar_sale_v2(c,legacy_client,jsonb_build_array(jsonb_build_object('kind','stock','product_id',p,'sale_option_id',o,'quantity',1)),'cash');
  perform set_config('dinner_test.sale',sale::text,true); perform set_config('dinner_test.plain_sale',plain::text,true); perform set_config('dinner_test.legacy_client_sale',legacy_client::text,true);
end $$;
reset role;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.dinner')::uuid; sale uuid:=current_setting('dinner_test.sale')::uuid; ev uuid:=current_setting('dinner_test.event')::uuid; line public.bar_sale_items%rowtype;
begin
  select * into line from public.bar_sale_items where sale_id=sale and item_kind='stock';
  perform pg_temp.assert_true(line.unit_cost_snapshot=.03 and line.cost_total_snapshot=3,'stored immutable costs');
  perform pg_temp.assert_true((select current_stock=850 from public.products where id=current_setting('dinner_test.product')::uuid),'stock movement and legacy V2 consumption');
  perform pg_temp.assert_true((select event_id=ev and weekly_dinner_id=d from public.bar_sales where id=sale),'event independent of dinner');
  perform pg_temp.assert_true((select event_id=ev and weekly_dinner_id is null from public.bar_sales where id=current_setting('dinner_test.plain_sale')::uuid),'sale without dinner retains event');
  perform pg_temp.assert_true(exists(select 1 from public.stock_movements where event_id=ev and quantity=-100 and unit_cost=.03),'stock movements preserved');
  perform pg_temp.assert_true(exists(select 1 from public.bar_operations where sale_id=sale and consumption_quantity=100),'BAR operation preserved');
  perform pg_temp.assert_true(exists(select 1 from public.fixture_domain_events where entity_id=sale and name='BarSaleCompleted'),'domain event preserved');
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='weekly_dinner_finances' and entity_id is not null and actor_id=auth.uid()),'existing audit with identifiable record');
  perform pg_temp.must_fail(format('update public.bar_sale_items set sale_id=%L where id=%L',current_setting('dinner_test.plain_sale'),line.id),'moving a completed line cannot bypass immutability');
  update public.products set cost=100,current_stock=10000 where id=current_setting('dinner_test.product')::uuid;
  update public.bar_sale_presets set unit_price=1000,counts_as_dinner_meal=false where id=current_setting('dinner_test.preset')::uuid;
  insert into public.treasury_transactions(club_id,kind,amount,description,reversal_of) values(c,'income',10,'Reversal',current_setting('dinner_test.food')::uuid);
end $$;
do $$ begin
  insert into public.weekly_dinners(club_id,dinner_date,dish) values(current_setting('dinner_test.club')::uuid,'2026-10-22','Second weighted fixture');
  insert into public.weekly_dinners(club_id,dinner_date,dish) values(current_setting('dinner_test.club')::uuid,'2024-10-17','Zero revenue fixture');
  perform set_config('dinner_test.second',(select id::text from public.weekly_dinners where club_id=current_setting('dinner_test.club')::uuid and dinner_date='2026-10-22'),true);
  perform set_config('dinner_test.zero',(select id::text from public.weekly_dinners where club_id=current_setting('dinner_test.club')::uuid and dinner_date='2024-10-17'),true);
end $$;
set local role authenticated;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.dinner')::uuid; detail jsonb; history jsonb; old_d uuid:=current_setting('dinner_test.old_dinner')::uuid;
begin
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'result')::numeric=8 and (detail->>'food_cost')::numeric=11,'closed unaffected by future product/preset/reversal');
  detail:=public.set_weekly_dinner_financial_closed_v1(c,d,false);
  perform pg_temp.assert_true((detail->>'food_cost')::numeric=1 and (detail->>'beverage_cost')::numeric=3 and (detail->>'meal_revenue')::numeric=20,'reopen uses live reversal and original line snapshots');
  perform public.set_weekly_dinner_financial_closed_v1(c,d,true);
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'revision')::integer=2 and jsonb_array_length(detail->'previous_snapshots')=2,'archive preserves previous revisions');
  -- A positive 'other' line stays excluded and visibly blocks the final close.
  perform public.assign_bar_sale_dinner_v1(c,current_setting('dinner_test.plain_sale')::uuid,old_d);
  detail:=public.weekly_dinner_finance_v1(c,old_d);
  perform pg_temp.assert_true((detail->>'excluded_revenue')::numeric=1
    and (detail->>'excluded_line_count')::integer=1,'unclassified revenue and line count visible');
  perform pg_temp.assert_true((detail->>'total_revenue')::numeric=0,'excluded revenue never silently enters meals/BAR totals');
  begin
    perform public.set_weekly_dinner_financial_closed_v1(c,old_d,true);
    raise exception 'Expected excluded revenue to prevent closing';
  exception when others then
    if SQLERRM<>'Existem vendas do BAR por classificar neste jantar. Classifica ou corrige essas vendas antes de fechar financeiramente.' then raise; end if;
  end;
  perform pg_temp.assert_true(not exists(select 1 from public.weekly_dinner_financial_snapshots where dinner_id=old_d),'rejected close records no snapshot');
  -- Correct only the explicitly wrong association. Preserve the sale itself.
  perform public.assign_bar_sale_dinner_v1(c,current_setting('dinner_test.plain_sale')::uuid,null);
  detail:=public.set_weekly_dinner_financial_closed_v1(c,old_d,true);
  perform pg_temp.assert_true(detail->>'financial_status'='closed'
    and (detail->>'excluded_revenue')::numeric=0,'corrected association allows closing');
  perform public.set_weekly_dinner_financial_closed_v1(c,old_d,false);
  perform public.assign_bar_sale_dinner_v1(c,current_setting('dinner_test.old_sale')::uuid,old_d);
  detail:=public.weekly_dinner_finance_v1(c,old_d);
  perform pg_temp.assert_true((detail->>'missing_cost_count')::integer=1 and detail->>'result' is null,'historical unknown cost never backfilled');
  perform pg_temp.must_fail(format('select public.set_weekly_dinner_financial_closed_v1(%L,%L,true)',c,old_d),'missing cost prevents false historic close');
  perform public.assign_bar_sale_dinner_v1(c,current_setting('dinner_test.old_sale')::uuid,null);
  perform public.save_weekly_dinner_finance_v1(c,old_d,'manual',2,100,30,0,null);
  perform public.set_weekly_dinner_financial_closed_v1(c,old_d,true);
  history:=public.weekly_dinner_financial_history_v1(c,2025);
  perform pg_temp.assert_true((history->>'closed_count')::integer=1 and (history->>'result')::numeric=70,'previous-year manual history');
  history:=public.weekly_dinner_financial_history_v1(c,2026);
  perform pg_temp.assert_true((history->>'closed_count')::integer=1 and (history->>'result')::numeric=18,'annual sum uses final snapshot');
  perform pg_temp.assert_true(abs((history->>'margin_percent')::numeric-18.0/26*100)<.000001,'global weighted margin');
  perform public.save_weekly_dinner_finance_v1(c,current_setting('dinner_test.second')::uuid,'manual',10,100,50,0,null);
  perform public.set_weekly_dinner_financial_closed_v1(c,current_setting('dinner_test.second')::uuid,true);
  history:=public.weekly_dinner_financial_history_v1(c,2026);
  perform pg_temp.assert_true((history->>'closed_count')::integer=2 and (history->>'total_revenue')::numeric=126 and (history->>'result')::numeric=68,'multiple closed dinner totals');
  perform pg_temp.assert_true(abs((history->>'margin_percent')::numeric-68.0/126*100)<.000001,'weighted ratio, not mean of dinner percentages');
  detail:=public.set_weekly_dinner_financial_closed_v1(c,current_setting('dinner_test.zero')::uuid,true);
  perform pg_temp.assert_true((detail->>'margin_percent')::numeric=0,'zero revenue margin');
  perform pg_temp.must_fail(format('select public.assign_bar_sale_dinner_v1(%L,%L,null)',c,current_setting('dinner_test.sale')),'cannot detach sale from a closed dinner');

end $$;
reset role;
-- Dedicated mixed-sale fixture avoids altering any previous annual totals.
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); o uuid:=gen_random_uuid(); preset uuid:=gen_random_uuid(); begin
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values(d,c,'2023-10-19','Mixed sale fixture');
  insert into public.products(id,club_id,name,inventory_area,cost,current_stock,consumption_unit) values(p,c,'Mixed beer fixture','bar',.6,100,'unid.');
  insert into public.bar_product_sale_options(id,club_id,product_id,name,stock_quantity,public_price,member_price) values(o,c,p,'Beer',1,2,1.5);
  insert into public.bar_sale_presets(id,club_id,name,unit_price,counts_as_dinner_meal) values(preset,c,'Mixed meal fixture',10,true);
  perform set_config('dinner_test.mixed_dinner',d::text,true); perform set_config('dinner_test.mixed_product',p::text,true);
  perform set_config('dinner_test.mixed_option',o::text,true); perform set_config('dinner_test.mixed_preset',preset::text,true);
end $$;
set local role authenticated;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.mixed_dinner')::uuid;
  sale uuid; item uuid; detail jsonb; original jsonb; begin
  sale:=public.create_bar_sale_v3(c,p_weekly_dinner=>d);
  perform public.complete_bar_sale_v3(c,sale,jsonb_build_array(
    jsonb_build_object('kind','stock','product_id',current_setting('dinner_test.mixed_product'),'sale_option_id',current_setting('dinner_test.mixed_option'),'quantity',10),
    jsonb_build_object('kind','preset','preset_id',current_setting('dinner_test.mixed_preset'),'quantity',2),
    jsonb_build_object('kind','other','description','Sobremesa','quantity',2,'unit_price',2.5)
  ),'cash',p_weekly_dinner=>d);
  select id into item from public.bar_sale_items where sale_id=sale and item_kind='other';
  -- Read only operational fields, never cost snapshots directly as authenticated.
  select jsonb_build_object('component',dinner_component_snapshot,'line_total',line_total,'quantity',quantity) into original from public.bar_sale_items where id=item;
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'excluded_revenue')::numeric=5 and (detail->>'excluded_line_count')::int=1,'mixed sale has visible unclassified line');
  perform pg_temp.assert_true(detail->'classification_lines'->0->>'description'='Sobremesa','RPC identifies individual unclassified line');
  perform pg_temp.must_fail(format('select public.set_weekly_dinner_financial_closed_v1(%L,%L,true)',c,d),'mixed excluded sale cannot close');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,''bar'')',c,d,item),'BAR override requires reliable historical cost');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,''meal'')',c,current_setting('dinner_test.foreign_dinner'),item),'cross-club dinner classification denied');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,''meal'')',current_setting('dinner_test.foreign_club'),d,item),'cross-club permission denied');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,''meal'')',c,d,(select id from public.bar_sale_items where sale_id=current_setting('dinner_test.sale')::uuid order by id limit 1)),'item must belong to the dinner sale');
  perform pg_temp.must_fail(format('insert into public.weekly_dinner_sale_item_classifications(club_id,dinner_id,sale_item_id,component_override) values(%L,%L,%L,''meal'')',c,d,item),'direct override DML denied');
  perform public.classify_weekly_dinner_sale_item_v1(c,d,item,'meal');
  perform public.classify_weekly_dinner_sale_item_v1(c,d,item,'meal');
  perform pg_temp.assert_true((select count(*)=1 from public.weekly_dinner_sale_item_classifications where dinner_id=d and sale_item_id=item),'override remains unique on upsert');
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'excluded_revenue')::numeric=0 and (detail->>'excluded_line_count')::int=0,'one line correction clears exclusion');
  perform pg_temp.assert_true((detail->>'meal_quantity')::numeric=4 and (detail->>'meal_revenue')::numeric=25,'existing meal plus corrected dessert');
  perform pg_temp.assert_true((detail->>'beverage_revenue')::numeric=20 and (detail->>'beverage_cost')::numeric=6,'existing BAR intact');
  perform pg_temp.assert_true((detail->>'total_revenue')::numeric=45 and (detail->>'result')::numeric=39,'effective components preserve approved formula');
  perform pg_temp.assert_true((select jsonb_build_object('component',dinner_component_snapshot,'line_total',line_total,'quantity',quantity)=original from public.bar_sale_items where id=item),'original completed line unchanged');
  perform public.classify_weekly_dinner_sale_item_v1(c,d,item,null);
  detail:=public.weekly_dinner_finance_v1(c,d);
  perform pg_temp.assert_true((detail->>'excluded_revenue')::numeric=5 and (detail->>'meal_revenue')::numeric=20,'undo restores original component');
  perform pg_temp.must_fail(format('select public.set_weekly_dinner_financial_closed_v1(%L,%L,true)',c,d),'undo restores closing block');
  perform public.classify_weekly_dinner_sale_item_v1(c,d,item,'meal');
  detail:=public.set_weekly_dinner_financial_closed_v1(c,d,true);
  perform pg_temp.assert_true(detail->>'financial_status'='closed' and (detail->>'result')::numeric=39,'mixed sale closes after line correction');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,null)',c,d,item),'closed dinner rejects undo');
  perform pg_temp.must_fail(format('select public.classify_weekly_dinner_sale_item_v1(%L,%L,%L,''meal'')',c,d,item),'closed dinner rejects classification changes');
  perform pg_temp.assert_true((public.weekly_dinner_finance_v1(c,d)->>'result')::numeric=39,'closed snapshot remains unchanged');
  perform set_config('dinner_test.mixed_item',item::text,true);
end $$;
reset role;
do $$ begin
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='weekly_dinner_sale_item_classifications' and action='created' and after_data->>'sale_item_id'=current_setting('dinner_test.mixed_item') and actor_id=auth.uid()),'override creation audited');
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='weekly_dinner_sale_item_classifications' and action='updated' and after_data->>'sale_item_id'=current_setting('dinner_test.mixed_item')),'override update audited');
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='weekly_dinner_sale_item_classifications' and action='deleted' and before_data->>'sale_item_id'=current_setting('dinner_test.mixed_item')),'override removal audited');
end $$;
select set_config('request.jwt.claim.sub',current_setting('dinner_test.reader'),true);
set local role authenticated;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.dinner')::uuid; begin
  perform pg_temp.assert_true(public.weekly_dinner_finance_v1(c,d)->>'financial_status'='closed','read-only financial access');
  perform pg_temp.must_fail(format('select public.set_weekly_dinner_financial_closed_v1(%L,%L,false)',c,d),'read permission does not authorize writing');
  begin
    perform public.classify_weekly_dinner_sale_item_v1(c,current_setting('dinner_test.mixed_dinner')::uuid,current_setting('dinner_test.mixed_item')::uuid,'meal');
    raise exception 'Read-only user unexpectedly classified a line';
  exception when insufficient_privilege then null; end;

end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('dinner_test.member'),true);
set local role authenticated;
do $$ declare c uuid:=current_setting('dinner_test.club')::uuid; d uuid:=current_setting('dinner_test.dinner')::uuid; begin
  perform pg_temp.assert_true((select count(*)=0 from public.weekly_dinner_finances),'member direct SELECT has no finance records');
  perform pg_temp.assert_true((select count(*)=0 from public.weekly_dinner_expenses),'member direct SELECT has no treasury links');
  perform pg_temp.assert_true((select count(*)=0 from public.weekly_dinner_financial_snapshots),'member direct SELECT has no snapshots');
  perform pg_temp.assert_true((select count(*)=0 from public.weekly_dinner_sale_item_classifications),'member direct SELECT has no classifications');
  begin
    perform public.classify_weekly_dinner_sale_item_v1(c,current_setting('dinner_test.mixed_dinner')::uuid,current_setting('dinner_test.mixed_item')::uuid,'meal');
    raise exception 'Member unexpectedly classified a line';
  exception when insufficient_privilege then null; end;


  perform pg_temp.must_fail(format('select public.weekly_dinner_finance_v1(%L,%L)',c,d),'member RPC denied');
  perform pg_temp.must_fail(format('select public.weekly_dinner_financial_history_v1(%L,2026)',c),'member history denied');
  perform pg_temp.must_fail('select cost_total_snapshot from public.bar_sale_items','member cost snapshot denied');
  perform 1 from public.bar_weekly_dinner_choices_v1(c); -- operational labels only
  perform pg_temp.assert_true((select count(*)>0 from public.bar_sale_items where club_id=c),'operational sale lines remain readable');
end $$;
reset role;
-- Isolated club: ordering fixtures are relative to the transaction's date,
-- independent of the calendar and of the financial test dinners above.
do $$ declare c uuid:=gen_random_uuid(); actor uuid:=current_setting('dinner_test.manager')::uuid;
  today uuid:=gen_random_uuid(); future_near uuid:=gen_random_uuid(); past_near uuid:=gen_random_uuid();
  future_far uuid:=gen_random_uuid(); past_far uuid:=gen_random_uuid(); financially_closed uuid:=gen_random_uuid();
begin
  insert into public.clubs(id,name) values(c,'Dinner choices ordering fixture');
  insert into public.fixture_permissions values(actor,c,'viewBar');
  insert into public.weekly_dinners(id,club_id,dinner_date,dish,status) values
    (future_far,c,current_date+10,'Future +10','planned'),
    (past_near,c,current_date-2,'Past -2','planned'),
    (today,c,current_date,'Today','planned'),
    (future_near,c,current_date+2,'Future +2','planned'),
    (past_far,c,current_date-10,'Past -10','planned'),
    (gen_random_uuid(),c,current_date+1,'Cancelled','cancelled'),
    (gen_random_uuid(),c,current_date-1,'Operationally closed','closed'),
    (financially_closed,c,current_date+3,'Financially closed','planned');
  insert into public.weekly_dinner_finances(club_id,dinner_id,financial_status,snapshot,closed_at,closed_by)
    values(c,financially_closed,'closed','{}'::jsonb,now(),actor);
  perform set_config('dinner_test.choices_club',c::text,true);
  perform set_config('dinner_test.choices_expected',array[today,future_near,past_near,future_far,past_far]::text,true);
end $$;
select set_config('request.jwt.claim.sub',current_setting('dinner_test.manager'),true);
set local role authenticated;
do $$ declare actual uuid[]; c uuid:=current_setting('dinner_test.choices_club')::uuid; begin
  select array_agg(choice.id order by choice.ordinality) into actual
    from public.bar_weekly_dinner_choices_v1(c) with ordinality as choice;
  perform pg_temp.assert_true(actual=current_setting('dinner_test.choices_expected')::uuid[],
    'today first; +2 before +10; future before past at equal distance; both past and future retained; all closed/cancelled excluded');
  perform pg_temp.assert_true(has_function_privilege('authenticated','public.bar_weekly_dinner_choices_v1(uuid)','execute'),
    'authenticated retains selector EXECUTE');
  perform pg_temp.assert_true(not has_function_privilege('anon','public.bar_weekly_dinner_choices_v1(uuid)','execute'),
    'anon cannot execute selector');
  perform pg_temp.assert_true(not exists(
    select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid='public.bar_weekly_dinner_choices_v1(uuid)'::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),
    'PUBLIC has no selector EXECUTE');
  perform pg_temp.must_fail(format('select * from public.bar_weekly_dinner_choices_v1(%L)',current_setting('dinner_test.foreign_club')),
    'selector still rejects unauthorized clubs');
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
  perform pg_temp.must_fail(format('select public.weekly_dinner_finance_v1(%L,%L)',current_setting('dinner_test.club'),current_setting('dinner_test.dinner')),'null auth rejected');
  perform pg_temp.must_fail(format('select * from public.bar_weekly_dinner_choices_v1(%L)',current_setting('dinner_test.choices_club')),'selector rejects null auth');
end $$;
reset role;
rollback;
select 'weekly_dinner_finance: all local assertions passed' as result;
