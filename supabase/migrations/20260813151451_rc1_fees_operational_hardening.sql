insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('fee-payment-proofs','fee-payment-proofs',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Integridade cruzada por club_id.
drop trigger if exists trg_fee_operational_guard_v1 on public.fee_payments;
create trigger trg_fee_operational_guard_v1 before insert or update on public.fee_payments for each row execute function public.fee_operational_reference_guard_v1();
drop trigger if exists trg_fee_operational_guard_v1 on public.fee_payment_allocations;
create trigger trg_fee_operational_guard_v1 before insert or update on public.fee_payment_allocations for each row execute function public.fee_operational_reference_guard_v1();
drop trigger if exists trg_fee_operational_guard_v1 on public.fee_credits;
create trigger trg_fee_operational_guard_v1 before insert or update on public.fee_credits for each row execute function public.fee_operational_reference_guard_v1();
drop trigger if exists trg_fee_operational_guard_v1 on public.fee_exemptions;
create trigger trg_fee_operational_guard_v1 before insert or update on public.fee_exemptions for each row execute function public.fee_operational_reference_guard_v1();
drop trigger if exists trg_fee_operational_guard_v1 on public.fee_adjustments;
create trigger trg_fee_operational_guard_v1 before insert or update on public.fee_adjustments for each row execute function public.fee_operational_reference_guard_v1();
drop trigger if exists trg_fee_operational_guard_v1 on public.reported_payments;
create trigger trg_fee_operational_guard_v1 before insert or update on public.reported_payments for each row execute function public.fee_operational_reference_guard_v1();

alter table public.fee_payment_allocations enable row level security;
alter table public.fee_credits enable row level security;
alter table public.fee_exemptions enable row level security;
alter table public.fee_adjustments enable row level security;
alter table public.reported_payments enable row level security;

drop policy if exists fee_obligations_select on public.fee_obligations;
create policy fee_obligations_select on public.fee_obligations for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=fee_obligations.member_id and m.club_id=fee_obligations.club_id and m.profile_id=auth.uid()));
drop policy if exists fee_obligations_insert on public.fee_obligations;
drop policy if exists fee_obligations_update on public.fee_obligations;

drop policy if exists fee_payments_select on public.fee_payments;
create policy fee_payments_select on public.fee_payments for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=fee_payments.member_id and m.club_id=fee_payments.club_id and m.profile_id=auth.uid()));

drop policy if exists fee_plans_access on public.fee_plans;
drop policy if exists fee_plans_select on public.fee_plans;
drop policy if exists fee_plans_manage on public.fee_plans;
create policy fee_plans_select on public.fee_plans for select to authenticated using(public.has_club_access(club_id));
create policy fee_plans_manage on public.fee_plans for all to authenticated
using(public.has_club_permission(club_id,'manageFees')) with check(public.has_club_permission(club_id,'manageFees'));

drop policy if exists fee_payment_allocations_select on public.fee_payment_allocations;
create policy fee_payment_allocations_select on public.fee_payment_allocations for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.fee_payments p join public.members m on m.id=p.member_id and m.club_id=p.club_id
    where p.id=fee_payment_allocations.payment_id and p.club_id=fee_payment_allocations.club_id and m.profile_id=auth.uid()));
drop policy if exists fee_credits_select on public.fee_credits;
create policy fee_credits_select on public.fee_credits for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=fee_credits.member_id and m.club_id=fee_credits.club_id and m.profile_id=auth.uid()));
drop policy if exists fee_exemptions_select on public.fee_exemptions;
create policy fee_exemptions_select on public.fee_exemptions for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=fee_exemptions.member_id and m.club_id=fee_exemptions.club_id and m.profile_id=auth.uid()));
drop policy if exists fee_adjustments_select on public.fee_adjustments;
create policy fee_adjustments_select on public.fee_adjustments for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=fee_adjustments.member_id and m.club_id=fee_adjustments.club_id and m.profile_id=auth.uid()));
drop policy if exists reported_payments_select on public.reported_payments;
create policy reported_payments_select on public.reported_payments for select to authenticated using(
  public.has_club_permission(club_id,'manageFees') or exists(
    select 1 from public.members m where m.id=reported_payments.member_id and m.club_id=reported_payments.club_id and m.profile_id=auth.uid()));

-- Bucket privado: pasta club/auth.uid/ficheiro.
drop policy if exists fee_payment_proofs_insert_v1 on storage.objects;
create policy fee_payment_proofs_insert_v1 on storage.objects for insert to authenticated with check(
  bucket_id='fee-payment-proofs' and (storage.foldername(name))[1] is not null
  and (storage.foldername(name))[2]=auth.uid()::text and exists(
    select 1 from public.club_memberships cm where cm.club_id::text=(storage.foldername(name))[1] and cm.profile_id=auth.uid() and cm.active=true));
drop policy if exists fee_payment_proofs_select_v1 on storage.objects;
create policy fee_payment_proofs_select_v1 on storage.objects for select to authenticated using(
  bucket_id='fee-payment-proofs' and ((storage.foldername(name))[2]=auth.uid()::text or exists(
    select 1 from public.reported_payments rp where rp.proof_path=name and public.has_club_permission(rp.club_id,'manageFees'))));
drop policy if exists fee_payment_proofs_delete_v1 on storage.objects;
create policy fee_payment_proofs_delete_v1 on storage.objects for delete to authenticated using(
  bucket_id='fee-payment-proofs' and (((storage.foldername(name))[2]=auth.uid()::text and not exists(
    select 1 from public.reported_payments rp where rp.proof_path=name and rp.status in('approved','rejected','reversed')))
    or exists(select 1 from public.reported_payments rp where rp.proof_path=name and public.has_club_permission(rp.club_id,'manageFees'))));

-- Leitura direta; escrita exclusivamente via RPC nas entidades económicas.
revoke all on public.fee_payment_allocations from anon;
revoke all on public.fee_credits from anon;
revoke all on public.fee_exemptions from anon;
revoke all on public.fee_adjustments from anon;
revoke all on public.reported_payments from anon;
grant select on public.fee_payment_allocations,public.fee_credits,public.fee_exemptions,public.fee_adjustments,public.reported_payments to authenticated;
revoke insert,update,delete,truncate on public.fee_obligations from authenticated;
revoke insert,update,delete,truncate on public.fee_payments from authenticated;
revoke insert,update,delete,truncate on public.fee_payment_allocations from authenticated;
revoke insert,update,delete,truncate on public.fee_credits from authenticated;
revoke insert,update,delete,truncate on public.fee_exemptions from authenticated;
revoke insert,update,delete,truncate on public.fee_adjustments from authenticated;
revoke insert,update,delete,truncate on public.reported_payments from authenticated;
grant select on public.fee_obligations,public.fee_payments,public.fee_plans to authenticated;

-- Audit global nas novas tabelas.
drop trigger if exists trg_audit_stamp_v1 on public.fee_payment_allocations;
create trigger trg_audit_stamp_v1 before insert or update on public.fee_payment_allocations for each row execute function public.audit_stamp_row_v1();
drop trigger if exists trg_audit_capture_v1 on public.fee_payment_allocations;
create trigger trg_audit_capture_v1 after insert or update or delete on public.fee_payment_allocations for each row execute function public.audit_capture_row_v1();
drop trigger if exists trg_audit_stamp_v1 on public.fee_credits;
create trigger trg_audit_stamp_v1 before insert or update on public.fee_credits for each row execute function public.audit_stamp_row_v1();
drop trigger if exists trg_audit_capture_v1 on public.fee_credits;
create trigger trg_audit_capture_v1 after insert or update or delete on public.fee_credits for each row execute function public.audit_capture_row_v1();
drop trigger if exists trg_audit_stamp_v1 on public.fee_exemptions;
create trigger trg_audit_stamp_v1 before insert or update on public.fee_exemptions for each row execute function public.audit_stamp_row_v1();
drop trigger if exists trg_audit_capture_v1 on public.fee_exemptions;
create trigger trg_audit_capture_v1 after insert or update or delete on public.fee_exemptions for each row execute function public.audit_capture_row_v1();
drop trigger if exists trg_audit_stamp_v1 on public.fee_adjustments;
create trigger trg_audit_stamp_v1 before insert or update on public.fee_adjustments for each row execute function public.audit_stamp_row_v1();
drop trigger if exists trg_audit_capture_v1 on public.fee_adjustments;
create trigger trg_audit_capture_v1 after insert or update or delete on public.fee_adjustments for each row execute function public.audit_capture_row_v1();
drop trigger if exists trg_audit_stamp_v1 on public.reported_payments;
create trigger trg_audit_stamp_v1 before insert or update on public.reported_payments for each row execute function public.audit_stamp_row_v1();
drop trigger if exists trg_audit_capture_v1 on public.reported_payments;
create trigger trg_audit_capture_v1 after insert or update or delete on public.reported_payments for each row execute function public.audit_capture_row_v1();