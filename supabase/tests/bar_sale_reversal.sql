-- LOCAL ONLY: bootstrap weekly_dinner_finance, then committed dinner/proximity
-- migrations and 20261011093500_rc1_bar_sale_reversal.sql. Never production.
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

do $$ declare c uuid:=gen_random_uuid(); foreign_c uuid:=gen_random_uuid(); manager uuid:=gen_random_uuid();
  bar_only uuid:=gen_random_uuid(); finance_only uuid:=gen_random_uuid(); p uuid:=gen_random_uuid();
  opt uuid:=gen_random_uuid(); meal uuid:=gen_random_uuid(); dinner uuid:=gen_random_uuid();
  sale uuid; stock_sale uuid; mixed_sale uuid; closed_sale uuid; failed_sale uuid; tx uuid;
  before_items jsonb; before_stock numeric; result jsonb; reversal uuid;
begin
  insert into public.clubs(id,name) values(c,'BAR reversal local'),(foreign_c,'Foreign BAR');
  insert into public.profiles(id,full_name) values(manager,'BAR cashier'),(bar_only,'BAR only'),(finance_only,'Treasury only');
  insert into public.fixture_permissions select manager,c,unnest(array['viewBar','manageBar','reverseTreasuryMovement','viewFinancialReports','approveExpenseRequests']);
  insert into public.fixture_permissions select bar_only,c,unnest(array['viewBar','manageBar']);
  insert into public.fixture_permissions select finance_only,c,unnest(array['viewBar','reverseTreasuryMovement']);
  insert into public.treasury_accounts(club_id,name) values(c,'Caixa');
  insert into public.products(id,club_id,name,inventory_area,cost,current_stock,consumption_unit) values(p,c,'Cerveja','bar',.03,1000,'ml');
  insert into public.bar_product_sale_options(id,club_id,product_id,name,stock_quantity,public_price,member_price) values(opt,c,p,'Copo 0,25 L',250,2.5,2);
  insert into public.bar_sale_presets(id,club_id,name,unit_price,counts_as_dinner_meal) values(meal,c,'Jantar',10,true);
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values(dinner,c,current_date,'Dinner');
  perform set_config('request.jwt.claim.sub',manager::text,true);
  -- Preset + Outro: financial reversal even though no stock operation exists.
  sale:=public.create_bar_sale_v3(c);
  perform public.complete_bar_sale_v3(c,sale,jsonb_build_array(
    jsonb_build_object('kind','preset','preset_id',meal,'quantity',1),
    jsonb_build_object('kind','other','description','Sobremesa','quantity',1,'unit_price',2)),'cash');
  select jsonb_agg(to_jsonb(i) order by id) into before_items from public.bar_sale_items i where sale_id=sale;
  reversal:=public.reverse_bar_sale_v1(c,sale,'Venda duplicada');
  perform pg_temp.assert_true((select status='reversed' from public.bar_sales where id=sale),'terminal reversed status');
  perform pg_temp.assert_true((select count(*)=0 from public.bar_operations where sale_id=sale),'preset/other returns no stock');
  perform pg_temp.assert_true((select current_stock=1000 from public.products where id=p),'no-stock sale leaves stock intact');
  perform pg_temp.assert_true((select amount=12 and kind='expense' and source_type='reversal' and reversal_of=r.original_transaction_id
    from public.treasury_transactions t join public.bar_sale_reversals r on r.reversal_transaction_id=t.id where r.id=reversal),'compensating treasury entry');
  perform pg_temp.assert_true((select count(*)=2 from public.treasury_transactions where club_id=c),'original treasury survives');
  perform pg_temp.assert_true((select jsonb_agg(to_jsonb(i) order by id)=before_items from public.bar_sale_items i where sale_id=sale),'all original non-stock lines preserved');
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''De novo'')',c,sale),'duplicate reversal rejected');
  perform pg_temp.assert_true(public.bar_sale_history_v1(c)->0->>'reversal_reason'='Venda duplicada','history includes preset/other reason');
  perform pg_temp.assert_true(public.bar_sale_history_v1(c)->0->>'completed_actor_name'='BAR cashier','scoped cashier name resolved');

  stock_sale:=public.create_bar_sale_v3(c);
  perform public.complete_bar_sale_v3(c,stock_sale,jsonb_build_array(jsonb_build_object('kind','stock','product_id',p,'sale_option_id',opt,'quantity',1)),'cash');
  select jsonb_agg(to_jsonb(i) order by id) into before_items from public.bar_sale_items i where sale_id=stock_sale;
  perform pg_temp.assert_true((select current_stock=750 from public.products where id=p),'dose consumes 250 rather than 1');
  -- Changing today's conversion and cost must not affect the historical reversal.
  update public.bar_product_sale_options set stock_quantity=400 where id=opt;
  update public.products set cost=.05 where id=p;
  perform public.reverse_bar_sale_v1(c,stock_sale,'Erro de registo');
  perform pg_temp.assert_true((select current_stock=1000 and cost=.05 from public.products where id=p),'exact stock returned, average cost unchanged');
  perform pg_temp.assert_true((select quantity=250 and unit_cost=.03 from public.stock_movements where club_id=c and kind='adjustment' and notes like '%'||stock_sale||'%'),'historical dose/cost used');
  perform pg_temp.assert_true((select jsonb_agg(to_jsonb(i) order by id)=before_items from public.bar_sale_items i where sale_id=stock_sale),'unit/total cost snapshots and all line fields unchanged');
  perform pg_temp.must_fail(format('update public.bar_sale_items set quantity=2 where sale_id=%L',stock_sale),'reversed lines remain immutable');
  perform pg_temp.must_fail(format('delete from public.bar_sale_items where sale_id=%L',stock_sale),'reversed lines cannot be deleted');
  perform pg_temp.must_fail(format('update public.bar_sales set status=''completed'' where id=%L',stock_sale),'reversed sale cannot resurrect');
  perform pg_temp.must_fail(format('delete from public.bar_sales where id=%L',stock_sale),'reversed sale cannot be deleted');
  update public.bar_product_sale_options set stock_quantity=250 where id=opt;

  -- Mixed sale integrates with live dinner calculation and close/association.
  mixed_sale:=public.create_bar_sale_v3(c,p_weekly_dinner=>dinner);
  perform public.complete_bar_sale_v3(c,mixed_sale,jsonb_build_array(
    jsonb_build_object('kind','stock','product_id',p,'sale_option_id',opt,'quantity',2),
    jsonb_build_object('kind','preset','preset_id',meal,'quantity',3),
    jsonb_build_object('kind','other','description','Extra','quantity',1,'unit_price',2)),'cash',p_weekly_dinner=>dinner);
  result:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((result->>'meal_revenue')::numeric=30 and (result->>'beverage_revenue')::numeric=5,'mixed sale contributes before reversal');
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Erro'')',foreign_c,mixed_sale),'cross-club rejected');
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,'' '')',c,mixed_sale),'reason mandatory');
  perform set_config('request.jwt.claim.sub',bar_only::text,true);
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Erro'')',c,mixed_sale),'requires treasury reversal permission');
  perform set_config('request.jwt.claim.sub',finance_only::text,true);
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Erro'')',c,mixed_sale),'requires manageBar');
  perform set_config('request.jwt.claim.sub','',true);
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Erro'')',c,mixed_sale),'requires authenticated identity');
  perform set_config('request.jwt.claim.sub',manager::text,true);
  perform public.reverse_bar_sale_v1(c,mixed_sale,'Venda errada');
  result:=public.weekly_dinner_finance_v1(c,dinner);
  perform pg_temp.assert_true((result->>'meal_quantity')::numeric=0 and (result->>'meal_revenue')::numeric=0
    and (result->>'beverage_revenue')::numeric=0 and (result->>'beverage_cost')::numeric=0 and (result->>'excluded_revenue')::numeric=0,'reversed sale disappears from all dinner totals');
  perform pg_temp.must_fail(format('select public.assign_bar_sale_dinner_v1(%L,%L,%L)',c,mixed_sale,dinner),'reversed sale cannot be associated');
  perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.weekly_dinner_finance_choices_v1(c,dinner)->'sales') x where x->>'id'=mixed_sale::text),'reversed sale not associable');
  perform pg_temp.assert_true((select current_stock=1000 from public.products where id=p),'mixed stock returned');

  closed_sale:=public.create_bar_sale_v3(c,p_weekly_dinner=>dinner);
  perform public.complete_bar_sale_v3(c,closed_sale,jsonb_build_array(jsonb_build_object('kind','preset','preset_id',meal,'quantity',1)),'cash',p_weekly_dinner=>dinner);
  result:=public.set_weekly_dinner_financial_closed_v1(c,dinner,true);
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Erro'')',c,closed_sale),'closed dinner blocks reversal');
  perform pg_temp.assert_true(public.weekly_dinner_finance_v1(c,dinner)=result,'closed snapshot unchanged');
  perform public.set_weekly_dinner_financial_closed_v1(c,dinner,false);
  perform public.reverse_bar_sale_v1(c,closed_sale,'Jantar reaberto');

  failed_sale:=public.create_bar_sale_v3(c);
  perform public.complete_bar_sale_v3(c,failed_sale,jsonb_build_array(jsonb_build_object('kind','stock','product_id',p,'sale_option_id',opt,'quantity',1)),'cash');
  select current_stock into before_stock from public.products where id=p;
  perform set_config('reversal_test.club',c::text,true);
  perform set_config('reversal_test.actor',manager::text,true);
  perform set_config('reversal_test.sale',failed_sale::text,true);
  perform set_config('reversal_test.product',p::text,true);
  perform set_config('reversal_test.stock',before_stock::text,true);
  perform set_config('reversal_test.tx',(select treasury_transaction_id::text from public.bar_sales where id=failed_sale),true);
end $$;
-- Reproduce the already-existing production bar_sales RLS/grants in this
-- disposable test transaction: rejection must come from the integrity trigger,
-- not from missing table privileges in the minimal bootstrap fixture.
alter table public.bar_sales enable row level security;
create policy bar_sales_select on public.bar_sales for select to authenticated
  using(public.has_club_permission(club_id,'viewBar'));
create policy bar_sales_manage on public.bar_sales for all to authenticated
  using(public.has_club_permission(club_id,'manageBar'))
  with check(public.has_club_permission(club_id,'manageBar'));
grant select,insert,update,delete on public.bar_sales to authenticated;
-- Reproduce the existing production audit stamp, which the minimal fixture
-- does not attach to bar_sales. This test-only trigger is rolled back below.
create trigger trg_audit_stamp_v1 before insert or update on public.bar_sales
  for each row execute function public.audit_stamp_row_v1();
create function pg_temp.must_reject(statement text,expected_state text,expected_message text) returns void
language plpgsql as $$ declare rejected boolean:=false; begin
  begin execute statement;
  exception when others then
    if sqlstate is distinct from expected_state or sqlerrm not like expected_message then
      raise exception 'Unexpected rejection: % / %',sqlstate,sqlerrm;
    end if;
    rejected:=true;
  end;
  if not rejected then raise exception 'Expected integrity rejection: %',statement; end if;
end $$;
do $$ declare c uuid:=current_setting('reversal_test.club')::uuid;
  actor uuid:=current_setting('reversal_test.actor')::uuid;
  bar_only uuid; d uuid:=gen_random_uuid(); ev uuid:=gen_random_uuid(); member uuid:=gen_random_uuid();
  tx uuid; closed_sale uuid; draft uuid;
begin
  select profile_id into bar_only from public.fixture_permissions where club_id=c and permission_key='manageBar' and profile_id<>actor;
  insert into public.weekly_dinners(id,club_id,dinner_date,dish) values(d,c,current_date+7,'Integrity association');
  insert into public.events(id,club_id,name) values(ev,c,'Integrity event');
  insert into public.members(id,club_id,full_name,status) values(member,c,'Integrity member','active');
  insert into public.treasury_transactions(club_id,kind,account_id,amount,description)
    select c,'income',id,1,'Other valid transaction' from public.treasury_accounts where club_id=c limit 1 returning id into tx;
  perform set_config('reversal_test.bar_only',bar_only::text,true);
  perform set_config('reversal_test.integrity_dinner',d::text,true);
  perform set_config('reversal_test.integrity_event',ev::text,true);
  perform set_config('reversal_test.integrity_member',member::text,true);
  perform set_config('reversal_test.other_tx',tx::text,true);
end $$;
select set_config('request.jwt.claim.sub',current_setting('reversal_test.bar_only'),true);
set local role authenticated;
do $$ declare s uuid:=current_setting('reversal_test.sale')::uuid; statement text; before_sale jsonb; begin
  select to_jsonb(sale) into before_sale from public.bar_sales sale where id=s;
  -- All referenced identities exist, so a FK failure cannot falsely pass a test.
  for statement in select unnest(array[
    'total_amount=total_amount+1',
    format('treasury_transaction_id=%L::uuid',current_setting('reversal_test.other_tx')),
    'payment_method=''card''',
    'customer_label=''Alterado''',
    'notes=''Alterado''',
    format('event_id=%L::uuid',current_setting('reversal_test.integrity_event')),
    'customer_type=''member''',
    format('member_id=%L::uuid',current_setting('reversal_test.integrity_member')),
    'source_mode=''ocr''',
    'completed_at=completed_at+interval ''1 day''',
    'completed_by=auth.uid()',
    format('club_id=%L::uuid',gen_random_uuid()),
    format('id=%L::uuid',gen_random_uuid())
  ]) loop
    perform pg_temp.must_reject(format('update public.bar_sales set %s where id=%L',statement,s),
      'P0001','Os dados de uma venda concluída são imutáveis.');
  end loop;
  perform pg_temp.must_reject(format('update public.bar_sales set weekly_dinner_id=%L where id=%L',current_setting('reversal_test.integrity_dinner'),s),
    '42501','Sem autorização financeira.');
  perform pg_temp.must_reject(format('update public.bar_sales set status=''reversed'' where id=%L',s),
    'P0001','Utiliza a operação autorizada Anular venda.');
  perform pg_temp.assert_true((select to_jsonb(sale)=before_sale from public.bar_sales sale where id=s),'failed direct UPDATEs preserve the entire sale');
  -- No business change: legitimate audit stamping must not be mistaken for tampering.
  update public.bar_sales set updated_at='2000-01-01',updated_by=null where id=s;
  perform pg_temp.assert_true((select updated_by=auth.uid() and updated_at=now() from public.bar_sales where id=s),'audit stamps permitted without business mutation');
end $$;
reset role;
select set_config('request.jwt.claim.sub',current_setting('reversal_test.actor'),true);
set local role authenticated;
do $$ declare c uuid:=current_setting('reversal_test.club')::uuid; s uuid:=current_setting('reversal_test.sale')::uuid;
  d uuid:=current_setting('reversal_test.integrity_dinner')::uuid; before_sale jsonb; closed_detail jsonb; draft uuid; begin
  select to_jsonb(sale)-array['weekly_dinner_id','updated_at','updated_by'] into before_sale from public.bar_sales sale where id=s;
  perform public.assign_bar_sale_dinner_v1(c,s,d);
  perform pg_temp.assert_true((select weekly_dinner_id=d and
    to_jsonb(sale)-array['weekly_dinner_id','updated_at','updated_by']=before_sale from public.bar_sales sale where id=s),'authorized association only changes dinner and audit metadata');
  closed_detail:=public.set_weekly_dinner_financial_closed_v1(c,d,true);
  perform pg_temp.must_reject(format('select public.assign_bar_sale_dinner_v1(%L,%L,null)',c,s),
    'P0001','Reabre o fecho financeiro antes de alterar as vendas.');
  perform pg_temp.assert_true(public.weekly_dinner_finance_v1(c,d)=closed_detail,'closed association attempt preserves snapshot');
  perform public.set_weekly_dinner_financial_closed_v1(c,d,false);
  perform public.assign_bar_sale_dinner_v1(c,s,null);
  -- Draft updates/cancellation/completion are deliberately unaffected.
  draft:=public.create_bar_sale_v3(c);
  update public.bar_sales set customer_label='Draft edited',notes='Draft notes',payment_method='cash' where id=draft;
  update public.bar_sales set status='cancelled' where id=draft;
  perform pg_temp.assert_true((select status='cancelled' and customer_label='Draft edited' from public.bar_sales where id=draft),'draft editing and cancellation remain supported');
  draft:=public.create_bar_sale_v3(c);
  perform public.complete_bar_sale_v3(c,draft,jsonb_build_array(jsonb_build_object('kind','other','description','Normal completion','quantity',1,'unit_price',2)),'cash');
  perform public.reverse_bar_sale_v1(c,draft,'Normal reversal');
  perform pg_temp.must_reject(format('update public.bar_sales set updated_at=updated_at where id=%L',draft),
    'P0001','Uma venda anulada é imutável.');
end $$;
reset role;
-- Even a pre-existing valid reversal record cannot authorize business mutation
-- during completed -> reversed. Roll back these owner-only test records locally.
do $$ declare c uuid:=current_setting('reversal_test.club')::uuid; s uuid:=current_setting('reversal_test.sale')::uuid;
  tx uuid; statement text; begin
  begin
    insert into public.treasury_transactions(club_id,kind,account_id,amount,description,source_type,reversal_of)
      select club_id,'expense',account_id,amount,'Temporary test reversal','reversal',id
        from public.treasury_transactions where id=current_setting('reversal_test.tx')::uuid returning id into tx;
    insert into public.bar_sale_reversals(club_id,sale_id,original_transaction_id,reversal_transaction_id,reason,created_by)
      values(c,s,current_setting('reversal_test.tx')::uuid,tx,'Test only',auth.uid());
    for statement in select unnest(array['total_amount=total_amount+1','payment_method=''card''','notes=''Changed''',
      format('weekly_dinner_id=%L',current_setting('reversal_test.integrity_dinner')),
      format('treasury_transaction_id=%L',current_setting('reversal_test.other_tx')),
      format('club_id=%L',gen_random_uuid())]) loop
      perform pg_temp.must_reject(format('update public.bar_sales set status=''reversed'',%s where id=%L',statement,s),
        'P0001','A anulação não pode alterar os dados originais da venda.');
    end loop;
    raise exception using errcode='ZX001',message='Rollback owner-only test records';
  exception when sqlstate 'ZX001' then null; end;
end $$;
-- Force a failure AFTER the compensating treasury row and stock update.
create function pg_temp.fail_reversal_stock() returns trigger language plpgsql as $$ begin
  if new.kind::text='adjustment' then raise exception 'Injected local stock error'; end if;
  return new;
end $$;
create trigger local_fail_reversal_stock before insert on public.stock_movements for each row execute function pg_temp.fail_reversal_stock();
set local role authenticated;
do $$ declare c uuid:=current_setting('reversal_test.club')::uuid; s uuid:=current_setting('reversal_test.sale')::uuid; begin
  perform pg_temp.must_fail(format('select public.reverse_bar_sale_v1(%L,%L,''Falha simulada'')',c,s),'mid-operation error propagated');
  perform pg_temp.must_fail(format('insert into public.bar_sale_reversals(club_id,sale_id,original_transaction_id,reversal_transaction_id,reason,created_by) values(%L,%L,%L,%L,''Fake'',auth.uid())',c,s,current_setting('reversal_test.tx'),current_setting('reversal_test.tx')),'direct reversal table DML denied');
  perform pg_temp.must_fail(format('update public.bar_sales set status=''reversed'' where id=%L',s),'direct terminal status counterfeit denied');
  perform pg_temp.assert_true(not has_function_privilege('anon','public.reverse_bar_sale_v1(uuid,uuid,text)','execute'),'anon has no reversal EXECUTE');
  perform pg_temp.assert_true(not has_function_privilege('anon','public.bar_sale_history_v1(uuid,integer)','execute'),'anon has no history EXECUTE');
end $$;
reset role;
drop trigger local_fail_reversal_stock on public.stock_movements;
do $$ declare s uuid:=current_setting('reversal_test.sale')::uuid; c uuid:=current_setting('reversal_test.club')::uuid; begin
  perform pg_temp.assert_true((select status='completed' from public.bar_sales where id=s),'rollback restores sale status');
  perform pg_temp.assert_true((select current_stock=current_setting('reversal_test.stock')::numeric from public.products where id=current_setting('reversal_test.product')::uuid),'rollback restores stock');
  perform pg_temp.assert_true(not exists(select 1 from public.bar_sale_reversals where sale_id=s),'rollback removes reversal metadata');
  perform pg_temp.assert_true(not exists(select 1 from public.treasury_transactions where reversal_of=current_setting('reversal_test.tx')::uuid),'rollback removes compensating treasury entry');
  perform pg_temp.assert_true(not exists(select 1 from public.bar_operations where sale_id=s and operation_type='adjustment_in'),'rollback removes stock operations');
  perform pg_temp.assert_true(exists(select 1 from public.audit_log where entity_type='bar_sale_reversals' and actor_id=auth.uid()),'successful reversals audited');
  perform public.reverse_bar_sale_v1(c,s,'Agora corrigido');
  perform pg_temp.must_reject(format('update public.bar_sales set notes=notes where id=%L',s),'P0001','Uma venda anulada é imutável.');
end $$;
rollback;
select 'bar_sale_reversal: all local assertions passed' as result;
