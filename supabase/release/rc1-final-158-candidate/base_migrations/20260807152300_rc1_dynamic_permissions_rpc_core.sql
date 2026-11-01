create or replace function public.create_transaction_v1(
  target_club uuid,p_kind text,p_account uuid,p_destination_account uuid,
  p_description text,p_amount numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare result_id uuid;
begin
  if p_kind='transfer' then
    if not public.has_club_permission(target_club,'transferBetweenAccounts') then
      raise exception 'Sem autorização para transferir entre contas.';
    end if;
  else
    if not public.has_club_permission(target_club,'createTreasuryMovement') then
      raise exception 'Sem autorização para criar movimentos.';
    end if;
  end if;
  if p_kind not in ('income','expense','transfer') then raise exception 'Tipo de movimento inválido.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  if p_description is null or btrim(p_description)='' then raise exception 'A descrição é obrigatória.'; end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,destination_account_id,transaction_date,description,amount,created_by
  ) values(
    target_club,p_kind::public.transaction_kind,p_account,
    case when p_kind='transfer' then p_destination_account else null end,
    current_date,btrim(p_description),p_amount,auth.uid()
  ) returning id into result_id;
  return result_id;
end; $$;

create or replace function public.create_treasury_transaction(
  target_club uuid,transaction_kind public.transaction_kind,source_account uuid,
  destination_account uuid,category uuid,cost_center uuid,event_ref uuid,
  movement_date date,movement_description text,movement_amount numeric,
  movement_payment_method text,movement_notes text
) returns uuid language plpgsql security definer set search_path=public as $$
declare transaction_id uuid;
begin
  if transaction_kind='transfer' then
    if not public.has_club_permission(target_club,'transferBetweenAccounts') then
      raise exception 'Sem autorização para transferir entre contas.';
    end if;
  else
    if not public.has_club_permission(target_club,'createTreasuryMovement') then
      raise exception 'Sem autorização para criar movimentos.';
    end if;
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,destination_account_id,category_id,cost_center_id,event_id,
    transaction_date,description,amount,payment_method,notes,created_by
  ) values(
    target_club,transaction_kind,source_account,
    case when transaction_kind='transfer' then destination_account else null end,
    category,cost_center,event_ref,movement_date,movement_description,movement_amount,
    movement_payment_method,movement_notes,auth.uid()
  ) returning id into transaction_id;
  return transaction_id;
end; $$;

create or replace function public.register_fee_payment_v1(
  target_club uuid,p_obligation uuid,p_amount numeric,p_payment_method text,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_obligation public.fee_obligations%rowtype;
  v_member_name text; v_account_id uuid; v_transaction_id uuid; v_payment_id uuid;
  v_new_paid numeric; v_new_status public.fee_status;
begin
  if not public.has_club_permission(target_club,'manageFees') then
    raise exception 'Sem autorização para registar pagamentos de quotas.';
  end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor do pagamento deve ser superior a zero.'; end if;

  select * into v_obligation from public.fee_obligations
  where id=p_obligation and club_id=target_club for update;
  if not found then raise exception 'Quota não encontrada.'; end if;
  if v_obligation.status in ('paid','exempt','cancelled') then raise exception 'Esta quota não aceita novos pagamentos.'; end if;
  if v_obligation.paid_amount+p_amount>v_obligation.amount then raise exception 'O pagamento excede o valor em dívida.'; end if;

  select full_name into v_member_name from public.members
  where id=v_obligation.member_id and club_id=target_club;
  select id into v_account_id from public.treasury_accounts
  where club_id=target_club and lower(name)='quotas' and active=true order by created_at limit 1;
  if v_account_id is null then raise exception 'A conta Quotas não está disponível.'; end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
  ) values(
    target_club,'income',v_account_id,current_date,
    'Pagamento de quota - '||coalesce(v_member_name,'Membro'),p_amount,
    nullif(trim(p_payment_method),''),'fee_obligation',p_obligation,auth.uid()
  ) returning id into v_transaction_id;

  insert into public.fee_payments(
    club_id,obligation_id,transaction_id,amount,paid_at,received_by,notes
  ) values(
    target_club,p_obligation,v_transaction_id,p_amount,now(),auth.uid(),p_notes
  ) returning id into v_payment_id;

  v_new_paid:=v_obligation.paid_amount+p_amount;
  v_new_status:=case when v_new_paid>=v_obligation.amount
    then 'paid'::public.fee_status else 'partial'::public.fee_status end;
  update public.fee_obligations set paid_amount=v_new_paid,status=v_new_status where id=p_obligation;
  return v_payment_id;
end; $$;

create or replace function public.pay_fee_v1(
  p_obligation uuid,p_account uuid,p_amount numeric,p_method text
) returns void language plpgsql security definer set search_path=public as $$
declare v_club uuid;
begin
  select club_id into v_club from public.fee_obligations where id=p_obligation;
  if v_club is null then raise exception 'Quota não encontrada.'; end if;
  perform public.register_fee_payment_v1(v_club,p_obligation,p_amount,p_method,null);
end; $$;

create or replace function public.pay_fee_obligation(
  obligation_ref uuid,account_ref uuid,payment_amount numeric,payment_method text,payment_notes text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_club uuid; v_payment uuid; v_row public.fee_obligations%rowtype;
begin
  select club_id into v_club from public.fee_obligations where id=obligation_ref;
  if v_club is null then raise exception 'Quota não encontrada.'; end if;
  v_payment:=public.register_fee_payment_v1(v_club,obligation_ref,payment_amount,payment_method,payment_notes);
  select * into v_row from public.fee_obligations where id=obligation_ref;
  return jsonb_build_object(
    'obligation_id',obligation_ref,'payment_id',v_payment,
    'paid_amount',v_row.paid_amount,'status',v_row.status
  );
end; $$;

create or replace function public.save_member_v1(
  target_club uuid,target_member uuid,p_member_number integer,p_full_name text,p_nickname text,
  p_email text,p_phone text,p_status text,p_birth_date date,p_joined_at date,
  p_prospect_joined_at date,p_full_colors_at date,p_notes text
) returns uuid language plpgsql security definer set search_path=public as $$
declare result_id uuid;
begin
  if not public.has_club_permission(target_club,'manageMembers') then raise exception 'Sem autorização.'; end if;
  if target_member is null then
    insert into public.members(
      club_id,member_number,full_name,nickname,email,phone,status,birth_date,
      joined_at,prospect_joined_at,full_colors_at,notes
    ) values(
      target_club,p_member_number,p_full_name,p_nickname,p_email,p_phone,
      p_status::public.member_status,p_birth_date,p_joined_at,p_prospect_joined_at,p_full_colors_at,p_notes
    ) returning id into result_id;
  else
    update public.members set
      member_number=p_member_number,full_name=p_full_name,nickname=p_nickname,email=p_email,
      phone=p_phone,status=p_status::public.member_status,birth_date=p_birth_date,joined_at=p_joined_at,
      prospect_joined_at=p_prospect_joined_at,full_colors_at=p_full_colors_at,notes=p_notes,updated_at=now()
    where id=target_member and club_id=target_club returning id into result_id;
  end if;
  if result_id is null then raise exception 'Não foi possível guardar o membro.'; end if;
  return result_id;
end; $$;

create or replace function public.update_member_complete(
  target_member uuid,target_club uuid,new_member_number integer,new_full_name text,new_nickname text,
  new_email text,new_phone text,new_status public.member_status,new_birth_date date,new_joined_at date,
  new_prospect_joined_at date,new_full_colors_at date,new_notes text
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem autorização para editar membros.';
  end if;
  update public.members set
    member_number=new_member_number,full_name=new_full_name,nickname=new_nickname,
    email=new_email,phone=new_phone,status=new_status,birth_date=new_birth_date,
    joined_at=new_joined_at,prospect_joined_at=new_prospect_joined_at,
    full_colors_at=new_full_colors_at,notes=new_notes,updated_at=now()
  where id=target_member and club_id=target_club;
  if not found then raise exception 'Membro não encontrado.'; end if;
end; $$;

create or replace function public.create_member_with_position(
  target_club uuid,new_member_number integer,new_full_name text,new_nickname text,
  new_email text,new_phone text,new_joined_at date,position_ref uuid
) returns uuid language plpgsql security definer set search_path=public as $$
declare member_id uuid;
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem autorização para criar membros.';
  end if;
  insert into public.members(
    club_id,member_number,full_name,nickname,email,phone,joined_at,status
  ) values(
    target_club,new_member_number,new_full_name,new_nickname,new_email,new_phone,new_joined_at,'active'
  ) returning id into member_id;
  if position_ref is not null then
    insert into public.member_positions(club_id,member_id,position_id,is_primary,starts_at)
    values(target_club,member_id,position_ref,true,new_joined_at);
  end if;
  return member_id;
end; $$;
