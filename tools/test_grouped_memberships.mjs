// Real membership table/RBAC/audit on fixed disposable loopback; all writes rollback.
import {readFileSync,writeFileSync} from 'node:fs';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';import assert from 'node:assert/strict';
const before=process.argv.includes('--before');const {database}=JSON.parse(readFileSync('docs/'+(before?'PHASE_GROUPED_BEFORE_DATABASE.json':'PHASE_BASELINE_REBUILD_RESULTS.json')));assert.match(database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',a='00000000-0000-0000-0000-000000000011',o='00000000-0000-0000-0000-000000000012';const out={database,before,status:'failed'};
try{await sql.unsafe('begin');await sql.unsafe(`insert into auth.users(id,email) values('${u}','member@example.invalid'),('${a}','admin@example.invalid'),('${o}','outsider@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Membership fixture','membership-fixture');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','member',true),('${c}','${a}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);set local role authenticated;`);
assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,false);
const updated=await sql.unsafe(`update public.club_memberships set access_role='super_admin' where club_id='${c}' and profile_id='${u}' returning access_role`);
if(before){assert.equal(updated.length,1);assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,true);out.attack='Member self UPDATE escalated to super_admin and acquired manageMembers';}
else{
assert.equal(updated.length,0);assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,false);
assert.equal((await sql.unsafe(`delete from public.club_memberships where club_id='${c}' and profile_id='${a}' returning id`)).length,0);
await sql.unsafe('savepoint denied');let error;try{await sql.unsafe(`insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${o}','super_admin',true)`);}catch(e){error=e.code;await sql.unsafe('rollback to savepoint denied');}assert.equal(error,'42501');
assert.equal((await sql.unsafe(`select count(*) n from public.club_memberships where club_id='${c}'`))[0].n,'2');
await sql.unsafe(`reset role;update public.club_memberships set active=false where club_id='${c}' and profile_id='${u}';set local role authenticated;`);
assert.equal((await sql.unsafe(`select count(*) n from public.club_memberships where club_id='${c}'`))[0].n,'1');
await sql.unsafe(`reset role;select set_config('request.jwt.claim.sub','${o}',true);set local role authenticated;`);assert.equal((await sql.unsafe('select count(*) n from public.club_memberships'))[0].n,'0');
await sql.unsafe(`reset role;select set_config('request.jwt.claim.sub','${a}',true);set local role authenticated;`);assert.equal((await sql.unsafe(`select count(*) n from public.club_memberships where club_id='${c}'`))[0].n,'2');
assert.equal((await sql.unsafe(`update public.club_memberships set access_role='admin' where club_id='${c}' and profile_id='${u}' returning id`)).length,0);
// Local privileged database writer only. Does not claim a real service-role/Edge stack proof.
await sql.unsafe(`reset role;update public.club_memberships set access_role='admin',active=true where club_id='${c}' and profile_id='${u}';`);
assert.equal((await sql.unsafe(`select access_role from public.club_memberships where profile_id='${u}'`))[0].access_role,'admin');
out.attack='Self role escalation, member DELETE/INSERT, outsider reads denied; active tenant, inactive self, admin SELECT preserved; privileged SQL writer works; Edge integration unproven';
}out.status='passed';
}finally{await sql.unsafe('rollback');await sql.end();writeFileSync('docs/PHASE_GROUPED_MEMBERSHIPS_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify(out,null,2)+'\n');}console.log(JSON.stringify(out));
