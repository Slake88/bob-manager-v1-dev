-- Synthetic fixtures only. This script refuses every non-harness database.
begin;
do $$ begin
 if current_database() not like 'bob_phase2c6_%' or inet_server_addr() is distinct from inet '127.0.0.1' then raise exception 'Local harness required'; end if;
end $$;
create function pg_temp.id(k integer,n integer) returns uuid language sql immutable as $$ select (lpad(k::text,8,'0')||'-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid $$;
create function pg_temp.uid(n integer) returns uuid language sql immutable as $$ select pg_temp.id(1,n) $$;
insert into auth.users(id) select pg_temp.uid(n) from generate_series(1,5) n;
insert into profiles(id,full_name,email) select id,'Synthetic',id||'@example.invalid' from auth.users;
insert into clubs(id,name,slug) values (pg_temp.id(2,1),'Local A','local-a'),(pg_temp.id(2,2),'Local B','local-b');
select set_config('request.jwt.claim.sub',pg_temp.uid(1)::text,true);
insert into club_memberships(club_id,profile_id,active,access_role) values
 (pg_temp.id(2,1),pg_temp.uid(1),true,'member'),(pg_temp.id(2,2),pg_temp.uid(1),true,'member'),
 (pg_temp.id(2,1),pg_temp.uid(2),true,'member'),(pg_temp.id(2,1),pg_temp.uid(3),true,'member'),(pg_temp.id(2,1),pg_temp.uid(5),true,'member');
insert into user_permission_overrides(club_id,profile_id,permission_key,allowed)
 select pg_temp.id(2,1),pg_temp.uid(3),p,true from unnest(array['manageFees','approveExpenseRequests','manageEventOperations','approveEventProposals','manageEventParticipants']) p;
insert into members(id,club_id,profile_id,full_name,status,joined_at) values
 (pg_temp.id(3,1),pg_temp.id(2,1),pg_temp.uid(1),'Owner A','active','2026-01-01'),
 (pg_temp.id(3,2),pg_temp.id(2,1),pg_temp.uid(2),'Third party','active','2026-01-01'),
 (pg_temp.id(3,3),pg_temp.id(2,1),pg_temp.uid(4),'No membership','active','2026-01-01'),
 (pg_temp.id(3,4),pg_temp.id(2,2),pg_temp.uid(1),'Owner B','active','2026-01-01');
insert into financial_requests(id,club_id,member_id,request_type,category,amount,description,status) values
 (pg_temp.id(4,1),pg_temp.id(2,1),pg_temp.id(3,1),'reimbursement','reimbursement',20,'Receipt','draft'),
 (pg_temp.id(4,2),pg_temp.id(2,1),pg_temp.id(3,1),'charge','fee',20,'Proof','awaiting_payment'),
 (pg_temp.id(4,3),pg_temp.id(2,2),pg_temp.id(3,4),'reimbursement','reimbursement',20,'Club B','draft'),
 (pg_temp.id(4,4),pg_temp.id(2,1),pg_temp.id(3,3),'reimbursement','reimbursement',20,'No membership','draft');
insert into financial_request_attachments(club_id,request_id,kind,storage_path,original_file_name,file_size)
 select club_id,id,case when request_type='charge' then 'member_payment_proof' else 'receipt' end,club_id||'/'||id||'/proof.pdf','proof.pdf',10 from financial_requests;
insert into fee_credits(id,club_id,member_id,amount,entry_type) values (pg_temp.id(13,1),pg_temp.id(2,1),pg_temp.id(3,1),25,'manual_adjustment');
insert into reported_payments(id,club_id,member_id,amount,paid_on,payment_method,proof_path,proof_name) values
 (pg_temp.id(5,1),pg_temp.id(2,1),pg_temp.id(3,1),20,current_date,'cash',pg_temp.id(2,1)||'/'||pg_temp.uid(1)||'/proof.pdf','proof.pdf');
insert into events(id,club_id,name,status) values (pg_temp.id(6,1),pg_temp.id(2,1),'Synthetic event','published');
insert into event_tasks(id,club_id,event_id,title) values (pg_temp.id(7,1),pg_temp.id(2,1),pg_temp.id(6,1),'Task');
insert into event_volunteers(club_id,event_id,member_id,function_name) values (pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(3,1),'Support');
insert into event_task_assignees(id,club_id,event_id,task_id,member_id) values (pg_temp.id(8,1),pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(7,1),pg_temp.id(3,1));
insert into event_shifts(id,club_id,event_id,name,starts_at,ends_at) values (pg_temp.id(9,1),pg_temp.id(2,1),pg_temp.id(6,1),'Shift',now(),now()+interval '1 hour');
insert into event_shift_members(id,club_id,event_id,shift_id,member_id) values (pg_temp.id(10,1),pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(9,1),pg_temp.id(3,1));
insert into event_proposals(id,club_id,proposed_by,name) values (pg_temp.id(11,1),pg_temp.id(2,1),pg_temp.uid(1),'Proposal');
insert into event_guests(id,club_id,event_id,host_member_id,name) values (pg_temp.id(12,1),pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(3,1),'Guest');
insert into event_registrations(id,event_id,member_id) values (pg_temp.id(20,1),pg_temp.id(6,1),pg_temp.id(3,1));
insert into event_registration_guests(id,registration_id,guest_name) values (pg_temp.id(21,1),pg_temp.id(20,1),'Companion');
insert into event_volunteers(club_id,event_id,guest_id,function_name) values (pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(21,1),'Guest support');
insert into event_task_assignees(id,club_id,event_id,task_id,guest_id) values (pg_temp.id(8,2),pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(7,1),pg_temp.id(21,1));
insert into event_shift_members(id,club_id,event_id,shift_id,guest_id) values (pg_temp.id(10,2),pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(9,1),pg_temp.id(21,1));
insert into fee_obligations(id,club_id,member_id,reference_year,reference_month,amount) values (pg_temp.id(14,1),pg_temp.id(2,1),pg_temp.id(3,1),2026,1,25);
insert into treasury_accounts(id,club_id,name,account_type) values (pg_temp.id(15,1),pg_temp.id(2,1),'Fixture cash','cash');
insert into treasury_transactions(id,club_id,kind,account_id,transaction_date,description,amount) values (pg_temp.id(16,1),pg_temp.id(2,1),'income',pg_temp.id(15,1),current_date,'Synthetic fee',1);
insert into fee_payments(id,club_id,member_id,transaction_id,amount) values (pg_temp.id(17,1),pg_temp.id(2,1),pg_temp.id(3,1),pg_temp.id(16,1),1);
insert into fee_payment_allocations(club_id,payment_id,obligation_id,amount) values (pg_temp.id(2,1),pg_temp.id(17,1),pg_temp.id(14,1),1);
insert into weekly_dinners(id,club_id,dinner_date) values (pg_temp.id(18,1),pg_temp.id(2,1),'2099-01-08');
insert into weekly_officer_swap_requests(id,club_id,dinner_id,requester_member_id,requested_member_id) values
 (pg_temp.id(19,1),pg_temp.id(2,1),pg_temp.id(18,1),pg_temp.id(3,1),pg_temp.id(3,2)),
 (pg_temp.id(19,2),pg_temp.id(2,1),pg_temp.id(18,1),pg_temp.id(3,2),pg_temp.id(3,1));
insert into fee_exemptions(club_id,member_id,obligation_id,amount,reason) values (pg_temp.id(2,1),pg_temp.id(3,1),pg_temp.id(14,1),1,'Synthetic');
insert into fee_adjustments(club_id,member_id,obligation_id,amount,reason) values (pg_temp.id(2,1),pg_temp.id(3,1),pg_temp.id(14,1),1,'Synthetic');
insert into storage.objects(bucket_id,name) select 'financial-documents',storage_path from financial_request_attachments;
insert into storage.objects(bucket_id,name) select 'fee-payment-proofs',proof_path from reported_payments;
update club_memberships set active=false where club_id=pg_temp.id(2,2);
-- BEGIN ASSERTIONS
create function pg_temp.assert(ok boolean,label text) returns void language plpgsql as $$ begin if ok is not true then raise exception 'Assertion: %',label; end if; end $$;
create function pg_temp.denied(stmt text,code text default 'P0001') returns void language plpgsql as $$ begin
 begin execute stmt; exception when others then if sqlstate=code then return; else raise; end if; end;
 raise exception 'Unexpected success: %',stmt;
end $$;
-- Snapshot all application rows, including audit and notification effects, as privileged test runner.
create function pg_temp.snapshot() returns jsonb language plpgsql as $$ declare t record; v jsonb; result jsonb:='{}'; begin
 for t in select tablename from pg_tables where schemaname='public' order by tablename loop
 execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from public.%I t',t.tablename) into v;
 result:=result||jsonb_build_object(t.tablename,v); end loop;
 select coalesce(jsonb_agg(to_jsonb(o) order by name),'[]') into v from storage.objects o;
 return result||jsonb_build_object('storage.objects',v); end $$;
-- Owner: read helpers and all direct paths work in A; same identity in inactive B fails.
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1))=pg_temp.id(3,1),'active financial identity');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1))=pg_temp.id(3,1),'active weekly identity');
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,2)) is null,'inactive B identity');
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,3)),'club isolation');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1))=25,'active credit balance');
select pg_temp.assert((select count(*)=2 from financial_requests),'owner financial RLS');
select pg_temp.assert((select count(*)=2 from financial_request_attachments),'owner attachment RLS');
select pg_temp.assert((select count(*)=3 from storage.objects),'owner Storage RLS');
select pg_temp.assert((select count(*)=1 from fee_credits),'credit RLS');
select pg_temp.assert((select count(*)=1 from fee_payment_allocations),'allocation RLS');
select pg_temp.assert((select count(*)=2 from weekly_officer_swap_requests),'swap RLS');
select pg_temp.assert((select count(*)=1 from fee_exemptions),'exemptions RLS');
select pg_temp.assert((select count(*)=1 from fee_adjustments),'adjustments RLS');
select pg_temp.assert((select count(*)=1 from reported_payments),'reported RLS');
select pg_temp.assert((select count(*)=1 from event_proposals),'proposal RLS');
reset role;
-- Rejected mutation matrix. Savepoint-based exception blocks roll back any incidental write.
create function pg_temp.reject_mutations() returns void language plpgsql as $$ begin
 perform pg_temp.denied('select respond_weekly_officer_swap_v1(pg_temp.id(2,1),pg_temp.id(19,2),true,null)');
 perform pg_temp.denied('select cancel_weekly_officer_swap_v1(pg_temp.id(2,1),pg_temp.id(19,1))');
 perform pg_temp.denied('select cancel_reported_fee_payment_v1(pg_temp.id(2,1),pg_temp.id(5,1))');
 perform pg_temp.denied('select acknowledge_event_task_v1(pg_temp.id(8,1),true)');
 perform pg_temp.denied('select set_event_shift_member_status_v1(pg_temp.id(10,1),''present'')');
 perform pg_temp.denied('select withdraw_event_proposal_v1(pg_temp.id(11,1))');
 perform pg_temp.denied('select update_reimbursement_draft_v1(pg_temp.id(2,1),pg_temp.id(4,1),30,''Changed'')');
 perform pg_temp.denied('select submit_reimbursement_v1(pg_temp.id(2,1),pg_temp.id(4,1))');
 perform pg_temp.denied('select submit_charge_proof_v1(pg_temp.id(2,1),pg_temp.id(4,2))');
 perform pg_temp.denied('select add_financial_attachment_v1(pg_temp.id(2,1),pg_temp.id(4,1),''receipt'',pg_temp.id(2,1)||''/''||pg_temp.id(4,1)||''/new.pdf'',''new.pdf'',''application/pdf'',10)');
 perform pg_temp.denied('insert into storage.objects(bucket_id,name) values (''financial-documents'',pg_temp.id(2,1)||''/''||pg_temp.id(4,1)||''/new.pdf'')','42501');
 perform pg_temp.denied('insert into storage.objects(bucket_id,name) values (''fee-payment-proofs'',pg_temp.id(2,1)||''/''||auth.uid()||''/new.pdf'')','42501');
 perform pg_temp.denied('insert into event_guests(club_id,event_id,host_member_id,name) values (pg_temp.id(2,1),pg_temp.id(6,1),pg_temp.id(3,1),''Denied guest'')','P0001');
end $$;
update club_memberships set active=false where profile_id=pg_temp.uid(1);
create temp table unchanged as select pg_temp.snapshot() data;
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'inactive financial identity');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1)) is null,'inactive weekly identity');
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,1)),'inactive request helper');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1)) is null,'inactive balance');
select pg_temp.assert((select count(*)=0 from financial_requests),'inactive financial RLS');
select pg_temp.assert((select count(*)=0 from financial_request_attachments),'inactive attachment RLS');
select pg_temp.assert((select count(*)=0 from storage.objects),'inactive Storage RLS');
select pg_temp.assert((select count(*)=0 from fee_credits),'inactive credit RLS');
select pg_temp.assert((select count(*)=0 from fee_payment_allocations),'inactive allocation RLS');
select pg_temp.assert((select count(*)=0 from weekly_officer_swap_requests),'inactive swap RLS');
select pg_temp.assert((select count(*)=0 from reported_payments),'inactive report RLS');
select pg_temp.assert((select count(*)=0 from fee_exemptions),'inactive exemptions RLS');
select pg_temp.assert((select count(*)=0 from fee_adjustments),'inactive adjustments RLS');
select pg_temp.assert((select count(*)=0 from event_proposals),'inactive proposals RLS');
select pg_temp.reject_mutations();
delete from storage.objects;
update storage.objects set metadata='{"denied":true}'::jsonb;
update event_guests set name='Changed';
reset role;
select pg_temp.assert((select data=pg_temp.snapshot() from unchanged),'rejection leaves all rows unchanged');
-- Same historical owner, with the membership row removed entirely.
savepoint no_membership;
delete from club_memberships where profile_id=pg_temp.uid(1) and club_id=pg_temp.id(2,1);
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'owner without membership');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1)) is null,'weekly owner without membership');
select pg_temp.reject_mutations();
reset role;
rollback to savepoint no_membership;
release savepoint no_membership;
-- Missing identity and linked profile without membership.
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'missing identity');
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,1)),'missing identity access');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1)) is null,'missing weekly identity');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1)) is null,'missing identity balance');
select pg_temp.reject_mutations();
reset role;
select set_config('request.jwt.claim.sub',pg_temp.uid(4)::text,true);
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'linked no membership');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1)) is null,'weekly linked no membership');
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,4)),'linked no membership request');
select pg_temp.assert((select count(*)=0 from financial_requests),'linked no membership RLS');
select pg_temp.reject_mutations();
reset role;
select set_config('request.jwt.claim.sub',pg_temp.uid(2)::text,true);
set local role authenticated;
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,1)),'third party helper');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1)) is null,'third party balance');
-- Own uploads allowed for this active third party, so test only RPCs here.
select pg_temp.denied('select cancel_reported_fee_payment_v1(pg_temp.id(2,1),pg_temp.id(5,1))');
select pg_temp.denied('select acknowledge_event_task_v1(pg_temp.id(8,1),true)');
select pg_temp.denied('select set_event_shift_member_status_v1(pg_temp.id(10,1),''present'')');
select pg_temp.denied('select withdraw_event_proposal_v1(pg_temp.id(11,1))');
reset role;
select pg_temp.assert((select data=pg_temp.snapshot() from unchanged),'all negative identities leave rows unchanged');
-- Active owner RPC success. Restore active A only; inactive B remains denied.
update club_memberships set active=true where profile_id=pg_temp.uid(1) and club_id=pg_temp.id(2,1);
select set_config('request.jwt.claim.sub',pg_temp.uid(1)::text,true);
set local role authenticated;
select pg_temp.denied('select acknowledge_event_task_v1(pg_temp.id(8,2),true)');
select pg_temp.denied('select set_event_shift_member_status_v1(pg_temp.id(10,2),''present'')');
insert into storage.objects(bucket_id,name) values ('financial-documents',pg_temp.id(2,1)||'/'||pg_temp.id(4,1)||'/transient.pdf');
delete from storage.objects where name like '%/transient.pdf';
insert into storage.objects(bucket_id,name) values ('fee-payment-proofs',pg_temp.id(2,1)||'/'||pg_temp.uid(1)||'/transient.pdf');
delete from storage.objects where name like '%/transient.pdf';
update event_guests set name='Owner changed' where id=pg_temp.id(12,1);
select respond_weekly_officer_swap_v1(pg_temp.id(2,1),pg_temp.id(19,2),true,null);
select cancel_weekly_officer_swap_v1(pg_temp.id(2,1),pg_temp.id(19,1));
select update_reimbursement_draft_v1(pg_temp.id(2,1),pg_temp.id(4,1),30,'Updated');
select submit_reimbursement_v1(pg_temp.id(2,1),pg_temp.id(4,1));
select submit_charge_proof_v1(pg_temp.id(2,1),pg_temp.id(4,2));
select acknowledge_event_task_v1(pg_temp.id(8,1),true);
select set_event_shift_member_status_v1(pg_temp.id(10,1),'present');
select cancel_reported_fee_payment_v1(pg_temp.id(2,1),pg_temp.id(5,1));
select withdraw_event_proposal_v1(pg_temp.id(11,1));
reset role;
select pg_temp.assert((select status='done' from event_tasks where id=pg_temp.id(7,1)),'owner task write');
select pg_temp.assert((select status='present' from event_shift_members where id=pg_temp.id(10,1)),'owner shift write');
select pg_temp.assert((select status='cancelled' from reported_payments where id=pg_temp.id(5,1)),'owner cancel write');
select pg_temp.assert((select status='withdrawn' from event_proposals where id=pg_temp.id(11,1)),'owner withdrawal write');
-- Authorized manager has no linked member; access remains permission based.
update reported_payments set status='pending';
update financial_requests set status='draft' where id=pg_temp.id(4,1);
select set_config('request.jwt.claim.sub',pg_temp.uid(3)::text,true);
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'manager no personal member');
select pg_temp.assert(financial_request_access_v1(pg_temp.id(4,1)),'manager financial helper');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1))=25,'manager balance');
select pg_temp.assert((select count(*)=3 from financial_requests),'manager RLS');
select pg_temp.assert((select count(*)=4 from storage.objects),'manager Storage RLS');
select cancel_reported_fee_payment_v1(pg_temp.id(2,1),pg_temp.id(5,1));
select acknowledge_event_task_v1(pg_temp.id(8,1),false);
select acknowledge_event_task_v1(pg_temp.id(8,2),false);
select set_event_shift_member_status_v1(pg_temp.id(10,2),'confirmed');
select set_event_shift_member_status_v1(pg_temp.id(10,1),'confirmed');
select update_reimbursement_draft_v1(pg_temp.id(2,1),pg_temp.id(4,1),35,'Manager updated');
-- Withdrawal was always author-only, even for managers.
select pg_temp.denied('select withdraw_event_proposal_v1(pg_temp.id(11,1))');
reset role;
-- Permission overrides cannot revive an inactive manager.
update club_memberships set active=false where profile_id=pg_temp.uid(3);
set local role authenticated;
select pg_temp.assert(not financial_request_access_v1(pg_temp.id(4,1)),'inactive manager denied');
select pg_temp.assert(fee_credit_balance_v1(pg_temp.id(2,1),pg_temp.id(3,1)) is null,'inactive manager balance denied');
select pg_temp.assert((select count(*)=0 from financial_requests),'inactive manager RLS');
select pg_temp.denied('select acknowledge_event_task_v1(pg_temp.id(8,1),false)');
select pg_temp.denied('select set_event_shift_member_status_v1(pg_temp.id(10,1),''present'')');
reset role;
-- Active membership without a linked member gives no personal identity.
select set_config('request.jwt.claim.sub',pg_temp.uid(5)::text,true);
set local role authenticated;
select pg_temp.assert(current_financial_member_v1(pg_temp.id(2,1)) is null,'active no linked financial member');
select pg_temp.assert(current_weekly_officer_member_v1(pg_temp.id(2,1)) is null,'active no linked weekly member');
reset role;
-- Exact signatures, hardened paths and effective execution privileges.
do $$ declare sig text; begin
 foreach sig in array array['current_financial_member_v1(uuid)','financial_request_access_v1(uuid)','current_weekly_officer_member_v1(uuid)','fee_credit_balance_v1(uuid,uuid)','cancel_reported_fee_payment_v1(uuid,uuid)','acknowledge_event_task_v1(uuid,boolean)','set_event_shift_member_status_v1(uuid,text)','withdraw_event_proposal_v1(uuid)'] loop
 perform pg_temp.assert(has_function_privilege('authenticated','public.'||sig,'execute'),'authenticated ACL '||sig);
 perform pg_temp.assert(not has_function_privilege('anon','public.'||sig,'execute'),'anon ACL '||sig);
 perform pg_temp.assert(not exists(select 1 from pg_proc p,aclexplode(p.proacl) a where p.oid=('public.'||sig)::regprocedure and a.grantee=0 and a.privilege_type='EXECUTE'),'PUBLIC ACL '||sig);
 perform pg_temp.assert((select proconfig @> array['search_path=pg_catalog, public, pg_temp'] from pg_proc where oid=('public.'||sig)::regprocedure),'search_path '||sig);
 end loop;
end $$;
rollback;
