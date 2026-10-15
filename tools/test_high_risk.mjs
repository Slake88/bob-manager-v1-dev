import {sanitizeCatalog} from './sanitize_catalog.mjs';
// Fixed loopback only. All synthetic data and trigger changes roll back.
import fs from 'node:fs';import assert from 'node:assert/strict';import {resolve} from 'node:path';import {pathToFileURL} from 'node:url';
const read=p=>JSON.parse(fs.readFileSync('docs/'+p));
const {database}=read('PHASE_BASELINE_REBUILD_RESULTS.json');assert.match(database,/^bob_clean_rebuild_\d+$/);
const pg=(await import(pathToFileURL(resolve(process.argv[2])).href)).default;
const sql=pg({host:'127.0.0.1',port:55440,user:'postgres',database,max:1,prepare:false,onnotice:()=>{}});
const before=process.argv.includes('--before'),results=[];
const inv=read('PHASE_HIGH_RISK_INVENTORY.json'),edits=read('PHASE_HIGH_RISK_EDITS.json');
const uid=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');const c=uid(1),u=uid(10),m=uid(20),ev=uid(30),d=uid(40);
async function insert(table,data){const keys=Object.keys(data);return (await sql.unsafe(`insert into public.${table} (${keys.join(',')}) values (${keys.map((_,i)=>'$'+(i+1)).join(',')}) returning *`,Object.values(data)))[0];}
async function probe(name,fn){await sql.unsafe('savepoint probe');try{await fn();results.push({name,status:'passed'});}catch(e){results.push({name,status:'failed',code:e.code,message:e.message});}await sql.unsafe('rollback to savepoint probe');}
async function rejected(name,query,args,code){await sql.unsafe('savepoint negative');let error;try{await sql.unsafe(query,args);}catch(e){error=e;}await sql.unsafe('rollback to savepoint negative');assert.equal(error?.code,code,name);results.push({name,status:'passed',expected:code});}
try{
 await sql.unsafe('begin');
 for(const x of inv.items.filter(x=>x.kind==='column_missing_local'&&edits.some(e=>e.id===x.id))){await probe('resolve '+x.id,async()=>{await sql.unsafe(`update public.${x.table} set ${x.name}=${x.name} where false`);});}
 if(before){
  await sql.unsafe(`insert into auth.users(id,email) values('${u}','highrisk@example.invalid');insert into public.clubs(id,name,slug) values('${c}','High risk','high-risk');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);`);
  await probe('real submit_event_proposal_v1 before',async()=>{await sql.unsafe(`select public.submit_event_proposal_v1('${c}','Proposta','Desc','Lisboa',now(),now()+interval '1 day','ride')`);});
 }else{
  const q=fs.readFileSync('docs/PHASE_STRUCTURAL_DRIFT_PREFLIGHT.sql','utf8').replace(/^begin transaction read only;\s*/i,'').replace(/rollback;\s*$/i,'');
  const snapshot=(await sql.unsafe(q))[0].snapshot;
  fs.writeFileSync('docs/PHASE_HIGH_RISK_LOCAL_SNAPSHOT.json',JSON.stringify(sanitizeCatalog(snapshot),null,2)+'\n');
  for(const e of edits){const x=inv.items.find(x=>x.id===e.id),t=snapshot.relations.find(t=>t.name===x.table);let actual;if(x.kind==='enum')actual=snapshot.enums.find(a=>a.name===x.table);else if(x.kind==='trigger')actual=t.triggers.find(a=>a.name===x.name);else if(x.kind.startsWith('column_'))actual=t.columns.find(a=>a.name===x.name);else if(x.kind==='constraint')actual=t.constraints.find(a=>a.name===x.name);else if(x.kind==='index')actual=t.indexes.find(a=>a.name===x.name);assert.deepEqual(actual??null,x.production,x.id);}
  results.push({name:'all '+edits.length+' targeted catalog contracts match captured production',status:'passed'});
  await sql.unsafe(`insert into auth.users(id,email) values('${u}','highrisk@example.invalid');insert into public.clubs(id,name,slug) values('${c}','High risk','high-risk');insert into public.club_memberships(club_id,profile_id,access_role,active) values('${c}','${u}','super_admin',true);select set_config('request.jwt.claim.sub','${u}',true);`);
  await insert('members',{id:m,club_id:c,full_name:'High risk',status:'active'});
  await insert('events',{id:ev,club_id:c,name:'High risk',status:'published',event_kind:'rock_ride_in'});
  await insert('event_volunteers',{club_id:c,event_id:ev,member_id:m,function_name:'Fixture'});
  await insert('documents',{id:d,club_id:c,name:'High risk',scope:'club',sensitive:false});
  const tasks=uid(50),shift=uid(51),book=uid(52),product=uid(53),motor=uid(54),maint=uid(55),loc=uid(56);
  await insert('inventory_locations',{id:loc,club_id:c,name:'Armazém',active:true,location_type:'storage'});
  await insert('inventory_locations',{club_id:c,name:'Club House',active:true,location_type:'clubhouse'});
  await insert('products',{id:product,club_id:c,name:'Patch',active:true});
  await insert('member_motorcycles',{id:motor,club_id:c,member_id:m,brand:'Fixture',model:'Fixture'});
  const pos=uid(57);await insert('club_positions',{id:pos,club_id:c,code:'HR',name:'High risk'});
  const fixtures={
   activity_feed:{club_id:c,actor_id:u,activity_type:'fixture',title:'High risk'},
   audit_log:{club_id:c,actor_id:u,entity_type:'fixture',action:'fixture'},
   club_positions:{club_id:c,code:'HR2',name:'High risk 2'},
   cost_centers:{club_id:c,name:'High risk'},
   member_positions:{club_id:c,member_id:m,position_id:pos,starts_at:'2026-10-15'},
   fee_plans:{club_id:c,name:'High risk',amount:10,frequency:'monthly'},
   product_variants:{club_id:c,product_id:product,name:'High risk'},
   announcements:{club_id:c,title:'Aviso',body:'Texto'},
   event_proposals:{club_id:c,proposed_by:u,name:'Proposta'},
   event_guests:{club_id:c,event_id:ev,host_member_id:m,name:'Convidado'},
   event_routes:{club_id:c,event_id:ev,name:'Roadbook',distance_km:42.5},
   event_octane_configs:{club_id:c,event_id:ev},
   event_tasks:{id:tasks,club_id:c,event_id:ev,title:'Tarefa'},
   event_task_assignees:{club_id:c,event_id:ev,task_id:tasks,member_id:m},
   event_shifts:{id:shift,club_id:c,event_id:ev,name:'Turno',starts_at:'2026-10-15T10:00:00Z',ends_at:'2026-10-15T11:00:00Z'},
   event_shift_members:{club_id:c,event_id:ev,shift_id:shift,member_id:m},
   event_program:{club_id:c,event_id:ev,title:'Programa',sequence_no:1},
   event_incidents:{club_id:c,event_id:ev,title:'Incidente'},
   document_approvals:{club_id:c,document_id:d,requested_by:u},
   document_ocr:{club_id:c,document_id:d,created_by:u,confidence:0.9},
   document_access_log:{club_id:c,document_id:d,profile_id:u,action:'view'},
   annual_books:{id:book,club_id:c,year:2026,title:'Anuário'},
   annual_book_items:{club_id:c,annual_book_id:book,sequence_no:1,title:'Página'},
   maintenance_records:{id:maint,club_id:c,member_id:m,motorcycle_id:motor,service_type:'inspection',odometer_km:1000,cost:10},
   maintenance_attachments:{club_id:c,member_id:m,maintenance_id:maint,storage_path:'fixture/high-risk.pdf',original_file_name:'fixture.pdf',file_size:12},
   member_patch_awards:{club_id:c,member_id:m,product_id:product,patch_name:'Patch'},
   member_status_history:{club_id:c,member_id:m,new_status:'active',notes:'Fixture'},
   member_timeline:{club_id:c,member_id:m,event_type:'fixture',title:'Fixture'},
   stock_lots:{club_id:c,product_id:product,location_id:loc,lot_code:'HR1',initial_quantity:10,quantity:10},
   stock_reservations:{club_id:c,product_id:product,location_id:loc,member_id:m,quantity:1}
  };
  for(const [table,data] of Object.entries(fixtures)){
   await sql.unsafe('savepoint fixture');let row;
   try{row=await insert(table,data);results.push({name:table+' positive writer payload with all triggers active',status:'passed'});}catch(e){await sql.unsafe('rollback to savepoint fixture');results.push({name:table+' positive writer payload with all triggers active',status:'failed',code:e.code,message:e.message});continue;}
   // Isolate declarative rejection from business guards/audit rewrites, keeping fixture writer above real.
   await sql.unsafe('savepoint declarative');await sql.unsafe(`alter table public.${table} disable trigger user`);
   for(const x of inv.items.filter(x=>x.table===table&&edits.some(e=>e.id===x.id)&&x.kind.startsWith('column_')&&x.production.notnull))await rejected(x.id+' rejects explicit NULL',`update public.${table} set ${x.name}=null where id=$1`,[row.id],'23502');
   for(const x of inv.items.filter(x=>x.table===table&&edits.some(e=>e.id===x.id)&&x.kind==='constraint')){
    if(!x.production)continue;const def=x.production.definition;
    if(x.production.type==='f'){const col=def.match(/^FOREIGN KEY \((\w+)\)/)[1];await rejected(x.id+' rejects orphan',`update public.${table} set ${col}=$1 where id=$2`,[uid(9999),row.id],'23503');}
    if(x.production.type==='u'){
     const keys=Object.keys(row).filter(k=>k!=='id');await rejected(x.id+' rejects duplicate',`insert into public.${table} (${keys.join(',')}) select ${keys.join(',')} from public.${table} where id=$1`,[row.id],'23505');
    }
    if(x.production.type==='c'){
     let assignment;const col=def.match(/\b(\w+) = ANY/)?.[1];
     if(col)assignment=col+"='invalid'";
     else if(def.includes('expires_at > published_at'))assignment='expires_at=published_at';
     else if(def.includes('ends_at >= starts_at'))assignment="starts_at='2026-10-16',ends_at='2026-10-15'";
     else if(def.includes('year >= 2000'))assignment='year=1999';
     else {const col=def.match(/\b(\w+) (?:>=|>|<=)/)?.[1];assert.ok(col,x.id);assignment=col+'=-1';}
     await rejected(x.id+' rejects invalid domain',`update public.${table} set ${assignment} where id=$1`,[row.id],'23514');
    }
   }
   await sql.unsafe('rollback to savepoint declarative');
  }
  await probe('real submit_event_proposal_v1 authenticated',async()=>{await sql.unsafe('set local role authenticated');const a=await sql.unsafe(`select public.submit_event_proposal_v1('${c}','Proposta RPC','Desc','Lisboa',now(),now()+interval '1 day','ride') id`);assert.ok(a[0].id);});
  await probe('Octane defaults and invalid price',async()=>{const row=(await sql.unsafe('select * from public.event_octane_configs where event_id=$1',[ev]))[0];assert.equal(Number(row.unit_price),1.5);assert.equal(row.ten_card_units,10);assert.equal(row.ten_card_bonus,1);await rejected('negative Octane price',`update public.event_octane_configs set unit_price=-1 where id=$1`,[row.id],'23514');});
  await probe('Documents current form sends scalar tags and links',async()=>{await sql.unsafe("update public.documents set tags='regulamento, clube',linked_entity_type='member',linked_entity_id=$1 where id=$2",[m,d]);assert.equal((await sql.unsafe('select tags from public.documents where id=$1',[d]))[0].tags,'regulamento, clube');});
  for(const e of edits.filter(e=>e.id.startsWith('enum:'))){const type=e.id.slice(5);await probe(e.id+' literals/order/casts',async()=>{const values=(await sql.unsafe(`select unnest(enum_range(null::public.${type}))::text value`)).map(x=>x.value);assert.deepEqual(values,e.production.values);await rejected(e.id+' rejects invalid',`select 'invalid'::public.${type}`,[],'22P02');});}
  for(const table of ['clubs','profiles','members','events'])await probe(table+' timestamp trigger and ordering',async()=>{const id={clubs:c,profiles:u,members:m,events:ev}[table];await sql.unsafe(`update public.${table} set updated_at='2000-01-01' where id=$1`,[id]);assert.ok(new Date((await sql.unsafe(`select updated_at from public.${table} where id=$1`,[id]))[0].updated_at)>new Date('2026-01-01'));const triggers=await sql.unsafe('select tgname,pg_get_triggerdef(oid) definition from pg_trigger where tgrelid=$1::regclass and not tgisinternal order by tgname',['public.'+table]);results.push({name:table+' trigger order',status:'passed',triggers});});
  await insert('document_versions',{club_id:c,document_id:d,version_no:1,version_label:'1.0',storage_path:'high-risk/1.pdf',file_size:1});
  await insert('document_links',{club_id:c,document_id:d,linked_entity_type:'member',linked_entity_id:m});
  const effects=[];
  for(const x of inv.items.filter(x=>x.kind==='trigger'&&!x.production&&!edits.some(e=>e.id===x.id))){
   const row=(await sql.unsafe(`select id from public.${x.table} limit 1`))[0];assert.ok(row,x.id+' fixture');
   const modes=[];
   for(const disabled of [false,true]){
    await sql.unsafe('savepoint effect');if(!disabled)await sql.unsafe(x.rebuild.definition); else assert.equal((await sql.unsafe('select count(*) n from pg_trigger where tgrelid=$1::regclass and tgname=$2',['public.'+x.table,x.name]))[0].n,'0');
    const count=async()=>Number((await sql.unsafe('select count(*) n from public.audit_log where entity_type=$1 and entity_id=$2',[x.table,String(row.id)]))[0].n);
    const n=await count();const changed=(await sql.unsafe(`update public.${x.table} set updated_at='2000-01-01' where id=$1 returning created_at,updated_at,created_by,updated_by`,[row.id]))[0];
    modes.push({disabled,audit_rows_added:(await count())-n,returned:changed});await sql.unsafe('rollback to savepoint effect');
   }
   effects.push({id:x.id,definition:x.rebuild.definition,function:x.rebuild.function,body:x.rebuild.body,config:x.rebuild.config,security_definer:x.rebuild.security_definer,modes,decision:'Retain global audit/stamping extension, or match captured production absence? Approved snapshot scope: absent in final catalog; enabled mode recreates the old trigger in a rolled-back savepoint.'});
  }
  fs.writeFileSync('docs/PHASE_HIGH_RISK_TRIGGER_EFFECTS.json',JSON.stringify({database,effects},null,2)+'\n');
  for(const table of ['maintenance_records','maintenance_attachments','member_patch_awards'])await probe(table+' exactly one canonical audit capture after deduplication',async()=>{const row=(await sql.unsafe(`select id from public.${table} limit 1`))[0];const count=async()=>Number((await sql.unsafe('select count(*) n from public.audit_log where entity_type=$1 and entity_id=$2',[table,row.id]))[0].n);const n=await count();await sql.unsafe(`update public.${table} set updated_at='2000-01-01' where id=$1`,[row.id]);assert.equal((await count())-n,1);assert.ok(new Date((await sql.unsafe(`select updated_at from public.${table} where id=$1`,[row.id]))[0].updated_at)>new Date('2026-01-01'));});
  await probe('member number uniqueness and NULL semantics',async()=>{await sql.unsafe('update public.members set member_number=42 where id=$1',[m]);await rejected('duplicate nonnull member number',`insert into public.members(club_id,full_name,member_number,status) values($1,'Duplicate',42,'active')`,[c],'23505');await insert('members',{club_id:c,full_name:'Null 1',status:'active'});await insert('members',{club_id:c,full_name:'Null 2',status:'active'});});
  await probe('stock ledger retention after variant delete',async()=>{const v=await insert('product_variants',{club_id:c,product_id:product,name:'Cascade fixture'});const move=await insert('stock_movements',{club_id:c,product_id:product,product_variant_id:v.id,kind:'adjustment',quantity:1,to_location_id:loc});await sql.unsafe('delete from public.product_variants where id=$1',[v.id]);assert.equal((await sql.unsafe('select id from public.stock_movements where id=$1',[move.id])).length,1);results.push({name:'legacy-linked movement survives variant delete',status:'passed',decision:'Approved removal of legacy FK absent from production: movement and legacy UUID survive variant deletion.'});});
  await probe('canonical variant FK preserves movement with SET NULL',async()=>{const v=await insert('product_variants',{club_id:c,product_id:product,name:'Canonical retention fixture'});const move=await insert('stock_movements',{club_id:c,product_id:product,variant_id:v.id,kind:'adjustment',quantity:1,to_location_id:loc});await sql.unsafe('delete from public.product_variants where id=$1',[v.id]);const rows=await sql.unsafe('select variant_id from public.stock_movements where id=$1',[move.id]);assert.equal(rows.length,1);assert.equal(rows[0].variant_id,null);});
 }
}finally{await sql.unsafe('rollback').catch(()=>{});await sql.end();fs.writeFileSync('docs/PHASE_HIGH_RISK_'+(before?'BEFORE':'AFTER')+'.json',JSON.stringify({database,before,results,passed:results.filter(x=>x.status==='passed').length,failed:results.filter(x=>x.status==='failed').length},null,2)+'\n');}
console.log(JSON.stringify({before,passed:results.filter(x=>x.status==='passed').length,failed:results.filter(x=>x.status==='failed')}));if(!before&&results.some(x=>x.status==='failed'))process.exitCode=1;
