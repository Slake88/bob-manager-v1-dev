-- Local-only synthetic regression. No remote endpoint accepted.
begin;
do $$ begin
 if current_database() not like 'bob_phase2c7_%' or inet_server_addr() is distinct from inet '127.0.0.1' or inet_server_port()<>55440 then raise exception 'Local harness required'; end if;
end $$;
create function pg_temp.id(k integer,n integer) returns uuid language sql immutable as $$ select (lpad(k::text,8,'0')||'-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
insert into auth.users(id) values(pg_temp.id(1,1)),(pg_temp.id(1,2));
insert into profiles(id,full_name,email) select id,'Synthetic',id||'@example.invalid' from auth.users;
insert into clubs(id,name,slug) values(pg_temp.id(2,1),'Local A','local-a'),(pg_temp.id(2,2),'Local B','local-b');
select set_config('request.jwt.claim.sub',pg_temp.id(1,1)::text,true);
insert into club_memberships(club_id,profile_id,active,access_role) values
 (pg_temp.id(2,1),pg_temp.id(1,1),true,'member'),(pg_temp.id(2,2),pg_temp.id(1,1),true,'member'),(pg_temp.id(2,1),pg_temp.id(1,2),true,'member');
insert into user_permission_overrides(club_id,profile_id,permission_key,allowed)
 select pg_temp.id(2,1),pg_temp.id(1,1),p,true from unnest(array['createTreasuryMovement','transferBetweenAccounts','manageMembers','manageAssets','manageMerchandising']) p;
insert into members(id,club_id,full_name,status,joined_at) select pg_temp.id(3,n),pg_temp.id(2,n),'Member','active',current_date from generate_series(1,2) n;
insert into events(id,club_id,name,status) select pg_temp.id(4,n),pg_temp.id(2,n),'Event','published' from generate_series(1,2) n;
insert into treasury_categories(id,club_id,name,direction,active) select pg_temp.id(5,n),pg_temp.id(2,n),'Category','both',false from generate_series(1,2) n;
insert into cost_centers(id,club_id,name,active) select pg_temp.id(6,n),pg_temp.id(2,n),'Center',false from generate_series(1,2) n;
insert into club_positions(id,club_id,code,name,active) select pg_temp.id(7,n),pg_temp.id(2,n),'fixture','Position',false from generate_series(1,2) n;
insert into inventory_assets(id,club_id,name,active) select pg_temp.id(8,n),pg_temp.id(2,n),'Asset',true from generate_series(1,2) n;
insert into inventory_assets(id,club_id,name,active) values(pg_temp.id(8,3),pg_temp.id(2,1),'Inactive asset',false);
insert into inventory_locations(club_id,name) select pg_temp.id(2,n),'Armazém' from generate_series(1,2) n;
insert into products(id,club_id,name,inventory_area) select pg_temp.id(9,n),pg_temp.id(2,n),'Product','shop' from generate_series(1,2) n;
insert into product_variants(id,product_id,name) select pg_temp.id(10,n),pg_temp.id(9,n),'Variant' from generate_series(1,2) n;
insert into treasury_accounts(id,club_id,name,account_type,allows_negative) select pg_temp.id(11,n),pg_temp.id(2,n),'Cash','cash',true from generate_series(1,2) n;
insert into treasury_accounts(id,club_id,name,account_type,allows_negative) values(pg_temp.id(11,3),pg_temp.id(2,1),'Destination','cash',true);
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin if ok is not true then raise exception 'Assertion: %',label; end if; end $$;
create function pg_temp.snapshot() returns jsonb language plpgsql as $$ declare t record; v jsonb; result jsonb:='{}'; begin
 for t in select schemaname,tablename from pg_tables where schemaname in ('public','net','storage') order by schemaname,tablename loop
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %I.%I t',t.schemaname,t.tablename) into v;
 result:=result||jsonb_build_object(t.schemaname||'.'||t.tablename,v); end loop;
 return result; end $$;
create temp table cases(label text, stmt text, message text, verify text);
insert into cases values('treasury same club (inactive optional references allowed)','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)',null,'select category_id=pg_temp.id(5,1) and cost_center_id=pg_temp.id(6,1) and event_id=pg_temp.id(4,1) and created_by=auth.uid() from treasury_transactions where id=$1');
insert into cases values('member same club (inactive optional references allowed)','select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,1))',null,'select exists(select 1 from member_positions where member_id=$1 and position_id=pg_temp.id(7,1) and club_id=pg_temp.id(2,1))');
insert into cases values('loan same club (inactive optional references allowed)','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')',null,'select member_id=pg_temp.id(3,1) and event_id=pg_temp.id(4,1) and external_name=''External'' and notes=''Notes'' and exists(select 1 from asset_events where metadata->>''loan_id''=$1::text) from asset_loans where id=$1');
insert into cases values('log same club (inactive optional references allowed)','select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,1),''note'',''Fixture'',null,null)',null,'select asset_id=pg_temp.id(8,1) and metadata=''{}''::jsonb from asset_events where id=$1');
insert into cases values('shop same club (inactive optional references allowed)','select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')',null,'select total_amount=10 and member_id=pg_temp.id(3,1) and exists(select 1 from shop_order_items where order_id=$1 and variant_id=pg_temp.id(10,1)) and exists(select 1 from domain_events where event_name=''ShopOrderCreated'') from shop_orders where id=$1');
insert into cases values('treasury null','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,null,null,null,current_date,''Fixture'',10,''cash'',null)',null,null);
insert into cases values('member null','select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,null)',null,null);
insert into cases values('loan null','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',null,null,'' External '',null,'' Notes '')',null,null);
insert into cases values('loan external null','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''external'',null,null,'' External '',null,'' Notes '')',null,null);
insert into cases values('loan event null','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''event'',null,null,'' External '',null,'' Notes '')',null,null);
insert into cases values('shop null','select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),null,2,5,null,'' External '',null,'' Notes '')',null,null);
insert into cases values('log inactive asset','select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,3),''note'',''Fixture'',null,null)',null,null);
insert into cases values('transfer','select create_treasury_transaction(pg_temp.id(2,1),''transfer'',pg_temp.id(11,1),pg_temp.id(11,3),pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)',null,null);
insert into cases values('income ignored destination','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),pg_temp.id(11,2),pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)',null,null);
insert into cases values('category cross','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,2),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)','Categoria: referência inválida para o clube.',null);
insert into cases values('center cross','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,2),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)','Centro de custo: referência inválida para o clube.',null);
insert into cases values('treasury event cross','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,2),current_date,''Fixture'',10,''cash'',null)','Evento: referência inválida para o clube.',null);
insert into cases values('position cross','select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,2))','Cargo: referência inválida para o clube.',null);
insert into cases values('loan member cross','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,2),pg_temp.id(4,1),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('loan event cross','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,2),'' External '',null,'' Notes '')','Evento: referência inválida para o clube.',null);
insert into cases values('asset log cross','select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,2),''note'',''Fixture'',null,null)','Bem patrimonial: referência inválida para o clube.',null);
insert into cases values('shop member cross','select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,2),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('external loan member cross','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''external'',pg_temp.id(3,2),pg_temp.id(4,1),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('member loan event cross','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,2),'' External '',null,'' Notes '')','Evento: referência inválida para o clube.',null);
insert into cases values('category missing','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,99),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)','Categoria: referência inválida para o clube.',null);
insert into cases values('center missing','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,99),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)','Centro de custo: referência inválida para o clube.',null);
insert into cases values('treasury event missing','select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,99),current_date,''Fixture'',10,''cash'',null)','Evento: referência inválida para o clube.',null);
insert into cases values('position missing','select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,99))','Cargo: referência inválida para o clube.',null);
insert into cases values('loan member missing','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,99),pg_temp.id(4,1),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('loan event missing','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,99),'' External '',null,'' Notes '')','Evento: referência inválida para o clube.',null);
insert into cases values('asset log missing','select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,99),''note'',''Fixture'',null,null)','Bem patrimonial: referência inválida para o clube.',null);
insert into cases values('shop member missing','select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,99),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('external loan member missing','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''external'',pg_temp.id(3,99),pg_temp.id(4,1),'' External '',null,'' Notes '')','Membro: referência inválida para o clube.',null);
insert into cases values('member loan event missing','select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,99),'' External '',null,'' Notes '')','Evento: referência inválida para o clube.',null);
insert into cases values('null required asset','select log_asset_event_v1(pg_temp.id(2,1),null,''note'',''Fixture'',null,null)','Bem patrimonial: referência inválida para o clube.',null);
-- BEGIN ASSERTIONS
create function pg_temp.attempt(stmt text, expected text, verify text default null) returns void language plpgsql as $$
declare result uuid; code text; message text; ok boolean; before jsonb;
begin
 before:=pg_temp.snapshot();
 begin
  set local role authenticated;
  execute stmt into result;
  perform pg_temp.assert(expected is null,'unexpected success: '||stmt);
  perform pg_temp.assert(result is not null,'uuid return: '||stmt);
  if verify is not null then
   reset role;
   execute verify into ok using result;
   perform pg_temp.assert(ok,'stored contract: '||stmt);
  end if;
  -- Undo every successful synthetic call after checking its real effects.
  raise exception 'successful case rollback' using errcode='Z0001';
 exception when sqlstate 'Z0001' then null;
 when others then
  get stacked diagnostics code=returned_sqlstate,message=message_text;
  if expected is null or code<>'22023' or message<>expected then raise exception 'Wrong result for %: [%] % (expected %)',stmt,code,message,expected; end if;
 end;
 reset role;
 perform pg_temp.assert(before=pg_temp.snapshot(),'no residual business/audit/notification/net mutation: '||stmt);
end $$;
do $$ declare r record; begin
 for r in select * from cases loop perform pg_temp.attempt(r.stmt,r.message,r.verify); end loop;
end $$;
-- Existing checks still reject foreign accounts/assets/products/variants.
create function pg_temp.legacy_reject(stmt text, expected_code text default 'P0001', test_role text default 'authenticated') returns void language plpgsql as $$
declare before jsonb; code text; message text;
begin
 before:=pg_temp.snapshot();
 begin
  execute format('set local role %I',test_role); execute stmt;
  raise exception 'Unexpected success' using errcode='Z0002';
 exception when others then
  get stacked diagnostics code=returned_sqlstate,message=message_text;
  if code<>expected_code then raise exception 'Unexpected error %: % for %',code,message,stmt; end if;
 end;
 reset role;
 perform pg_temp.assert(before=pg_temp.snapshot(),'legacy rejection leaves zero mutations');
end $$;
select pg_temp.legacy_reject('select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,2),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)');
select pg_temp.legacy_reject('select create_treasury_transaction(pg_temp.id(2,1),''transfer'',pg_temp.id(11,1),pg_temp.id(11,2),pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)');
select pg_temp.legacy_reject('select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,2),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')');
select pg_temp.legacy_reject('select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,99),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')');
select pg_temp.legacy_reject('select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,2),null,2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')');
select pg_temp.legacy_reject('select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,2),2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')');
-- Authorization is evaluated before new UUID checks. Compare baseline permission messages in harness.
select set_config('request.jwt.claim.sub',pg_temp.id(1,2)::text,true);
select pg_temp.legacy_reject('select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)');
select pg_temp.legacy_reject('select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,1))');
select pg_temp.legacy_reject('select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')');
select pg_temp.legacy_reject('select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,1),''note'',''Fixture'',null,null)');
select pg_temp.legacy_reject('select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.legacy_reject('select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)');
select pg_temp.legacy_reject('select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,1))');
select pg_temp.legacy_reject('select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')');
select pg_temp.legacy_reject('select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,1),''note'',''Fixture'',null,null)');
select pg_temp.legacy_reject('select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')');
-- No API exposure to anon; effective PUBLIC privileges checked in harness.
select pg_temp.legacy_reject('select create_treasury_transaction(pg_temp.id(2,1),''income'',pg_temp.id(11,1),null,pg_temp.id(5,1),pg_temp.id(6,1),pg_temp.id(4,1),current_date,''Fixture'',10,''cash'',null)','42501','anon');
select pg_temp.legacy_reject('select create_member_with_position(pg_temp.id(2,1),909,''Fixture'',null,null,null,current_date,pg_temp.id(7,1))','42501','anon');
select pg_temp.legacy_reject('select asset_loan_v1(pg_temp.id(2,1),pg_temp.id(8,1),''member'',pg_temp.id(3,1),pg_temp.id(4,1),'' External '',null,'' Notes '')','42501','anon');
select pg_temp.legacy_reject('select log_asset_event_v1(pg_temp.id(2,1),pg_temp.id(8,1),''note'',''Fixture'',null,null)','42501','anon');
select pg_temp.legacy_reject('select create_shop_order_v1(pg_temp.id(2,1),pg_temp.id(9,1),pg_temp.id(10,1),2,5,pg_temp.id(3,1),'' External '',null,'' Notes '')','42501','anon');
reset role;
rollback;
