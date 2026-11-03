// Real operations writers on loopback; rollback synthetic fixtures.
import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const before=process.argv.includes('--before');const {database}=JSON.parse(readFileSync('docs/'+(before?'PHASE_GROUPED_BEFORE_DATABASE.json':'PHASE_BASELINE_REBUILD_RESULTS.json')));assert.match(database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const results=[];const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',e='00000000-0000-0000-0000-000000000040';
async function probe(name,fn){await sql.unsafe('savepoint probe');try{await fn();results.push({name,status:'passed'});}catch(err){results.push({name,status:'failed',code:err.code,message:err.message});}finally{await sql.unsafe('rollback to savepoint probe');}}
async function rejects(s,code){await sql.unsafe('savepoint rejection');let err;try{await sql.unsafe(s);}catch(e){err=e;}await sql.unsafe('rollback to savepoint rejection');assert.equal(err?.code,code);}
const snapshot=JSON.parse(readFileSync('docs/PHASE_STRUCTURAL_PRODUCTION_SNAPSHOT.json'));
try{await sql.unsafe('begin');await sql.unsafe(`insert into auth.users(id,email) values('${u}','operations@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Operations fixture','operations-fixture');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);`);
await probe('Real event INSERT with location text and activity trigger',async()=>{await sql.unsafe(`insert into public.events(club_id,name,status,location) values('${c}','Location fixture','published','Lisboa')`);});
if(before){const triggers=await sql.unsafe("select tgname from pg_trigger where tgrelid='public.events'::regclass and tgfoid='public.activity_event_trigger_v1()'::regprocedure and not tgisinternal");for(const t of triggers)await sql.unsafe('alter table public.events disable trigger '+t.tgname);}
await sql.unsafe(`insert into public.events(id,club_id,name,status) values('${e}','${c}','Operations fixture','published')`);
await sql.unsafe(`insert into public.inventory_locations(club_id,name,active,location_type) values('${c}','Armazém',true,'storage'),('${c}','Club House',true,'clubhouse')`);
await probe('Product normalized saveProduct payload and critical read model',async()=>{
await sql.unsafe('set local role authenticated');
const id=(await sql.unsafe(`insert into public.products(club_id,name,sku,category,unit,current_stock,reserved_stock,minimum_stock,cost,sale_price,active) values('${c}','Fixture product','SKU-1','fixture','unit',0,0,2,1,2,true) returning id`))[0].id;
await sql.unsafe(`update public.products set sku='SKU-2',minimum_stock=3,unit='un' where id=$1`,[id]);
const p=(await sql.unsafe('select sku,unit,minimum_stock from public.products where id=$1',[id]))[0];assert.equal(p.sku,'SKU-2');assert.equal(p.unit,'un');assert.equal(Number(p.minimum_stock),3);await sql.unsafe('reset role');
});
for(const table of ['event_bands','event_exhibitors','event_sponsors']){
const value=table==='event_sponsors'?'received_value':'paid_value';
await probe(table+' authenticated save payload, update and defaults',async()=>{
await sql.unsafe('set local role authenticated');
const id=(await sql.unsafe(`insert into public.${table}(club_id,event_id,name,contact_name,phone,email,agreed_value,${value},notes) values('${c}','${e}','Fixture','Contact','000','fixture@example.invalid',10,2,'Fixture notes') returning id`))[0].id;
assert.equal((await sql.unsafe(`select status from public.${table} where id=$1`,[id]))[0].status,'planned');
await sql.unsafe(`update public.${table} set status='confirmed',${value}=3 where id=$1`,[id]);
assert.equal(Number((await sql.unsafe(`select ${value} value from public.${table} where id=$1`,[id]))[0].value),3);
await rejects(`update public.${table} set agreed_value=-1 where id='${id}'`,'23514');await rejects(`update public.${table} set status='invalid' where id='${id}'`,'23514');await rejects(`update public.${table} set event_id=null where id='${id}'`,'P0001');
if(table==='event_bands')await rejects(`update public.${table} set slot_start='2026-01-02',slot_end='2026-01-01' where id='${id}'`,'23514');
await sql.unsafe('reset role');
});
await probe(table+' canonical columns and constraints',async()=>{
const remote=snapshot.relations.find(t=>t.name===table);
for(const col of remote.columns){const a=(await sql.unsafe(`select format_type(a.atttypid,a.atttypmod) type,a.attnotnull as "notnull",pg_get_expr(d.adbin,d.adrelid) "default" from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=$1::regclass and a.attname=$2 and not a.attisdropped`,['public.'+table,col.name]))[0];assert.deepEqual(a,{type:col.type,notnull:col.notnull,default:col.default},table+'.'+col.name);}
for(const k of remote.constraints){const a=(await sql.unsafe('select pg_get_constraintdef(oid) definition,convalidated validated from pg_constraint where conrelid=$1::regclass and conname=$2',['public.'+table,k.name]))[0];assert.deepEqual(a,{definition:k.definition,validated:k.validated},k.name);}
});
await probe(table+' parent cascade and orphan rejection with guards isolated',async()=>{
await sql.unsafe(`alter table public.${table} disable trigger user`);
const id=(await sql.unsafe(`insert into public.${table}(club_id,event_id,name) values('${c}','${e}','Cascade fixture') returning id`))[0].id;
await rejects(`update public.${table} set event_id='00000000-0000-0000-0000-000000000099' where id='${id}'`,'23503');
await sql.unsafe(`delete from public.events where id='${e}'`);
assert.equal((await sql.unsafe(`select count(*) n from public.${table} where id=$1`,[id]))[0].n,'0');
});
}
}finally{await sql.unsafe('rollback');await sql.end();writeFileSync('docs/PHASE_GROUPED_OPERATIONS_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify({database,before,results},null,2)+'\n');}
console.log(JSON.stringify(results));if(before)assert.ok(results.some(r=>r.code==='42703'));else assert.ok(results.every(r=>r.status==='passed'));
