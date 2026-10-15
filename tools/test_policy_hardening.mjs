// Isolated PostgreSQL policy regression, fixed loopback only. No remote URLs.
// Shadow tables retain column types and exact effective policies. Constraints,
// defaults and triggers are intentionally excluded to isolate RLS from writer drift.
// Real public RBAC helpers and memberships are used, never mocked.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const baseline=JSON.parse(readFileSync(resolve(root,'docs/PHASE_STRUCTURAL_DRIFT_CLASSIFICATION.json'),'utf8'));
const replay=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_REBUILD_RESULTS.json'),'utf8'));
assert.match(replay.database,/^bob_clean_rebuild_\d+$/);
const sql=postgres({host:'127.0.0.1',port:55440,user:'postgres',database:replay.database,max:1,prepare:false,onnotice:()=>{}});
const q=s=>'"'+s.replaceAll('"','""')+'"';
const club='00000000-0000-0000-0000-000000000001';
const user='00000000-0000-0000-0000-000000000010';
const other='00000000-0000-0000-0000-000000000011';
const rowid='00000000-0000-0000-0000-000000000040';
const candidates=baseline.items.filter(i=>i.classification==='D'&&i.kind==='policy');
assert.equal(candidates.length,41);
const results=[];
try {
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('${user}','policy@example.invalid');
 insert into public.clubs(id,name,slug) values('${club}','Policy fixture','policy-fixture');
 insert into public.club_memberships(id,club_id,profile_id,access_role,active) values('00000000-0000-0000-0000-000000000020','${club}','${user}','member',true);
 select set_config('request.jwt.claim.sub','${user}',true);
 create schema policy_probe; grant usage on schema policy_probe to authenticated,anon;`);
 const relations=await sql.unsafe(`select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by c.relname`);
 const policies=await sql.unsafe(`select tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname`);
 const fixtures=new Map();
 for(const {relname} of relations){
  await sql.unsafe(`create table policy_probe.${q(relname)} (like public.${q(relname)}); alter table policy_probe.${q(relname)} add column _probe text;`);
  const cols=await sql.unsafe(`select a.attname name,format_type(a.atttypid,a.atttypmod) type,t.typtype,(select e.enumlabel from pg_enum e where e.enumtypid=t.oid order by e.enumsortorder limit 1) label from pg_attribute a join pg_type t on t.oid=a.atttypid where a.attrelid=$1::regclass and a.attnum>0 and not a.attisdropped`,['public.'+relname]);
  const fixture={_probe:'seed'};
  for(const c of cols){
   await sql.unsafe(`alter table policy_probe.${q(relname)} alter column ${q(c.name)} drop not null`);
   if(c.type.endsWith('[]'))fixture[c.name]=[];
   else if(c.type==='uuid')fixture[c.name]=c.name==='club_id'?club:c.name==='profile_id'?other:c.name==='created_by'||c.name==='requested_by'?user:rowid;
   else if(c.typtype==='e')fixture[c.name]=c.label;
   else if(c.type==='boolean')fixture[c.name]=true;
   else if(/^(numeric|integer|bigint|smallint|double precision|real)/.test(c.type))fixture[c.name]=1;
   else if(c.type==='jsonb'||c.type==='json')fixture[c.name]={};
   else if(c.type==='date')fixture[c.name]='2026-10-14';
   else if(c.type.includes('timestamp'))fixture[c.name]='2026-10-14T12:00:00Z';
   else if(c.type==='text')fixture[c.name]=({status:'pending',visibility:'club',inventory_area:'inventory',access_role:'member',action:'view'}[c.name]??'fixture');
  }
  fixtures.set(relname,fixture);
  await sql.unsafe(`insert into policy_probe.${q(relname)} select * from jsonb_populate_record(null::policy_probe.${q(relname)},$1::jsonb)`,[fixture]);
 }
 // Resolve policy subqueries against identically named shadow relations. Explicit
 // public relation references are redirected; RBAC functions remain in public.
 await sql.unsafe('set local search_path=policy_probe,public');
 const expression=e=>e?.replace(/public\.([a-z_][a-z_0-9]*)/g,(m,n)=>relations.some(r=>r.relname===n)?'policy_probe.'+q(n):m);
 for(const p of policies){
  const command=p.cmd==='ALL'?'ALL':p.cmd;
  await sql.unsafe(`create policy ${q(p.policyname)} on policy_probe.${q(p.tablename)} as ${p.permissive} for ${command} to ${p.roles.map(q).join(',')} ${p.qual?'using ('+expression(p.qual)+')':''} ${p.with_check?'with check ('+expression(p.with_check)+')':''}`);
 }
 // Reconstruct only the candidate policy for the vulnerable control, even when
 // the repaired baseline no longer creates it. Its captured definition is fixed.
 for(const c of candidates){
  await sql.unsafe(`drop policy if exists ${q(c.name)} on policy_probe.${q(c.table)}`);
  await sql.unsafe(`create policy ${q(c.name)} on policy_probe.${q(c.table)} for all to authenticated using(public.has_club_access(club_id)) with check(public.has_club_access(club_id))`);
 }
 for(const {relname} of relations)await sql.unsafe(`alter table policy_probe.${q(relname)} enable row level security; grant select,insert,update,delete on policy_probe.${q(relname)} to authenticated,anon`);
 async function probe(table,operation){
  await sql.unsafe('savepoint operation');
  let result;
  try{
   const target='policy_probe.'+q(table);
   if(operation==='SELECT')result={rows:(await sql.unsafe(`select _probe from ${target} where _probe='seed'`)).length};
   if(operation==='UPDATE')result={rows:(await sql.unsafe(`update ${target} set _probe='updated' where _probe='seed' returning _probe`)).length};
   if(operation==='DELETE')result={rows:(await sql.unsafe(`delete from ${target} where _probe='seed' returning _probe`)).length};
   if(operation==='INSERT')result={rows:(await sql.unsafe(`insert into ${target} select * from jsonb_populate_record(null::${target},$1::jsonb) returning _probe`,[{...fixtures.get(table),_probe:'inserted'}])).length};
  }catch(e){result={rows:0,code:e.code,message:e.message};}
  await sql.unsafe('rollback to savepoint operation');
  return result;
 }
 const ops=['SELECT','INSERT','UPDATE','DELETE'];
 for(const candidate of candidates){
  const {table,name,id,module}=candidate;
  const ps=policies.filter(p=>p.tablename===table&&p.policyname!==name);
  const keys=[...new Set(ps.flatMap(p=>[...(p.qual+' '+p.with_check).matchAll(/'([A-Za-z][A-Za-z0-9]*)'::text/g)].map(m=>m[1])).filter(k=>/^(view|manage|approve|run|edit|sell|perform)/.test(k)))];
  await sql.unsafe(`update public.user_permission_overrides set allowed=false where club_id=$1 and profile_id=$2`,[club,user]);
  await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) select $1::uuid,$2::uuid,k,false from unnest($3::text[]) k on conflict (club_id,profile_id,permission_key) do update set allowed=false`,[club,user,keys]);
  await sql.unsafe('set local role authenticated');
  assert.equal((await sql.unsafe('select public.has_club_access($1::uuid) yes',[club]))[0].yes,true);
  const before={};for(const op of ops)before[op]=await probe(table,op);
  await sql.unsafe('reset role');
  await sql.unsafe(`drop policy if exists ${q(name)} on policy_probe.${q(table)}`);
  if(table==='members')await sql.unsafe(`create policy members_tenant on policy_probe.members for select to authenticated using(public.has_club_access(club_id))`);
  await sql.unsafe('set local role authenticated');
  const after={};for(const op of ops)after[op]=await probe(table,op);
  await sql.unsafe('reset role');
  const bypass=ops.filter(op=>before[op].rows>0&&after[op].rows===0&&(!after[op].code||after[op].code==='42501'));
  await sql.unsafe(`update public.user_permission_overrides set allowed=true where club_id=$1 and profile_id=$2 and permission_key=any($3::text[])`,[club,user,keys]);
  await sql.unsafe('set local role authenticated');
  const authorized={};for(const op of ops)authorized[op]=await probe(table,op);
  await sql.unsafe('reset role');
  await sql.unsafe(`delete from public.user_permission_overrides where club_id=$1 and profile_id=$2`,[club,user]);
  await sql.unsafe(`insert into public.club_role_permissions(club_id,role_key,permission_key,allowed) select $1::uuid,'admin',k,true from unnest($2::text[]) k on conflict(club_id,role_key,permission_key) do update set allowed=true`,[club,keys]);
  await sql.unsafe(`update public.club_memberships set access_role='admin' where club_id=$1 and profile_id=$2`,[club,user]);
  await sql.unsafe('set local role authenticated');
  const manager={};for(const op of ops)manager[op]=await probe(table,op);
  await sql.unsafe('reset role');
  await sql.unsafe(`update public.club_memberships set access_role='super_admin' where club_id=$1 and profile_id=$2`,[club,user]);
  await sql.unsafe('set local role authenticated');
  const superadmin={};for(const op of ops)superadmin[op]=await probe(table,op);
  await sql.unsafe('reset role');
  await sql.unsafe(`update public.club_memberships set access_role='member' where club_id=$1 and profile_id=$2`,[club,user]);
  await sql.unsafe(`select set_config('request.jwt.claim.sub','',true)`);
  await sql.unsafe('set local role anon');
  const anon={};for(const op of ops)anon[op]=await probe(table,op);
  await sql.unsafe('reset role');
  await sql.unsafe(`select set_config('request.jwt.claim.sub',$1,true)`,[user]);
  assert.ok(ops.every(op=>anon[op].rows===0),table+' anon');
  assert.deepEqual(manager,authorized,table+' configured manager retains the authorized contract');
  assert.deepEqual(superadmin,authorized,table+' superadmin retains the authorized contract');
  assert.ok(ops.every(op=>before[op].rows===1),table+' vulnerable control must allow all four operations');
  const errors=[after,authorized,superadmin].flatMap(s=>Object.values(s).filter(r=>r.code&&r.code!=='42501'));
  const classification=errors.length?'D':bypass.length?'C':'B';
  const held=['document_access_log','document_approvals','document_ocr'].includes(table);
  if(!held)assert.equal(authorized.SELECT.rows,1,table+' positive visibility');
  results.push({id,table,name,module,classification,bypass_operations:bypass,permission_keys:keys,before,after,authorized,manager,superadmin,anon,errors,scope:'Exact effective policies on shadow relations, real public RBAC; no constraints/triggers/production ACL assertion',corrected:!policies.some(p=>p.tablename===table&&p.policyname===name&&p.cmd==='ALL'),held_reason:held?'Complementary integrated document results required; shadow helpers alone do not validate ownership paths':null});
  console.log(table+': '+classification+' '+bypass.join(','));
 }
 await sql.unsafe('set local search_path=public');
 const finalPublic=await sql.unsafe(`select tablename,policyname,permissive,roles,cmd,qual,with_check from pg_policies where schemaname='public' order by tablename,policyname`);
 assert.deepEqual(finalPublic,policies,'No public policy is changed by the test');
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();}
writeFileSync(resolve(root,'docs/PHASE_POLICY_HARDENING_RESULTS.json'),JSON.stringify({captured_at:new Date().toISOString(),database:replay.database,scope:'Isolated policy evaluation; fixed loopback; transaction rolled back',results},null,2)+'\n');
