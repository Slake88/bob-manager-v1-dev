// Integrated real-table regression. Fixed loopback, disposable DB, rollback.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const replay=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_REBUILD_RESULTS.json'),'utf8'));
assert.match(replay.database,/^bob_clean_rebuild_\d+$/);
const sql=postgres({host:'127.0.0.1',port:55440,user:'postgres',database:replay.database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',m='00000000-0000-0000-0000-000000000030',p='00000000-0000-0000-0000-000000000040';
const results=[];
async function test(name,fn){await sql.unsafe('savepoint check_case');try{await fn();results.push({name,status:'passed'});}catch(e){await sql.unsafe('rollback to savepoint check_case');results.push({name,status:'failed',code:e.code,message:e.message});}console.log(JSON.stringify(results.at(-1)));}
async function rejected(statement,params=[],expected){await sql.unsafe('savepoint expected_failure');let err;try{await sql.unsafe(statement,params);}catch(e){err=e;}await sql.unsafe('rollback to savepoint expected_failure');assert.ok(err,'expected rejection');if(expected)assert.equal(err.code,expected);return err.code;}
try{
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('${u}','contracts@example.invalid');
 insert into public.clubs(id,name,slug) values('${c}','Contracts fixture','contracts-fixture');
 insert into public.club_memberships(id,club_id,profile_id,access_role,active) values('00000000-0000-0000-0000-000000000020','${c}','${u}','super_admin',true);
 select set_config('request.jwt.claim.sub','${u}',true);
 insert into public.inventory_locations(club_id,name,active,location_type) values('${c}','Armazém',true,'storage'),('${c}','Club House',true,'clubhouse');
 insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled)
 select '${c}'::uuid,'${u}'::uuid,x,false,false from unnest(array['members','fees','inventory','events','treasury','documents','general']) x;`);
 await test('Real member INSERT + explicit fee preparation; monthly ON CONFLICT is idempotent',async()=>{
  await sql.unsafe(`insert into public.members(id,club_id,profile_id,full_name,status,joined_at) values('${m}','${c}','${u}','Fixture member','active','2026-01-01')`);
  await sql.unsafe(`select public.prepare_member_fees_year_v1('${c}',2026)`);
  await sql.unsafe(`select public.prepare_member_fees_year_v1('${c}',2026)`);
  assert.equal(Number((await sql.unsafe(`select count(*) n from public.fee_obligations where member_id='${m}' and reference_year=2026 and obligation_type='monthly'`))[0].n),12);
 });
 await test('Obligation negative amount, duplicate month and orphan plan rejected',async()=>{
  const id=(await sql.unsafe(`select id from public.fee_obligations where member_id='${m}' limit 1`))[0]?.id;assert.ok(id);
  await rejected('update public.fee_obligations set amount=-1 where id=$1',[id],'23514');
  await rejected(`insert into public.fee_obligations(club_id,member_id,reference_year,reference_month,amount) values('${c}','${m}',2026,1,25)`,[],'23505');
  await rejected(`update public.fee_obligations set fee_plan_id='00000000-0000-0000-0000-000000000099' where id=$1`,[id],'23503');
 });
 await test('Fee payment batch RPC; allocation uniqueness, positive amount and parent FKs',async()=>{
  await sql.unsafe(`insert into public.treasury_accounts(club_id,name,account_type,active) values('${c}','Quotas','cash',true)`);
  const payment=(await sql.unsafe(`select public.register_fee_payment_batch_v1('${c}','${m}',25,'Dinheiro') id`))[0].id;
  const allocation=(await sql.unsafe('select obligation_id from public.fee_payment_allocations where payment_id=$1',[payment]))[0];assert.ok(allocation);
  await rejected(`insert into public.fee_payment_allocations(club_id,payment_id,obligation_id,amount) values('${c}',$1,$2,1)`,[payment,allocation.obligation_id],'23505');
  await rejected('update public.fee_payment_allocations set amount=0 where payment_id=$1',[payment],'23514');
  // The versioned reference trigger rejects the orphan before FK evaluation.
  await rejected(`update public.fee_payment_allocations set payment_id='00000000-0000-0000-0000-000000000099' where payment_id=$1`,[payment],'P0001');
  assert.equal((await sql.unsafe(`select count(*) n from pg_constraint where conrelid='public.fee_payment_allocations'::regclass and contype='f' and convalidated`))[0].n,'3');
  await rejected('update public.fee_payments set amount=-1 where id=$1',[payment],'23514');
 });
 await test('Product insert and location aggregate triggers remain operational',async()=>{
  await sql.unsafe(`insert into public.products(id,club_id,name,current_stock,active,inventory_area) values('${p}','${c}','Fixture product',10,true,'shop')`);
  assert.equal(Number((await sql.unsafe(`select sum(quantity) n from public.inventory_stock_balances where product_id='${p}'`))[0].n),10);
 });
 await test('Stock movement canonical writer; signed adjustment accepted and orphan product denied',async()=>{
  await sql.unsafe(`insert into public.stock_movements(club_id,product_id,kind,quantity,notes) values('${c}','${p}','adjustment',-1,'Signed adjustment fixture')`);
  await rejected(`insert into public.stock_movements(club_id,product_id,kind,quantity) values('${c}','00000000-0000-0000-0000-000000000099','purchase',1)`,[],'23503');
 });
 await test('Lot receive RPC, aggregate totals, quantity bounds and cost check',async()=>{
  const location=(await sql.unsafe(`select location_id from public.inventory_stock_balances where product_id='${p}' limit 1`))[0]?.location_id;assert.ok(location);
  const id=(await sql.unsafe(`select public.inventory_lot_receive_v1('${c}','${p}',null,$1::uuid,'LOT-1',5) id`,[location]))[0].id;
  const lot=(await sql.unsafe('select initial_quantity,quantity from public.stock_lots where id=$1',[id]))[0];assert.equal(Number(lot.quantity),5);assert.equal(Number(lot.initial_quantity),5);
  assert.equal(Number((await sql.unsafe(`select sum(quantity) n from public.inventory_stock_balances where product_id='${p}'`))[0].n),15);
  await rejected('update public.stock_lots set quantity=initial_quantity+1 where id=$1',[id],'23514');
  await rejected('update public.stock_lots set quantity=-1 where id=$1',[id],'23514');
  await rejected('update public.stock_lots set unit_cost=-1 where id=$1',[id],'23514');
 });
 await test('Reservation create/release RPC; reserved aggregate and expiry bounds',async()=>{
  const location=(await sql.unsafe(`select location_id from public.inventory_stock_balances where product_id='${p}' limit 1`))[0]?.location_id;assert.ok(location);
  const id=(await sql.unsafe(`select public.inventory_reservation_create_v1('${c}','${p}',null,$1::uuid,2,'${m}') id`,[location]))[0].id;
  assert.equal(Number((await sql.unsafe(`select reserved_stock from public.products where id='${p}'`))[0].reserved_stock),2);
  await rejected('update public.stock_reservations set expires_at=reserved_at+interval \'31 days\' where id=$1',[id],'23514');
  await sql.unsafe(`select public.inventory_reservation_close_v1('${c}',$1::uuid,'release','Fixture release')`,[id]);
  assert.equal(Number((await sql.unsafe(`select reserved_stock from public.products where id='${p}'`))[0].reserved_stock),0);
 });
 await test('Physical inventory count executes canonical stock movement writer',async()=>{
  const id=(await sql.unsafe(`select public.inventory_count_start_v1('${c}','Fixture count') id`))[0].id;
  const items=await sql.unsafe('select id,theoretical_qty from public.inventory_count_items where session_id=$1',[id]);assert.ok(items.length);
  for(const item of items)await sql.unsafe(`select public.inventory_count_set_qty_v1('${c}',$1::uuid,$2::numeric)`,[item.id,Number(item.theoretical_qty)+1]);
  await sql.unsafe(`select public.inventory_count_finalize_v1('${c}',$1::uuid)`,[id]);
 });
 await test('Location balance nonnegative/reserved bounds and unique product/location',async()=>{
  const balance=(await sql.unsafe(`select * from public.inventory_stock_balances where product_id='${p}' limit 1`))[0];assert.ok(balance);
  await rejected('update public.inventory_stock_balances set quantity=-1 where id=$1',[balance.id],'23514');
  await rejected('update public.inventory_stock_balances set reserved_quantity=quantity+1 where id=$1',[balance.id],'23514');
  await rejected(`insert into public.inventory_stock_balances(club_id,product_id,location_id) values('${c}','${p}',$1)`,[balance.location_id],'23505');
 });
 await test('Variant current/reserved bounds remain enforced by NOT VALID check',async()=>{
  const id=(await sql.unsafe(`insert into public.product_variants(club_id,product_id,name,current_stock,reserved_stock) values('${c}','${p}','Fixture variant',3,1) returning id`))[0].id;
  await rejected('update public.product_variants set current_stock=-1 where id=$1',[id],'23514');
  await rejected('update public.product_variants set reserved_stock=current_stock+1 where id=$1',[id],'23514');
 });
 await test('Members real-table RLS narrows ALL to SELECT and retains module writes',async()=>{
  await sql.unsafe(`grant select,insert,update,delete on public.members to authenticated,anon; update public.club_memberships set access_role='member' where profile_id='${u}'; drop policy if exists members_tenant on public.members; create policy members_tenant on public.members for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))`);
  await sql.unsafe('set local role authenticated');assert.equal((await sql.unsafe(`update public.members set nickname='Bypass fixture' where id='${m}' returning id`)).length,1);
  await sql.unsafe('reset role');await sql.unsafe('drop policy members_tenant on public.members; create policy members_tenant on public.members for select to authenticated using(public.has_club_access(club_id))');
  await sql.unsafe('set local role authenticated');assert.equal((await sql.unsafe(`select id from public.members where id='${m}'`)).length,1);assert.equal((await sql.unsafe(`update public.members set nickname='Denied fixture' where id='${m}' returning id`)).length,0);await sql.unsafe('reset role');
  await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','manageMembers',true)`);
  await sql.unsafe('set local role authenticated');assert.equal((await sql.unsafe(`update public.members set nickname='Authorized fixture' where id='${m}' returning id`)).length,1);await sql.unsafe('reset role');
 });
 await test('Products real-table RLS before/after, authorized and anon, with triggers enabled',async()=>{
  await sql.unsafe(`grant select,insert,update,delete on public.products to authenticated,anon; update public.club_memberships set access_role='member' where profile_id='${u}'`);
  await sql.unsafe(`create policy products_tenant on public.products for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))`);
  await sql.unsafe('set local role authenticated');
  assert.equal((await sql.unsafe(`update public.products set name='Unauthorized fixture' where id='${p}' returning id`)).length,1);
  await sql.unsafe('reset role');await sql.unsafe('drop policy products_tenant on public.products');
  await sql.unsafe('set local role authenticated');
  assert.equal((await sql.unsafe(`update public.products set name='Denied fixture' where id='${p}' returning id`)).length,0);
  await rejected(`insert into public.products(club_id,name) values('${c}','Denied fixture')`,[],'42501');
  await sql.unsafe('reset role');
  await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','viewInventory',true),('${c}','${u}','manageInventory',true)`);
  await sql.unsafe('set local role authenticated');
  assert.equal((await sql.unsafe(`update public.products set name='Authorized fixture' where id='${p}' returning id`)).length,1);
  await sql.unsafe(`insert into public.products(club_id,name,inventory_area) values('${c}','Authorized fixture','shop')`);
  await sql.unsafe('reset role');await sql.unsafe(`select set_config('request.jwt.claim.sub','',true)`);await sql.unsafe('set local role anon');
  assert.equal((await sql.unsafe(`select id from public.products where id='${p}'`)).length,0);
  await rejected(`insert into public.products(club_id,name) values('${c}','Anon fixture')`,[],'42501');
  await sql.unsafe('reset role');await sql.unsafe(`select set_config('request.jwt.claim.sub','${u}',true)`);
 });
 await test('Notification enabled member trigger and canonical variant writer',async()=>{
  const before=process.argv.includes('--before');
  await sql.unsafe(`update public.club_memberships set access_role='super_admin' where profile_id='${u}'; update public.notification_preferences set in_app_enabled=true where club_id='${c}' and profile_id='${u}' and module_code='members'`);
  const update=`update public.members set full_name='Enabled notifications fixture' where id='${m}'`;
  if(before) await rejected(update,[],'42703');
  else {
   await sql.unsafe(update);
   const rows=await sql.unsafe(`select * from public.notifications where profile_id='${u}' and entity_id='${m}'`);
   assert.ok(rows.length);assert.ok(rows.every(r=>r.notification_type&&r.body&&r.domain_event_id));
   await sql.unsafe('select public.mark_notification_read_v1($1,true)',[rows[0].id]);
   assert.ok((await sql.unsafe('select read_at from public.notifications where id=$1',[rows[0].id]))[0].read_at);
  }
  await sql.unsafe(`update public.notification_preferences set in_app_enabled=false where club_id='${c}' and profile_id='${u}'`);
  const insert=`insert into public.product_variants(product_id,name,current_stock) values('${p}','Canonical writer',3) returning id`;
  if(before)await rejected(insert,[],'23502');
  else {
   await sql.unsafe('grant select,insert,update,delete on public.product_variants to authenticated');
   await sql.unsafe('set local role authenticated');
   const variant=(await sql.unsafe(insert))[0];
   await sql.unsafe('update public.product_variants set name=$1 where id=$2',['Updated canonical writer',variant.id]);
   await sql.unsafe('reset role');
   assert.equal(Number((await sql.unsafe('select sum(quantity) n from public.inventory_stock_balances where variant_id=$1',[variant.id]))[0].n),3);
   await sql.unsafe(`update public.club_memberships set access_role='member' where profile_id='${u}'; delete from public.user_permission_overrides where profile_id='${u}'`);
   await sql.unsafe('set local role authenticated');await rejected(insert,[],'42501');await sql.unsafe('reset role');
  }
 });

}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();}
writeFileSync(resolve(root,'docs/PHASE_POLICY_STRUCTURAL_SQL_RESULTS.json'),JSON.stringify({database:replay.database,scope:'Real tables, constraints, triggers and RPCs; fixtures rolled back; loopback only',results},null,2)+'\n');
if(results.some(r=>r.status==='failed'))process.exitCode=1;
