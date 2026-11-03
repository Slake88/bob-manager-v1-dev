// Actual public table, helpers and triggers. Local loopback; all fixtures/grants rollback.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const root=resolve(import.meta.dirname,'..'),before=process.argv.includes('--before');
const replay=JSON.parse(readFileSync(resolve(root,before?'docs/PHASE_AMBIGUOUS_ADDRESS_BEFORE.json':'docs/PHASE_BASELINE_REBUILD_RESULTS.json')));
assert.match(replay.database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database:replay.database,max:1,prepare:false,onnotice:()=>{}});
const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010',a='00000000-0000-0000-0000-000000000011';
const out={before,database:replay.database,status:'failed'};
try{
 await sql.unsafe('begin');
 await sql.unsafe(`insert into auth.users(id,email) values('${u}','member@example.invalid'),('${a}','admin@example.invalid');
 insert into public.clubs(id,name,slug) values('${c}','Override fixture','override-fixture');
 insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','member',true),('${c}','${a}','super_admin',true);
 insert into public.notification_preferences(club_id,profile_id,module_code,in_app_enabled,push_enabled)
 select '${c}'::uuid,p::uuid,m,false,false from unnest(array['${u}','${a}']) p cross join unnest(array['members','general','admin']) m;
 grant select,insert,update,delete on public.user_permission_overrides to authenticated;
 select set_config('request.jwt.claim.sub','${u}',true);
 set local role authenticated;`);
 assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,false);
 await sql.unsafe('savepoint attack');
 let code;
 try{await sql.unsafe(`insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','manageMembers',true)`);}catch(e){code=e.code;await sql.unsafe('rollback to savepoint attack');}
 if(before){assert.equal(code,undefined);assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,true);out.attack='real INSERT escalates member to manageMembers';}
 else{assert.equal(code,'42501');out.attack='real INSERT denied 42501';
 await sql.unsafe(`reset role;select set_config('request.jwt.claim.sub','${a}',true);set local role authenticated;
 insert into public.user_permission_overrides(club_id,profile_id,permission_key,allowed) values('${c}','${u}','manageMembers',true);
 update public.user_permission_overrides set allowed=false where club_id='${c}' and profile_id='${u}';`);
 assert.equal((await sql.unsafe(`select allowed from public.user_permission_overrides where club_id='${c}' and profile_id='${u}'`))[0].allowed,false);
 await sql.unsafe(`reset role;select set_config('request.jwt.claim.sub','${u}',true);set local role authenticated;`);
 assert.equal((await sql.unsafe(`select allowed from public.user_permission_overrides where club_id='${c}' and profile_id='${u}'`))[0].allowed,false);
 const changed=await sql.unsafe(`update public.user_permission_overrides set allowed=true where club_id='${c}' and profile_id='${u}' returning allowed`);assert.equal(changed.length,0);
 const removed=await sql.unsafe(`delete from public.user_permission_overrides where club_id='${c}' and profile_id='${u}' returning allowed`);assert.equal(removed.length,0);
 assert.equal((await sql.unsafe(`select public.has_club_permission('${c}','manageMembers') allowed`))[0].allowed,false);
 out.authorized='super_admin INSERT/UPDATE and member self SELECT passed; member UPDATE/DELETE affect zero rows';}
 out.status='passed';
}catch(e){out.error={code:e.code,message:e.message};throw e;}
finally{await sql.unsafe('rollback');await sql.end();writeFileSync(resolve(root,`docs/PHASE_AMBIGUOUS_OVERRIDE_${before?'BEFORE':'AFTER'}.json`),JSON.stringify(out,null,2)+'\n');}
console.log(JSON.stringify(out));
