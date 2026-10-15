create or replace function public.save_fee_obligation_v1(
  target_club uuid,p_obligation uuid,p_member uuid,p_reference_year integer,
  p_reference_month integer,p_due_date date,p_amount numeric,p_obligation_type text,p_notes text
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para gerir quotas.'; end if;
  if p_amount is null or p_amount<0 then raise exception 'O valor da quota é inválido.'; end if;
  if p_reference_year is null or p_reference_year<2000 or p_reference_year>2200 then raise exception 'Ano inválido.'; end if;
  if p_obligation_type not in('monthly','registration') then raise exception 'Tipo de quota inválido.'; end if;
  if p_obligation_type='monthly' and (p_reference_month is null or p_reference_month<1 or p_reference_month>12) then raise exception 'Mês inválido.'; end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then raise exception 'Membro inválido.'; end if;
  if p_obligation is null then
    insert into public.fee_obligations(club_id,member_id,reference_year,reference_month,due_date,amount,paid_amount,exempt_amount,adjustment_amount,status,obligation_type,notes)
    values(target_club,p_member,p_reference_year,case when p_obligation_type='registration' then null else p_reference_month end,p_due_date,p_amount,0,0,0,'pending',p_obligation_type,nullif(trim(coalesce(p_notes,'')),'')) returning id into v_id;
  else
    if exists(select 1 from public.fee_payment_allocations where obligation_id=p_obligation) then raise exception 'A quota já tem pagamentos. Usa ajustes, isenções ou reversões.'; end if;
    update public.fee_obligations set member_id=p_member,reference_year=p_reference_year,
      reference_month=case when p_obligation_type='registration' then null else p_reference_month end,
      due_date=p_due_date,amount=p_amount,obligation_type=p_obligation_type,notes=nullif(trim(coalesce(p_notes,'')),'')
    where id=p_obligation and club_id=target_club returning id into v_id;
    if v_id is null then raise exception 'Quota não encontrada.'; end if;
  end if;
  perform public.refresh_fee_obligation_status_v1(v_id); return v_id;
end;
$$;
revoke all on function public.save_fee_obligation_v1(uuid,uuid,uuid,integer,integer,date,numeric,text,text) from public,anon;
grant execute on function public.save_fee_obligation_v1(uuid,uuid,uuid,integer,integer,date,numeric,text,text) to authenticated;

create or replace function public.apply_fee_exemption_v1(target_club uuid,p_obligation uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v public.fee_obligations%rowtype; v_outstanding numeric; v_id uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para aplicar isenções.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da isenção.'; end if;
  select * into v from public.fee_obligations where id=p_obligation and club_id=target_club for update;
  if not found then raise exception 'Quota não encontrada.'; end if;
  if v.status in('paid','exempt','cancelled') then raise exception 'A quota não aceita isenção.'; end if;
  v_outstanding:=public.fee_obligation_outstanding_v1(v);
  if p_amount>v_outstanding then raise exception 'A isenção excede o saldo da quota.'; end if;
  insert into public.fee_exemptions(club_id,member_id,obligation_id,amount,reason)
  values(target_club,v.member_id,p_obligation,p_amount,trim(p_reason)) returning id into v_id;
  update public.fee_obligations set exempt_amount=exempt_amount+p_amount where id=p_obligation;
  perform public.refresh_fee_obligation_status_v1(p_obligation); return v_id;
end;
$$;
revoke all on function public.apply_fee_exemption_v1(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.apply_fee_exemption_v1(uuid,uuid,numeric,text) to authenticated;

create or replace function public.reverse_fee_exemption_v1(target_club uuid,p_exemption uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v public.fee_exemptions%rowtype;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para reverter isenções.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da reversão.'; end if;
  select * into v from public.fee_exemptions where id=p_exemption and club_id=target_club for update;
  if not found then raise exception 'Isenção não encontrada.'; end if;
  if v.status='reversed' then raise exception 'A isenção já foi revertida.'; end if;
  update public.fee_exemptions set status='reversed',reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason) where id=p_exemption;
  update public.fee_obligations set exempt_amount=greatest(0,exempt_amount-v.amount) where id=v.obligation_id;
  perform public.refresh_fee_obligation_status_v1(v.obligation_id);
end;
$$;
revoke all on function public.reverse_fee_exemption_v1(uuid,uuid,text) from public,anon;
grant execute on function public.reverse_fee_exemption_v1(uuid,uuid,text) to authenticated;

create or replace function public.apply_fee_adjustment_v1(target_club uuid,p_obligation uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v public.fee_obligations%rowtype; v_outstanding numeric; v_id uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para ajustar quotas.'; end if;
  if p_amount is null or p_amount=0 then raise exception 'O ajuste não pode ser zero.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo do ajuste.'; end if;
  select * into v from public.fee_obligations where id=p_obligation and club_id=target_club for update;
  if not found then raise exception 'Quota não encontrada.'; end if;
  if v.status in('cancelled','exempt') then raise exception 'A quota não aceita ajustes.'; end if;
  v_outstanding:=public.fee_obligation_outstanding_v1(v);
  if p_amount<0 and abs(p_amount)>v_outstanding then raise exception 'A redução excede o saldo pendente.'; end if;
  insert into public.fee_adjustments(club_id,member_id,obligation_id,amount,reason)
  values(target_club,v.member_id,p_obligation,p_amount,trim(p_reason)) returning id into v_id;
  update public.fee_obligations set adjustment_amount=adjustment_amount+p_amount where id=p_obligation;
  perform public.refresh_fee_obligation_status_v1(p_obligation); return v_id;
end;
$$;
revoke all on function public.apply_fee_adjustment_v1(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.apply_fee_adjustment_v1(uuid,uuid,numeric,text) to authenticated;

create or replace function public.reverse_fee_adjustment_v1(target_club uuid,p_adjustment uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v public.fee_adjustments%rowtype; o public.fee_obligations%rowtype; v_new numeric; v_total numeric;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para reverter ajustes.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da reversão.'; end if;
  select * into v from public.fee_adjustments where id=p_adjustment and club_id=target_club for update;
  if not found then raise exception 'Ajuste não encontrado.'; end if;
  if v.status='reversed' then raise exception 'O ajuste já foi revertido.'; end if;
  select * into o from public.fee_obligations where id=v.obligation_id for update;
  v_new:=o.adjustment_amount-v.amount; v_total:=greatest(0,o.amount+v_new-o.exempt_amount);
  if o.paid_amount>v_total then raise exception 'A reversão deixaria pagamentos acima do valor devido.'; end if;
  update public.fee_adjustments set status='reversed',reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason) where id=p_adjustment;
  update public.fee_obligations set adjustment_amount=v_new where id=v.obligation_id;
  perform public.refresh_fee_obligation_status_v1(v.obligation_id);
end;
$$;
revoke all on function public.reverse_fee_adjustment_v1(uuid,uuid,text) from public,anon;
grant execute on function public.reverse_fee_adjustment_v1(uuid,uuid,text) to authenticated;

create or replace function public.create_reported_fee_payment_v1(
  target_club uuid,p_amount numeric,p_paid_on date,p_payment_method text,p_notes text,
  p_proof_path text,p_proof_name text,p_proof_mime_type text,p_proof_size bigint
)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_member uuid; v_id uuid; v_prefix text;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select m.id into v_member from public.members m join public.club_memberships cm on cm.club_id=m.club_id and cm.profile_id=m.profile_id and cm.active=true
  where m.club_id=target_club and m.profile_id=auth.uid() limit 1;
  if v_member is null then raise exception 'Não existe membro associado ao utilizador.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if p_paid_on is null then raise exception 'Indica a data do pagamento.'; end if;
  if nullif(trim(coalesce(p_payment_method,'')),'') is null then raise exception 'Indica o método de pagamento.'; end if;
  if nullif(trim(coalesce(p_proof_path,'')),'') is null or nullif(trim(coalesce(p_proof_name,'')),'') is null then raise exception 'É obrigatório anexar o comprovativo.'; end if;
  v_prefix:=target_club::text||'/'||auth.uid()::text||'/';
  if left(p_proof_path,length(v_prefix))<>v_prefix then raise exception 'Caminho do comprovativo inválido.'; end if;
  insert into public.reported_payments(club_id,member_id,amount,paid_on,payment_method,notes,proof_path,proof_name,proof_mime_type,proof_size,status,created_by)
  values(target_club,v_member,p_amount,p_paid_on,trim(p_payment_method),nullif(trim(coalesce(p_notes,'')),''),p_proof_path,p_proof_name,p_proof_mime_type,p_proof_size,'pending',auth.uid()) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_reported_fee_payment_v1(uuid,numeric,date,text,text,text,text,text,bigint) from public,anon;
grant execute on function public.create_reported_fee_payment_v1(uuid,numeric,date,text,text,text,text,text,bigint) to authenticated;

create or replace function public.review_reported_fee_payment_v1(target_club uuid,p_report uuid,p_action text,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v public.reported_payments%rowtype; v_payment uuid; v_action text:=lower(trim(coalesce(p_action,'')));
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para validar pagamentos comunicados.'; end if;
  if v_action not in('approve','reject') then raise exception 'Ação inválida.'; end if;
  select * into v from public.reported_payments where id=p_report and club_id=target_club for update;
  if not found then raise exception 'Pagamento comunicado não encontrado.'; end if;
  if v.status<>'pending' then raise exception 'O pagamento comunicado já foi tratado.'; end if;
  if v_action='reject' then
    if length(trim(coalesce(p_notes,'')))<3 then raise exception 'Indica o motivo da rejeição.'; end if;
    update public.reported_payments set status='rejected',review_notes=trim(p_notes),reviewed_at=now(),reviewed_by=auth.uid() where id=p_report;
    return null;
  end if;
  v_payment:=public.register_fee_payment_batch_v1(target_club,v.member_id,v.amount,v.payment_method,v.paid_on,coalesce(nullif(trim(coalesce(p_notes,'')),''),v.notes),null,p_report);
  update public.reported_payments set review_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_report;
  return v_payment;
end;
$$;
revoke all on function public.review_reported_fee_payment_v1(uuid,uuid,text,text) from public,anon;
grant execute on function public.review_reported_fee_payment_v1(uuid,uuid,text,text) to authenticated;

create or replace function public.cancel_reported_fee_payment_v1(target_club uuid,p_report uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v public.reported_payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select * into v from public.reported_payments where id=p_report and club_id=target_club for update;
  if not found then raise exception 'Pagamento comunicado não encontrado.'; end if;
  if v.status<>'pending' then raise exception 'Só é possível cancelar pagamentos pendentes.'; end if;
  if not exists(select 1 from public.members m where m.id=v.member_id and m.club_id=target_club and m.profile_id=auth.uid()) and not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para cancelar este pagamento.'; end if;
  update public.reported_payments set status='cancelled' where id=p_report;
end;
$$;
revoke all on function public.cancel_reported_fee_payment_v1(uuid,uuid) from public,anon;
grant execute on function public.cancel_reported_fee_payment_v1(uuid,uuid) to authenticated;

create or replace function public.update_fee_settings_v1(target_club uuid,p_due_day integer,p_monthly_amount numeric,p_registration_amount numeric)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para alterar as definições de quotas.'; end if;
  if p_due_day<1 or p_due_day>28 then raise exception 'O dia de vencimento deve estar entre 1 e 28.'; end if;
  if p_monthly_amount<0 or p_registration_amount<0 then raise exception 'Os valores não podem ser negativos.'; end if;
  insert into public.club_settings(club_id,key,value,updated_by) values
    (target_club,'fee_due_day',p_due_day::text,auth.uid()),(target_club,'monthly_fee_amount',p_monthly_amount::text,auth.uid()),(target_club,'registration_fee_amount',p_registration_amount::text,auth.uid())
  on conflict(club_id,key) do update set value=excluded.value,updated_by=excluded.updated_by,updated_at=now();
  update public.fee_plans set due_day=p_due_day,amount=p_monthly_amount where club_id=target_club and active=true and frequency='monthly';
end;
$$;
revoke all on function public.update_fee_settings_v1(uuid,integer,numeric,numeric) from public,anon;
grant execute on function public.update_fee_settings_v1(uuid,integer,numeric,numeric) to authenticated;

create or replace function public.sync_member_fee_obligations_v1(target_club uuid,p_year integer default null,p_member uuid default null)
returns void language plpgsql security definer set search_path=public as $$
declare target_year integer:=coalesce(p_year,extract(year from current_date)::integer); r record;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para gerar quotas.'; end if;
  for r in select id from public.members where club_id=target_club and status::text in('prospect','full_color','active') and (p_member is null or id=p_member)
  loop perform public.generate_member_fees_internal(r.id,target_year); end loop;
end;
$$;
revoke all on function public.sync_member_fee_obligations_v1(uuid,integer,uuid) from public,anon;
grant execute on function public.sync_member_fee_obligations_v1(uuid,integer,uuid) to authenticated;

create or replace function public.delete_fee_obligation_v1(target_club uuid,p_obligation uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.club_memberships cm where cm.club_id=target_club and cm.profile_id=auth.uid() and cm.active=true and lower(cm.access_role) in('super_admin','super admin')) then raise exception 'Apenas o Super Admin pode apagar quotas.'; end if;
  if exists(select 1 from public.fee_payment_allocations where club_id=target_club and obligation_id=p_obligation)
     or exists(select 1 from public.fee_exemptions where club_id=target_club and obligation_id=p_obligation)
     or exists(select 1 from public.fee_adjustments where club_id=target_club and obligation_id=p_obligation) then raise exception 'Esta quota tem histórico e não pode ser apagada. Usa anulação/reversão.'; end if;
  delete from public.fee_obligations where id=p_obligation and club_id=target_club;
end;
$$;
revoke all on function public.delete_fee_obligation_v1(uuid,uuid) from public,anon;
grant execute on function public.delete_fee_obligation_v1(uuid,uuid) to authenticated;

create or replace function public.activity_fee_payment_trigger_v1()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  select full_name into v_name from public.members where id=new.member_id and club_id=new.club_id;
  perform public.emit_domain_event(new.club_id,'FeePaid','fee',new.id,jsonb_build_object('title','Quotas recebidas','description',coalesce(v_name,'Membro')||' · '||to_char(new.amount,'FM999999990D00')||' €','route','fees','priority','normal','amount',new.amount));
  return new;
end;
$$;