// Disposable loopback database only; all fixture changes rolled back.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const before=process.argv.includes('--before');
const ref='docs/'+(before?'PHASE_GROUPED_BEFORE_DATABASE.json':'PHASE_BASELINE_REBUILD_RESULTS.json');
const {database}=JSON.parse(readFileSync(ref));assert.match(database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const results=[];
async function probe(name,fn){await sql.unsafe('savepoint probe');try{await fn();results.push({name,status:'passed'});}catch(e){results.push({name,status:'failed',code:e.code,message:e.message});}finally{await sql.unsafe('rollback to savepoint probe');}}
async function rejects(statement,code){await sql.unsafe('savepoint reject');let err;try{await sql.unsafe(statement);}catch(e){err=e;}await sql.unsafe('rollback to savepoint reject');assert.equal(err?.code,code);}
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',m='00000000-0000-0000-0000-000000000030';
const tables=['fee_credits','fee_exemptions','fee_adjustments','reported_payments'];
try{
await sql.unsafe('begin');
await sql.unsafe(`insert into auth.users(id,email) values('${u}','grouped@example.invalid');
insert into public.clubs(id,name,slug) values('${c}','Grouped fixture','grouped-fixture');
insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);
select set_config('request.jwt.claim.sub','${u}',true);
insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled) select '${c}'::uuid,'${u}'::uuid,x,false,false from unnest(array['members','fees','general']) x;
insert into public.members(id,club_id,profile_id,full_name,status,joined_at) values('${m}','${c}','${u}','Grouped fixture','active','2026-01-01');
select public.prepare_member_fees_year_v1('${c}',2026);`);
const oid=(await sql.unsafe(`select id from public.fee_obligations where member_id='${m}' order by reference_month limit 1`))[0].id;
await probe('Authenticated credit adjustment RPC and read balance',async()=>{
await sql.unsafe('set local role authenticated');
const id=(await sql.unsafe(`select public.add_fee_credit_adjustment_v1('${c}','${m}',10,'Fixture credit') id`))[0].id;
assert.equal((await sql.unsafe('select entry_type from public.fee_credits where id=$1',[id]))[0].entry_type,'manual_adjustment');
await sql.unsafe('reset role');
});
for(const [table,kind] of [['fee_exemptions','exemption'],['fee_adjustments','adjustment']])await probe('Authenticated '+kind+' create and reverse RPCs',async()=>{
await sql.unsafe('set local role authenticated');
const id=(await sql.unsafe(`select public.apply_fee_${kind}_v1('${c}','${oid}',1,'Fixture reason') id`))[0].id;
assert.equal((await sql.unsafe(`select status from public.${table} where id=$1`,[id]))[0].status,'active');
await sql.unsafe(`select public.reverse_fee_${kind}_v1('${c}',$1,'Fixture reversal')`,[id]);
const row=(await sql.unsafe(`select status,reversed_at,reversed_by,reversal_reason from public.${table} where id=$1`,[id]))[0];
assert.equal(row.status,'reversed');assert.ok(row.reversed_at);assert.equal(row.reversed_by,u);assert.equal(row.reversal_reason,'Fixture reversal');
await rejects(`select public.reverse_fee_${kind}_v1('${c}','${id}','Fixture duplicate')`,'P0001');
await sql.unsafe('reset role');
});
for(const action of ['reject','cancel','approve'])await probe('Reported payment '+action+' through authenticated real RPCs',async()=>{
await sql.unsafe("insert into public.treasury_accounts(club_id,name,account_type,active) values($1,'Quotas','cash',true)",[c]);
await sql.unsafe('set local role authenticated');
const id=(await sql.unsafe("select public.create_reported_fee_payment_v1($1,5,current_date,'Dinheiro','Fixture notes',$2,'proof.pdf','application/pdf',100) id",[c,c+'/'+u+'/proof.pdf']))[0].id;
if(action==='cancel')await sql.unsafe('select public.cancel_reported_fee_payment_v1($1,$2)',[c,id]);
else await sql.unsafe("select public.review_reported_fee_payment_v1($1,$2,$3,'Fixture review')",[c,id,action]);
const r=(await sql.unsafe('select status,fee_payment_id from public.reported_payments where id=$1',[id]))[0];
assert.equal(r.status,{reject:'rejected',cancel:'cancelled',approve:'approved'}[action]);
if(action==='approve')assert.ok(r.fee_payment_id);
await sql.unsafe('reset role');
});
const snapshot=JSON.parse(readFileSync('docs/PHASE_STRUCTURAL_PRODUCTION_SNAPSHOT.json'));
for(const table of tables){
const remote=snapshot.relations.find(t=>t.name===table);
await probe(table+' canonical column contracts',async()=>{
for(const col of remote.columns){const actual=(await sql.unsafe(`select format_type(a.atttypid,a.atttypmod) type,a.attnotnull as "notnull",pg_get_expr(d.adbin,d.adrelid) "default" from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum where a.attrelid=$1::regclass and a.attname=$2 and not a.attisdropped`,['public.'+table,col.name]))[0];assert.deepEqual(actual,{type:col.type,notnull:col.notnull,default:col.default},table+'.'+col.name);}
});
await probe(table+' canonical constraints',async()=>{
for(const con of remote.constraints){const actual=(await sql.unsafe(`select pg_get_constraintdef(oid) definition,convalidated validated from pg_constraint where conrelid=$1::regclass and conname=$2`,['public.'+table,con.name]))[0];assert.deepEqual(actual,{definition:con.definition,validated:con.validated},con.name);}
});
await probe(table+' declarative boundaries with user triggers disabled in rollback',async()=>{
// Isolate SQL constraints from reference guards and audit stamps; no persistent trigger changes.
await sql.unsafe(`alter table public.${table} disable trigger user`);
const cols=table==='reported_payments'?'club_id,member_id,amount,paid_on,payment_method,proof_path,proof_name':table==='fee_credits'?'club_id,member_id,amount,entry_type':'club_id,member_id,obligation_id,amount,reason';
const vals=table==='reported_payments'?`'${c}','${m}',1,current_date,'Dinheiro','fixture/proof.pdf','proof.pdf'`:table==='fee_credits'?`'${c}','${m}',1,'manual_adjustment'`:`'${c}','${m}','${oid}',1,'Fixture reason'`;
const row=(await sql.unsafe(`insert into public.${table}(${cols}) values(${vals}) returning id`))[0];
await rejects(`update public.${table} set amount=0 where id='${row.id}'`,'23514');
await rejects(`update public.${table} set amount=null where id='${row.id}'`,'23502');
await rejects(`update public.${table} set member_id=null where id='${row.id}'`,'23502');
await rejects(`update public.${table} set member_id='00000000-0000-0000-0000-000000000099' where id='${row.id}'`,'23503');
await rejects(`update public.${table} set amount=10000000000 where id='${row.id}'`,'22003');
if(table==='fee_credits')await rejects(`update public.${table} set entry_type='invalid' where id='${row.id}'`,'23514');
else if(table==='reported_payments'){await rejects(`update public.${table} set proof_size=-1 where id='${row.id}'`,'23514');await rejects(`update public.${table} set status='invalid' where id='${row.id}'`,'23514');}
else {await rejects(`update public.${table} set status='invalid' where id='${row.id}'`,'23514');await rejects(`update public.${table} set reason=null where id='${row.id}'`,'23502');}
});
}
}finally{await sql.unsafe('rollback');await sql.end();writeFileSync('docs/PHASE_GROUPED_FEES_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify({database,before,results},null,2)+'\n');}
console.log(JSON.stringify(results));
if(before)assert.ok(results.some(r=>r.status==='failed'&&r.code==='42703'));
else assert.ok(results.every(r=>r.status==='passed'));
