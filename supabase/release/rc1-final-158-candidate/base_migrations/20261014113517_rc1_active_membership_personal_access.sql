-- Phase 2C.6: revoke personal operational access immediately on inactive membership.
-- Definitions and policies only; no business calls or backfill.
begin;

create or replace function public.current_financial_member_v1(target_club uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select m.id
  from public.members m
  where auth.uid() is not null
    and exists (select 1 from public.club_memberships cm where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active is true)
    and m.club_id=target_club
    and m.profile_id=auth.uid()
    and m.status::text not in ('former','deceased')
  order by m.created_at
  limit 1;
$$;

revoke all on function public.current_financial_member_v1(uuid) from public, anon;
grant execute on function public.current_financial_member_v1(uuid) to authenticated;

create or replace function public.financial_request_access_v1(p_request uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.financial_requests r
    join public.members m on m.id=r.member_id
    where r.id=p_request
      and (
        public.financial_manager_v1(r.club_id)
        or (m.profile_id=auth.uid() and exists (select 1 from public.club_memberships cm where cm.club_id=r.club_id and cm.profile_id=auth.uid() and cm.active is true))
      )
  );
$$;

revoke all on function public.financial_request_access_v1(uuid) from public, anon;
grant execute on function public.financial_request_access_v1(uuid) to authenticated;

create or replace function public.current_weekly_officer_member_v1(target_club uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select m.id
  from public.members m
  where auth.uid() is not null
    and exists (select 1 from public.club_memberships cm where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active is true)
    and m.club_id=target_club
    and m.profile_id=(select auth.uid())
  limit 1;
$$;

revoke all on function public.current_weekly_officer_member_v1(uuid) from public, anon;
grant execute on function public.current_weekly_officer_member_v1(uuid) to authenticated;

create or replace function public.fee_credit_balance_v1(target_club uuid,p_member uuid)
returns numeric language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_total numeric;
begin
  if auth.uid() is null or not(public.has_club_permission(target_club,'manageFees') or exists(
    select 1 from public.members m where m.id=p_member and m.club_id=target_club and m.profile_id=auth.uid() and exists (select 1 from public.club_memberships cm where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active is true)
  )) then return null; end if;
  select coalesce(sum(c.amount),0) into v_total from public.fee_credits c where c.club_id=target_club and c.member_id=p_member;
  return greatest(0,v_total);
end;
$$;

revoke all on function public.fee_credit_balance_v1(uuid,uuid) from public, anon;
grant execute on function public.fee_credit_balance_v1(uuid,uuid) to authenticated;

create or replace function public.cancel_reported_fee_payment_v1(target_club uuid,p_report uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v public.reported_payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select * into v from public.reported_payments where id=p_report and club_id=target_club for update;
  if not found then raise exception 'Pagamento comunicado não encontrado.'; end if;
  if v.status<>'pending' then raise exception 'Só é possível cancelar pagamentos pendentes.'; end if;
  if not exists(select 1 from public.members m where m.id=v.member_id and m.club_id=target_club and m.profile_id=auth.uid() and exists (select 1 from public.club_memberships cm where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active is true)) and not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para cancelar este pagamento.'; end if;
  update public.reported_payments set status='cancelled' where id=p_report;
end;
$$;

revoke all on function public.cancel_reported_fee_payment_v1(uuid,uuid) from public, anon;
grant execute on function public.cancel_reported_fee_payment_v1(uuid,uuid) to authenticated;

create or replace function public.acknowledge_event_task_v1(
  p_assignment uuid,
  p_complete boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v public.event_task_assignees%rowtype;
  v_profile uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticação necessária.';
  end if;
  select * into v
  from public.event_task_assignees
  where id = p_assignment
  for update;
  if not found then
    raise exception 'Atribuição não encontrada.';
  end if;
  if v.member_id is not null then
    select m.profile_id into v_profile
    from public.members m
    where m.id = v.member_id;
    if (v_profile is distinct from (select auth.uid())
        or not exists (select 1 from public.club_memberships cm where cm.club_id=v.club_id and cm.profile_id=auth.uid() and cm.active is true))
       and not public.has_club_permission(v.club_id, 'manageEventOperations') then
      raise exception 'Sem permissão para atualizar esta tarefa.';
    end if;
  elsif not public.has_club_permission(v.club_id, 'manageEventOperations') then
    raise exception 'Sem permissão para atualizar esta tarefa.';
  end if;
  update public.event_task_assignees
  set acknowledged_at = coalesce(acknowledged_at, now()),
      completed_at = case when p_complete then now() else completed_at end
  where id = p_assignment;
  if p_complete then
    update public.event_tasks
    set status = 'done',
        completed_at = coalesce(completed_at, now()),
        updated_at = now()
    where id = v.task_id;
  end if;
end;
$$;

revoke all on function public.acknowledge_event_task_v1(uuid,boolean) from public, anon;
grant execute on function public.acknowledge_event_task_v1(uuid,boolean) to authenticated;

create or replace function public.set_event_shift_member_status_v1(
  p_assignment uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v public.event_shift_members%rowtype;
  v_profile uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Autenticação necessária.';
  end if;
  if p_status not in ('assigned','confirmed','present','absent','cancelled') then
    raise exception 'Estado inválido.';
  end if;
  select * into v
  from public.event_shift_members
  where id = p_assignment
  for update;
  if not found then
    raise exception 'Atribuição não encontrada.';
  end if;
  if v.member_id is not null then
    select m.profile_id into v_profile
    from public.members m
    where m.id = v.member_id;
    if (v_profile is distinct from (select auth.uid())
        or not exists (select 1 from public.club_memberships cm where cm.club_id=v.club_id and cm.profile_id=auth.uid() and cm.active is true))
       and not public.has_club_permission(v.club_id, 'manageEventOperations') then
      raise exception 'Sem permissão para atualizar este turno.';
    end if;
  elsif not public.has_club_permission(v.club_id, 'manageEventOperations') then
    raise exception 'Sem permissão para atualizar este turno.';
  end if;
  update public.event_shift_members
  set status = p_status,
      checked_in_at = case
        when p_status = 'present' then coalesce(checked_in_at, now())
        else checked_in_at
      end,
      checked_out_at = case
        when p_status in ('absent','cancelled') then coalesce(checked_out_at, now())
        else checked_out_at
      end
  where id = p_assignment;
end;
$$;

revoke all on function public.set_event_shift_member_status_v1(uuid,text) from public, anon;
grant execute on function public.set_event_shift_member_status_v1(uuid,text) to authenticated;

create or replace function public.withdraw_event_proposal_v1(p_proposal uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v public.event_proposals%rowtype;
begin
  if (select auth.uid()) is null then raise exception 'Autenticação necessária.'; end if;
  select * into v from public.event_proposals where id = p_proposal for update;
  if not found then raise exception 'Proposta não encontrada.'; end if;
  if v.proposed_by is distinct from (select auth.uid()) or not exists (select 1 from public.club_memberships cm where cm.club_id=v.club_id and cm.profile_id=auth.uid() and cm.active is true) then raise exception 'Só o autor pode retirar a proposta.'; end if;
  if v.status <> 'submitted' then raise exception 'A proposta já foi processada.'; end if;
  update public.event_proposals
  set status='withdrawn', updated_at=now(), updated_by=(select auth.uid())
  where id=p_proposal;
end;
$$;

revoke all on function public.withdraw_event_proposal_v1(uuid) from public, anon;
grant execute on function public.withdraw_event_proposal_v1(uuid) to authenticated;

-- Keep permission-based manager access; only personal alternatives require active membership.
drop policy if exists financial_requests_read on public.financial_requests;
create policy financial_requests_read on public.financial_requests
for select to authenticated using (public.financial_request_access_v1(id));

drop policy if exists fee_credits_select on public.fee_credits;
create policy fee_credits_select on public.fee_credits for select to authenticated
using (
  public.has_club_permission(club_id,'manageFees')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=fee_credits.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
      select 1 from public.members m
      where m.id=fee_credits.member_id and m.club_id=fee_credits.club_id
        and m.profile_id=(select auth.uid())
    ))
);

drop policy if exists reported_payments_select on public.reported_payments;
create policy reported_payments_select on public.reported_payments for select to authenticated
using (
  public.has_club_permission(club_id,'manageFees')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=reported_payments.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
      select 1 from public.members m
      where m.id=reported_payments.member_id and m.club_id=reported_payments.club_id
        and m.profile_id=(select auth.uid())
    ))
);

drop policy if exists fee_exemptions_select on public.fee_exemptions;
create policy fee_exemptions_select on public.fee_exemptions for select to authenticated
using (
  public.has_club_permission(club_id,'manageFees')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=fee_exemptions.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
      select 1 from public.members m
      where m.id=fee_exemptions.member_id and m.club_id=fee_exemptions.club_id
        and m.profile_id=(select auth.uid())
    ))
);

drop policy if exists fee_adjustments_select on public.fee_adjustments;
create policy fee_adjustments_select on public.fee_adjustments for select to authenticated
using (
  public.has_club_permission(club_id,'manageFees')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=fee_adjustments.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
      select 1 from public.members m
      where m.id=fee_adjustments.member_id and m.club_id=fee_adjustments.club_id
        and m.profile_id=(select auth.uid())
    ))
);

drop policy if exists fee_payment_allocations_select on public.fee_payment_allocations;
create policy fee_payment_allocations_select on public.fee_payment_allocations for select to authenticated
using (
  public.has_club_permission(club_id,'manageFees')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=fee_payment_allocations.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
      select 1 from public.fee_payments p
      join public.members m on m.id=p.member_id and m.club_id=p.club_id
      where p.id=fee_payment_allocations.payment_id
        and p.club_id=fee_payment_allocations.club_id
        and m.profile_id=(select auth.uid())
    ))
);

drop policy if exists event_proposals_select on public.event_proposals;
create policy event_proposals_select on public.event_proposals for select to authenticated
using (
  public.has_club_permission(club_id,'approveEventProposals')
  or (proposed_by=(select auth.uid()) and exists (
      select 1 from public.club_memberships cm
      where cm.club_id=event_proposals.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ))
);

drop policy if exists event_guests_insert on public.event_guests;
create policy event_guests_insert on public.event_guests for insert to authenticated
with check (public.has_club_permission(club_id,'manageEventParticipants')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=event_guests.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
    select 1 from public.members m
    where m.id=event_guests.host_member_id and m.club_id=event_guests.club_id
      and m.profile_id=(select auth.uid())
  )));

drop policy if exists event_guests_update on public.event_guests;
create policy event_guests_update on public.event_guests for update to authenticated
using (public.has_club_permission(club_id,'manageEventParticipants')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=event_guests.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
    select 1 from public.members m
    where m.id=event_guests.host_member_id and m.club_id=event_guests.club_id
      and m.profile_id=(select auth.uid())
  )))
with check (public.has_club_permission(club_id,'manageEventParticipants')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=event_guests.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
    select 1 from public.members m
    where m.id=event_guests.host_member_id and m.club_id=event_guests.club_id
      and m.profile_id=(select auth.uid())
  )));

drop policy if exists event_guests_delete on public.event_guests;
create policy event_guests_delete on public.event_guests for delete to authenticated
using (public.has_club_permission(club_id,'manageEventParticipants')
  or (exists (
      select 1 from public.club_memberships cm
      where cm.club_id=event_guests.club_id
        and cm.profile_id=(select auth.uid()) and cm.active is true
    ) and exists (
    select 1 from public.members m
    where m.id=event_guests.host_member_id and m.club_id=event_guests.club_id
      and m.profile_id=(select auth.uid())
  )));

drop policy if exists fee_payment_proofs_select_v1 on storage.objects;
create policy fee_payment_proofs_select_v1 on storage.objects for select to authenticated using(
  bucket_id='fee-payment-proofs' and (((storage.foldername(name))[2]=auth.uid()::text and exists (select 1 from public.club_memberships cm where cm.club_id::text=(storage.foldername(name))[1] and cm.profile_id=auth.uid() and cm.active is true)) or exists(
    select 1 from public.reported_payments rp where rp.proof_path=name and public.has_club_permission(rp.club_id,'manageFees'))));

drop policy if exists fee_payment_proofs_delete_v1 on storage.objects;
create policy fee_payment_proofs_delete_v1 on storage.objects for delete to authenticated using(
  bucket_id='fee-payment-proofs' and ((((storage.foldername(name))[2]=auth.uid()::text and exists (select 1 from public.club_memberships cm where cm.club_id::text=(storage.foldername(name))[1] and cm.profile_id=auth.uid() and cm.active is true)) and not exists(
    select 1 from public.reported_payments rp where rp.proof_path=name and rp.status in('approved','rejected','reversed')))
    or exists(select 1 from public.reported_payments rp where rp.proof_path=name and public.has_club_permission(rp.club_id,'manageFees'))));

commit;
