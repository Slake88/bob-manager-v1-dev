// Loopback-only contract resolution and real writer regression; never accepts a remote URL.
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const before=process.argv.includes('--before');
const {database}=JSON.parse(readFileSync('docs/PHASE_BASELINE_REBUILD_RESULTS.json'));
assert.match(database,/^bob_clean_rebuild_\d+$/);
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const targets={document_ocr:['provider','model','raw_text','error_message','started_at','completed_at'],events:['budget','banner_path','event_mode_enabled']};
const results=[];
try {
 await sql.unsafe('begin');
 for(const [table,columns] of Object.entries(targets))for(const column of columns){
  await sql.unsafe('savepoint probe');let code='OK';
  try{await sql.unsafe(`update public.${table} set ${column}=${column} where false`);}catch(e){code=e.code;}
  await sql.unsafe('rollback to savepoint probe');
  assert.equal(code,before?'42703':'OK',`${table}.${column}`);
  results.push({table,column,code,scope:'Column resolution, not HTTP/Edge execution'});
 }
 if(!before){
  const c='00000000-0000-0000-0000-000000000001',u='00000000-0000-0000-0000-000000000010';
  await sql.unsafe(`insert into auth.users(id,email) values('${u}','consolidated@example.invalid');insert into public.clubs(id,name,slug) values('${c}','Consolidated','consolidated');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);set local role authenticated;`);
  const event=(await sql.unsafe(`insert into public.events(club_id,name,description,location,starts_at,ends_at,event_kind,status,capacity,budget,banner_path,event_mode_enabled,updated_at) values('${c}','Writer fixture',null,'Lisboa',now(),null,'general','published',10,42.50,null,false,now()) returning budget,banner_path,event_mode_enabled`))[0];
  assert.equal(Number(event.budget),42.5);assert.equal(event.event_mode_enabled,false);
  await sql.unsafe('reset role');
  await sql.unsafe(`insert into public.documents(id,club_id,name,scope,sensitive) values('00000000-0000-0000-0000-000000000040','${c}','OCR fixture','club',false)`);
  const job=(await sql.unsafe(`insert into public.document_ocr(club_id,document_id,status,created_by) values('${c}','00000000-0000-0000-0000-000000000040','pending','${u}') returning id`))[0];
  const claim=await sql.unsafe(`update public.document_ocr set status='processing',started_at=now(),completed_at=null,error_message=null,provider='fixture',model='fixture',updated_at=now() where id=$1 and status='pending' returning id`,[job.id]);assert.equal(claim.length,1);
  const done=(await sql.unsafe(`update public.document_ocr set status='ready',provider='fixture',model='fixture',raw_text='OCR fixture',confidence=0.9,error_message=null,completed_at=now(),updated_at=now() where id=$1 returning raw_text,completed_at`,[job.id]))[0];assert.equal(done.raw_text,'OCR fixture');assert.ok(done.completed_at);
  results.push({scope:'Real tables and enabled triggers; authenticated event payload; privileged OCR claim/completion SQL',status:'passed'});
 }
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();writeFileSync(`docs/PHASE_RECONCILIATION_CONSOLIDATED_WRITERS_${before?'BEFORE':'AFTER'}.json`,JSON.stringify({database,before,results},null,2)+'\n');}
console.log(JSON.stringify({before,passed:results.length}));
