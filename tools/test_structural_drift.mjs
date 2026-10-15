// Local synthetic RLS regression. An optional previous disposable database
// proves the vulnerable baseline behavior; no remote URL is accepted.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..');
const postgres=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const replay=JSON.parse(readFileSync(resolve(root,'docs/PHASE_BASELINE_REBUILD_RESULTS.json'),'utf8'));
const prod=JSON.parse(readFileSync(resolve(root,'docs/PHASE_STRUCTURAL_PRODUCTION_SNAPSHOT.json'),'utf8'));
const results=[];
async function test(database,fixed){
 assert.match(database,/^bob_clean_rebuild_\d+$/);
 const sql=postgres({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
 try {
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('00000000-0000-0000-0000-000000000010','rls@example.invalid');
 insert into public.clubs(id,name,slug) values('00000000-0000-0000-0000-000000000001','RLS fixture','rls-fixture');
 insert into public.club_memberships(id,club_id,profile_id,access_role,active) values('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','member',true);
 grant select,insert,update,delete on public.activity_feed,public.announcements to authenticated;
 select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000010',true);
 insert into public.activity_feed(club_id,activity_type,title,metadata) values('00000000-0000-0000-0000-000000000001','members','Hidden member event','{"module_code":"members"}');
 insert into public.announcements(id,club_id,title,body) values('00000000-0000-0000-0000-000000000040','00000000-0000-0000-0000-000000000001','Protected announcement','Synthetic announcement body');
 select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000010',true);`);
 const pol=await sql.unsafe(`select tablename,policyname,cmd,qual,with_check from pg_policies where schemaname='public' and tablename in ('activity_feed','announcements') order by tablename,policyname`);
 if(fixed)for(const name of ['activity_feed','announcements']){
 const expected=prod.relations.find(t=>t.name===name).policies;
 assert.deepEqual(pol.filter(x=>x.tablename===name).map(x=>x.policyname),expected.map(x=>x.name).sort());
 }
 await sql.unsafe('set local role authenticated');
 assert.equal((await sql.unsafe(`select has_club_access('00000000-0000-0000-0000-000000000001') allowed`))[0].allowed,true);
 assert.equal((await sql.unsafe(`select has_club_permission('00000000-0000-0000-0000-000000000001','manageCommunication') allowed`))[0].allowed,false);
 assert.equal((await sql.unsafe(`select has_club_permission('00000000-0000-0000-0000-000000000001','viewMembers') allowed`))[0].allowed,false);
 const visible=Number((await sql.unsafe(`select count(*) n from public.activity_feed where title='Hidden member event'`))[0].n);
 assert.equal(visible,fixed?0:1);
 const updated=await sql.unsafe(`update public.announcements set title='Unauthorized update' where id='00000000-0000-0000-0000-000000000040' returning id`);
 assert.equal(updated.length,fixed?0:1);
 const deleted=await sql.unsafe(`delete from public.announcements where id='00000000-0000-0000-0000-000000000040' returning id`);
 assert.equal(deleted.length,fixed?0:1);
 await sql.unsafe('savepoint denied_insert');let code;
 try {await sql.unsafe(`insert into public.announcements(club_id,title,body) values('00000000-0000-0000-0000-000000000001','Unauthorized insert','Synthetic announcement body')`);}catch(e){code=e.code;}
 await sql.unsafe('rollback to savepoint denied_insert');assert.equal(code,fixed?'42501':undefined);
 await sql.unsafe('reset role');
 if(fixed){
 await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','manageCommunication',true),('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000010','viewMembers',true)`);
 await sql.unsafe('set local role authenticated');
 assert.equal(Number((await sql.unsafe(`select count(*) n from public.activity_feed where title='Hidden member event'`))[0].n),1);
 assert.equal((await sql.unsafe(`update public.announcements set title='Authorized update' where id='00000000-0000-0000-0000-000000000040' returning id`)).length,1);
 await sql.unsafe(`insert into public.announcements(club_id,title,body) values('00000000-0000-0000-0000-000000000001','Authorized insert','Synthetic announcement body')`);
 assert.equal((await sql.unsafe(`delete from public.announcements where id='00000000-0000-0000-0000-000000000040' returning id`)).length,1);
 }
 results.push({database,fixed,status:'passed',checks:['active membership is insufficient for module permission','restricted feed visibility','announcement INSERT/UPDATE/DELETE denial',...(fixed?['positive permission overrides permit operations','policy names match current production']:['pre-fix bypass reproduced'])],grant_note:'Table privileges granted only inside rollback to isolate RLS from environment ACLs'});
 }finally {await sql.unsafe('rollback').catch(()=>{});await sql.end();}
}
if(process.argv[3])await test(process.argv[3],false);
await test(replay.database,true);
writeFileSync(resolve(root,'docs/PHASE_STRUCTURAL_SQL_RESULTS.json'),JSON.stringify({status:'passed',results},null,2)+'\n');
console.log(JSON.stringify(results,null,2));
