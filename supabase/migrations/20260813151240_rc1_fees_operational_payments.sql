create or replace function public.fee_operational_reference_guard_v1()
returns trigger
language plpgsql
set search_path=public
as $$
declare v jsonb:=to_jsonb(new); v_id uuid; v_member uuid;
begin
  if nullif(v->>'member_id','') is not null then
    v_member:=(v->>'member_id')::uuid;
    if not exists(select 1 from public.members m where m.id=v_member and m.club_id=new.club_id) then
      raise exception 'O membro não pertence ao clube.';
    end if;
  end if;
  if nullif(v->>'obligation_id','') is not null then
    v_id:=(v->>'obligation_id')::uuid;
    if not exists(select 1 from public.fee_obligations o where o.id=v_id and o.club_id=new.club_id and (v_member is null or o.member_id=v_member)) then
      raise exception 'A quota não pertence ao membro/clube.';
    end if;
  end if;
  if nullif(v->>'payment_id','') is not null then
    v_id:=(v->>'payment_id')::uuid;
    if not exists(select 1 from public.fee_payments p where p.id=v_id and p.club_id=new.club_id and (v_member is null or p.member_id=v_member)) then
      raise exception 'O pagamento não pertence ao membro/clube.';
    end if;
  end if;
  if nullif(v->>'source_credit_id','') is not null then
    v_id:=(v->>'source_credit_id')::uuid;
    if not exists(select 1 from public.fee_credits c where c.id=v_id and c.club_id=new.club_id and (v_member is null or c.member_id=v_member)) then
      raise exception 'O crédito de origem não pertence ao membro/clube.';
    end if;
  end if;
  if nullif(v->>'fee_payment_id','') is not null then
    v_id:=(v->>'fee_payment_id')::uuid;
    if not exists(select 1 from public.fee_payments p where p.id=v_id and p.club_id=new.club_id and (v_member is null or p.member_id=v_member)) then
      raise exception 'O pagamento validado não pertence ao membro/clube.';
    end if;
  end if;
  if nullif(v->>'transaction_id','') is not null then
    v_id:=(v->>'transaction_id')::uuid;
    if not exists(select 1 from public.treasury_transactions t where t.id=v_id and t.club_id=new.club_id) then
      raise exception 'O movimento financeiro não pertence ao clube.';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.fee_operational_reference_guard_v1() from public,anon,authenticated;

create or replace function public.fee_obligation_outstanding_v1(p_obligation public.fee_obligations)
returns numeric language sql immutable set search_path=public as $$
  select greatest(0::numeric,coalesce(p_obligation.amount,0)+coalesce(p_obligation.adjustment_amount,0)-coalesce(p_obligation.exempt_amount,0)-coalesce(p_obligation.paid_amount,0));
$$;
revoke all on function public.fee_obligation_outstanding_v1(public.fee_obligations) from public,anon,authenticated;

create or replace function public.refresh_fee_obligation_status_v1(p_obligation uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v public.fee_obligations%rowtype; v_total numeric;
begin
  select * into v from public.fee_obligations where id=p_obligation for update;
  if not found or v.status='cancelled' then return; end if;
  v_total:=greatest(0,coalesce(v.amount,0)+coalesce(v.adjustment_amount,0)-coalesce(v.exempt_amount,0));
  update public.fee_obligations set status=case
    when v_total=0 and coalesce(v.exempt_amount,0)>0 then 'exempt'::public.fee_status
    when coalesce(v.paid_amount,0)>=v_total and v_total>0 then 'paid'::public.fee_status
    when coalesce(v.paid_amount,0)>0 then 'partial'::public.fee_status
    else 'pending'::public.fee_status end
  where id=p_obligation;
end;
$$;
revoke all on function public.refresh_fee_obligation_status_v1(uuid) from public,anon,authenticated;

create or replace function public.fee_credit_balance_v1(target_club uuid,p_member uuid)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare v_total numeric;
begin
  if auth.uid() is null or not(public.has_club_permission(target_club,'manageFees') or exists(
    select 1 from public.members m where m.id=p_member and m.club_id=target_club and m.profile_id=auth.uid()
  )) then raise exception 'Sem acesso ao saldo de crédito.'; end if;
  select coalesce(sum(c.amount),0) into v_total from public.fee_credits c where c.club_id=target_club and c.member_id=p_member;
  return greatest(0,v_total);
end;
$$;
revoke all on function public.fee_credit_balance_v1(uuid,uuid) from public,anon;
grant execute on function public.fee_credit_balance_v1(uuid,uuid) to authenticated;

create or replace function public.preview_fee_payment_v1(target_club uuid,p_member uuid,p_amount numeric)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r record; v_remaining numeric:=coalesce(p_amount,0); v_use numeric; v_allocations jsonb:='[]'::jsonb; v_credit numeric:=0;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para receber quotas.'; end if;
  if v_remaining<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then raise exception 'Membro inválido.'; end if;
  for r in select o.*,public.fee_obligation_outstanding_v1(o) outstanding from public.fee_obligations o
    where o.club_id=target_club and o.member_id=p_member and o.status not in('cancelled','exempt','paid') and public.fee_obligation_outstanding_v1(o)>0
    order by o.due_date nulls last,o.reference_year,o.reference_month nulls first,o.created_at
  loop
    exit when v_remaining<=0;
    v_use:=least(v_remaining,r.outstanding);
    v_allocations:=v_allocations||jsonb_build_array(jsonb_build_object('obligation_id',r.id,'reference_year',r.reference_year,'reference_month',r.reference_month,'obligation_type',r.obligation_type,'due_date',r.due_date,'amount',v_use,'outstanding_before',r.outstanding));
    v_remaining:=v_remaining-v_use;
  end loop;
  select coalesce(sum(amount),0) into v_credit from public.fee_credits where club_id=target_club and member_id=p_member;
  return jsonb_build_object('payment_amount',p_amount,'allocations',v_allocations,'allocated',p_amount-v_remaining,'excess_credit',v_remaining,'existing_credit',greatest(0,v_credit));
end;
$$;
revoke all on function public.preview_fee_payment_v1(uuid,uuid,numeric) from public,anon;
grant execute on function public.preview_fee_payment_v1(uuid,uuid,numeric) to authenticated;

create or replace function public.register_fee_payment_batch_v1(target_club uuid,p_member uuid,p_amount numeric,p_payment_method text,p_payment_date date default current_date,p_notes text default null,p_allocations jsonb default null,p_reported_payment uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_account uuid; v_payment uuid:=gen_random_uuid(); v_transaction uuid:=gen_random_uuid(); v_member_name text;
  v_remaining numeric:=coalesce(p_amount,0); v_first_obligation uuid; v_row jsonb;
  v_obligation public.fee_obligations%rowtype; v_requested numeric; v_outstanding numeric; r record;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para registar pagamentos de quotas.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor do pagamento deve ser superior a zero.'; end if;
  if nullif(trim(coalesce(p_payment_method,'')),'') is null then raise exception 'Indica o método de pagamento.'; end if;
  select full_name into v_member_name from public.members where id=p_member and club_id=target_club;
  if v_member_name is null then raise exception 'Membro inválido.'; end if;
  select id into v_account from public.treasury_accounts where club_id=target_club and lower(name)='quotas' and active=true order by created_at limit 1;
  if v_account is null then raise exception 'A conta Quotas não está disponível.'; end if;
  if p_reported_payment is not null and not exists(select 1 from public.reported_payments where id=p_reported_payment and club_id=target_club and member_id=p_member and status='pending' and amount=p_amount) then
    raise exception 'Pagamento comunicado inválido ou já tratado.';
  end if;

  insert into public.treasury_transactions(id,club_id,kind,account_id,transaction_date,description,amount,payment_method,notes,source_type,source_id,created_by)
  values(v_transaction,target_club,'income',v_account,coalesce(p_payment_date,current_date),'Pagamento de quotas - '||v_member_name,p_amount,trim(p_payment_method),nullif(trim(coalesce(p_notes,'')),''),'fee_payment',v_payment,auth.uid());
  insert into public.fee_payments(id,club_id,member_id,obligation_id,transaction_id,amount,paid_at,received_by,notes,payment_method,payment_date,status)
  values(v_payment,target_club,p_member,null,v_transaction,p_amount,now(),auth.uid(),nullif(trim(coalesce(p_notes,'')),''),trim(p_payment_method),coalesce(p_payment_date,current_date),'confirmed');

  if p_allocations is not null and jsonb_typeof(p_allocations)='array' and jsonb_array_length(p_allocations)>0 then
    for v_row in select value from jsonb_array_elements(p_allocations) loop
      if nullif(v_row->>'obligation_id','') is null then raise exception 'Distribuição inválida.'; end if;
      v_requested:=(v_row->>'amount')::numeric;
      if v_requested is null or v_requested<=0 then raise exception 'O valor distribuído deve ser positivo.'; end if;
      select * into v_obligation from public.fee_obligations where id=(v_row->>'obligation_id')::uuid and club_id=target_club and member_id=p_member for update;
      if not found then raise exception 'Quota da distribuição não encontrada.'; end if;
      if v_obligation.status in('paid','exempt','cancelled') then raise exception 'Uma das quotas já não aceita pagamentos.'; end if;
      v_outstanding:=public.fee_obligation_outstanding_v1(v_obligation);
      if v_requested>v_outstanding then raise exception 'A distribuição excede o saldo de uma quota.'; end if;
      if v_requested>v_remaining then raise exception 'A distribuição excede o valor recebido.'; end if;
      insert into public.fee_payment_allocations(club_id,payment_id,obligation_id,amount) values(target_club,v_payment,v_obligation.id,v_requested);
      update public.fee_obligations set paid_amount=paid_amount+v_requested where id=v_obligation.id;
      perform public.refresh_fee_obligation_status_v1(v_obligation.id);
      v_first_obligation:=coalesce(v_first_obligation,v_obligation.id); v_remaining:=v_remaining-v_requested;
    end loop;
  else
    for r in select o.id from public.fee_obligations o where o.club_id=target_club and o.member_id=p_member and o.status not in('paid','exempt','cancelled') and public.fee_obligation_outstanding_v1(o)>0 order by o.due_date nulls last,o.reference_year,o.reference_month nulls first,o.created_at for update
    loop
      exit when v_remaining<=0;
      select * into v_obligation from public.fee_obligations where id=r.id;
      v_outstanding:=public.fee_obligation_outstanding_v1(v_obligation); v_requested:=least(v_remaining,v_outstanding);
      insert into public.fee_payment_allocations(club_id,payment_id,obligation_id,amount) values(target_club,v_payment,v_obligation.id,v_requested);
      update public.fee_obligations set paid_amount=paid_amount+v_requested where id=v_obligation.id;
      perform public.refresh_fee_obligation_status_v1(v_obligation.id);
      v_first_obligation:=coalesce(v_first_obligation,v_obligation.id); v_remaining:=v_remaining-v_requested;
    end loop;
  end if;
  update public.fee_payments set obligation_id=v_first_obligation where id=v_payment;
  if v_remaining>0 then insert into public.fee_credits(club_id,member_id,amount,entry_type,payment_id,reason) values(target_club,p_member,v_remaining,'payment_excess',v_payment,'Excesso do pagamento de quotas'); end if;
  if p_reported_payment is not null then update public.reported_payments set status='approved',reviewed_at=now(),reviewed_by=auth.uid(),fee_payment_id=v_payment where id=p_reported_payment; end if;
  return v_payment;
end;
$$;
revoke all on function public.register_fee_payment_batch_v1(uuid,uuid,numeric,text,date,text,jsonb,uuid) from public,anon;
grant execute on function public.register_fee_payment_batch_v1(uuid,uuid,numeric,text,date,text,jsonb,uuid) to authenticated;

create or replace function public.register_fee_payment_v1(target_club uuid,p_obligation uuid,p_amount numeric,p_payment_method text,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_member uuid;
begin
  select member_id into v_member from public.fee_obligations where id=p_obligation and club_id=target_club;
  if v_member is null then raise exception 'Quota não encontrada.'; end if;
  return public.register_fee_payment_batch_v1(target_club,v_member,p_amount,p_payment_method,current_date,p_notes,jsonb_build_array(jsonb_build_object('obligation_id',p_obligation,'amount',p_amount)),null);
end;
$$;
revoke all on function public.register_fee_payment_v1(uuid,uuid,numeric,text,text) from public,anon;
grant execute on function public.register_fee_payment_v1(uuid,uuid,numeric,text,text) to authenticated;

create or replace function public.apply_fee_credit_v1(target_club uuid,p_member uuid,p_obligation uuid,p_amount numeric,p_reason text default null)
returns numeric language plpgsql security definer set search_path=public as $$
declare v_obligation public.fee_obligations%rowtype; v_outstanding numeric; v_balance numeric; v_remaining numeric:=coalesce(p_amount,0); v_use numeric; r record;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para aplicar créditos.'; end if;
  if v_remaining<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select * into v_obligation from public.fee_obligations where id=p_obligation and club_id=target_club and member_id=p_member for update;
  if not found then raise exception 'Quota não encontrada.'; end if;
  if v_obligation.status in('paid','exempt','cancelled') then raise exception 'A quota não aceita crédito.'; end if;
  v_outstanding:=public.fee_obligation_outstanding_v1(v_obligation);
  if v_remaining>v_outstanding then raise exception 'O crédito excede o saldo da quota.'; end if;
  select coalesce(sum(amount),0) into v_balance from public.fee_credits where club_id=target_club and member_id=p_member;
  if v_remaining>v_balance then raise exception 'Crédito disponível insuficiente.'; end if;
  for r in select c.id,c.amount+coalesce((select sum(x.amount) from public.fee_credits x where x.source_credit_id=c.id),0) available from public.fee_credits c
    where c.club_id=target_club and c.member_id=p_member and c.amount>0 and c.entry_type in('payment_excess','manual_adjustment') order by c.created_at,c.id for update
  loop
    exit when v_remaining<=0; if r.available<=0 then continue; end if; v_use:=least(v_remaining,r.available);
    insert into public.fee_credits(club_id,member_id,amount,entry_type,obligation_id,source_credit_id,reason)
    values(target_club,p_member,-v_use,'application',p_obligation,r.id,coalesce(nullif(trim(coalesce(p_reason,'')),''),'Aplicação de crédito em quota'));
    v_remaining:=v_remaining-v_use;
  end loop;
  if v_remaining>0 then raise exception 'Não foi possível consumir o crédito solicitado.'; end if;
  update public.fee_obligations set paid_amount=paid_amount+p_amount where id=p_obligation;
  perform public.refresh_fee_obligation_status_v1(p_obligation); return p_amount;
end;
$$;
revoke all on function public.apply_fee_credit_v1(uuid,uuid,uuid,numeric,text) from public,anon;
grant execute on function public.apply_fee_credit_v1(uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.add_fee_credit_adjustment_v1(target_club uuid,p_member uuid,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_balance numeric;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para ajustar créditos.'; end if;
  if p_amount is null or p_amount=0 then raise exception 'O ajuste não pode ser zero.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo do ajuste.'; end if;
  if not exists(select 1 from public.members where id=p_member and club_id=target_club) then raise exception 'Membro inválido.'; end if;
  select coalesce(sum(amount),0) into v_balance from public.fee_credits where club_id=target_club and member_id=p_member;
  if p_amount<0 and abs(p_amount)>v_balance then raise exception 'O ajuste deixaria o crédito negativo.'; end if;
  insert into public.fee_credits(club_id,member_id,amount,entry_type,reason) values(target_club,p_member,p_amount,'manual_adjustment',trim(p_reason)) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.add_fee_credit_adjustment_v1(uuid,uuid,numeric,text) from public,anon;
grant execute on function public.add_fee_credit_adjustment_v1(uuid,uuid,numeric,text) to authenticated;

create or replace function public.reverse_fee_payment_v1(target_club uuid,p_payment uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare p public.fee_payments%rowtype; t public.treasury_transactions%rowtype; v_reversal uuid:=gen_random_uuid(); a record; c record; u record;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageFees') then raise exception 'Sem autorização para reverter pagamentos de quotas.'; end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da reversão.'; end if;
  select * into p from public.fee_payments where id=p_payment and club_id=target_club for update;
  if not found then raise exception 'Pagamento não encontrado.'; end if;
  if p.status='reversed' then raise exception 'O pagamento já foi revertido.'; end if;
  select * into t from public.treasury_transactions where id=p.transaction_id and club_id=target_club for update;
  if not found then raise exception 'Movimento financeiro do pagamento não encontrado.'; end if;
  if exists(select 1 from public.treasury_transactions x where x.reversal_of=t.id) then raise exception 'O movimento financeiro já possui reversão.'; end if;
  for a in select obligation_id,amount from public.fee_payment_allocations where payment_id=p_payment and club_id=target_club loop
    update public.fee_obligations set paid_amount=greatest(0,paid_amount-a.amount) where id=a.obligation_id and club_id=target_club;
    perform public.refresh_fee_obligation_status_v1(a.obligation_id);
  end loop;
  for c in select * from public.fee_credits where club_id=target_club and member_id=p.member_id and payment_id=p_payment and amount>0 and entry_type='payment_excess' order by created_at loop
    for u in select * from public.fee_credits cu where cu.source_credit_id=c.id and cu.entry_type='application' and cu.amount<0 and not exists(select 1 from public.fee_credits rr where rr.reversal_of=cu.id) order by cu.created_at loop
      update public.fee_obligations set paid_amount=greatest(0,paid_amount-abs(u.amount)) where id=u.obligation_id and club_id=target_club;
      perform public.refresh_fee_obligation_status_v1(u.obligation_id);
      insert into public.fee_credits(club_id,member_id,amount,entry_type,obligation_id,source_credit_id,reversal_of,reason)
      values(target_club,p.member_id,abs(u.amount),'reversal',u.obligation_id,c.id,u.id,'Reversão da aplicação de crédito');
    end loop;
    insert into public.fee_credits(club_id,member_id,amount,entry_type,payment_id,source_credit_id,reversal_of,reason)
    values(target_club,p.member_id,-c.amount,'reversal',p_payment,c.id,c.id,'Reversão do excesso do pagamento');
  end loop;
  insert into public.treasury_transactions(id,club_id,kind,account_id,transaction_date,description,amount,payment_method,notes,source_type,source_id,reversal_of,created_by)
  values(v_reversal,target_club,'expense',t.account_id,current_date,'Reversão — '||t.description,t.amount,t.payment_method,trim(p_reason),'fee_payment_reversal',p_payment,t.id,auth.uid());
  update public.fee_payments set status='reversed',reversed_at=now(),reversed_by=auth.uid(),reversal_reason=trim(p_reason) where id=p_payment;
  update public.reported_payments set status='reversed',review_notes=trim(concat_ws(' · ',nullif(review_notes,''),'Pagamento revertido: '||trim(p_reason))),updated_at=now() where fee_payment_id=p_payment and status='approved';
  perform public.emit_domain_event(target_club,'FeePaymentReversed','fee',p_payment,jsonb_build_object('title','Pagamento de quotas revertido','description',coalesce(p.amount,0)::text||' € · '||trim(p_reason),'route','fees','priority','important','amount',p.amount));
  return v_reversal;
end;
$$;
revoke all on function public.reverse_fee_payment_v1(uuid,uuid,text) from public,anon;
grant execute on function public.reverse_fee_payment_v1(uuid,uuid,text) to authenticated;