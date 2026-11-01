create or replace function public.dashboard_summary_rc1(target_club uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  can_financial boolean;
  result jsonb;
  members_count integer:=0;
  prospects_count integer:=0;
  outstanding numeric:=0;
  overdue_count integer:=0;
  open_events_count integer:=0;
  low_stock_count integer:=0;
  expiring_documents_count integer:=0;
  unread_announcements_count integer:=0;
  total_balance numeric:=0;
  monthly_income numeric:=0;
  monthly_expense numeric:=0;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  can_financial:=public.has_club_permission(target_club,'viewTreasury');

  select count(*) filter(where status::text not in ('former','deceased')),
         count(*) filter(where status::text='prospect')
  into members_count,prospects_count
  from public.members where club_id=target_club;

  select coalesce(sum(greatest(amount-paid_amount,0)),0),
         count(*) filter(where greatest(amount-paid_amount,0)>0 and due_date<current_date)
  into outstanding,overdue_count
  from public.fee_obligations where club_id=target_club;

  select count(*) into open_events_count
  from public.events where club_id=target_club and status::text not in ('completed','cancelled','archived');

  select count(*) into low_stock_count
  from public.products where club_id=target_club and active=true
    and (current_stock-reserved_stock)<=minimum_stock;

  select count(*) into expiring_documents_count
  from public.documents where club_id=target_club and expires_at between current_date and current_date+30;

  select count(*) into unread_announcements_count
  from public.announcements a
  where a.club_id=target_club
    and a.requires_acknowledgement=true
    and a.published_at<=now()
    and (a.expires_at is null or a.expires_at>now())
    and not exists(
      select 1 from public.announcement_acknowledgements aa
      where aa.announcement_id=a.id and aa.profile_id=auth.uid()
    );

  if can_financial then
    select coalesce(sum(
      a.opening_balance
      +coalesce((select sum(case when t.kind::text='income' then t.amount when t.kind::text in ('expense','transfer') then -t.amount else 0 end)
                 from public.treasury_transactions t where t.club_id=target_club and t.account_id=a.id),0)
      +coalesce((select sum(t.amount) from public.treasury_transactions t
                 where t.club_id=target_club and t.kind::text='transfer' and t.destination_account_id=a.id),0)
    ),0)
    into total_balance
    from public.treasury_accounts a where a.club_id=target_club and a.active=true;

    select coalesce(sum(amount) filter(where kind::text='income'),0),
           coalesce(sum(amount) filter(where kind::text='expense'),0)
    into monthly_income,monthly_expense
    from public.treasury_transactions
    where club_id=target_club
      and date_trunc('month',transaction_date::timestamp)=date_trunc('month',current_date::timestamp);
  end if;

  result:=jsonb_build_object(
    'members',members_count,'prospects',prospects_count,
    'total_balance',case when can_financial then total_balance else 0 end,
    'fee_outstanding',outstanding,'overdue_fees',overdue_count,
    'open_events',open_events_count,'low_stock',low_stock_count,
    'expiring_documents',expiring_documents_count,
    'unread_announcements',unread_announcements_count,
    'pending_approvals',0,
    'monthly_income',case when can_financial then monthly_income else 0 end,
    'monthly_expense',case when can_financial then monthly_expense else 0 end,
    'can_view_financial',can_financial
  );
  return result;
end; $$;

create or replace function public.generate_monthly_fees(target_club uuid,target_year integer,plan_ref uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare plan_row public.fee_plans%rowtype; inserted_count integer;
begin
  if not public.has_club_permission(target_club,'manageFees') then
    raise exception 'Sem autorização para gerar quotas.';
  end if;
  select * into plan_row from public.fee_plans
  where id=plan_ref and club_id=target_club and active=true;
  if not found then raise exception 'Plano de quotas não encontrado.'; end if;

  insert into public.fee_obligations(
    club_id,member_id,fee_plan_id,reference_year,reference_month,due_date,amount,status
  )
  select target_club,m.id,plan_row.id,target_year,month_number,
         make_date(target_year,month_number,1)+(coalesce(plan_row.due_day,1)-1),
         plan_row.amount,'pending'
  from public.members m
  cross join generate_series(1,12) as month_number
  where m.club_id=target_club and m.status='active'
  on conflict(club_id,member_id,reference_year,reference_month) do nothing;
  get diagnostics inserted_count=row_count;
  return inserted_count;
end; $$;

create or replace function public.ensure_euromillions_open_draw_v1(target_club uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare result_id uuid; current_week integer:=extract(week from current_date)::integer;
begin
  if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem autorização.'; end if;
  select id into result_id from public.euromillions_draws
  where club_id=target_club and status='open' order by created_at desc limit 1;
  if result_id is null then
    insert into public.euromillions_draws(club_id,week,start_date,end_date,unit_cost,total_bet,prize,status)
    values(target_club,current_week,current_date,current_date+6,0,0,0,'open')
    returning id into result_id;
  end if;
  return result_id;
end; $$;

create or replace function public.process_euromillions_result_v1(
  target_club uuid,p_draw_date date,p_numbers integer[],p_stars integer[]
) returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid; fine_unit numeric; p record; mn int; ms int;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para processar sorteios.';
  end if;
  if cardinality(p_numbers)<>5 or cardinality(p_stars)<>2 then raise exception 'Resultado inválido.'; end if;
  insert into public.euromillions_results(club_id,draw_date,numbers,stars,created_by)
  values(target_club,p_draw_date,p_numbers,p_stars,auth.uid())
  on conflict(club_id,draw_date) do update set
    numbers=excluded.numbers,stars=excluded.stars,created_by=excluded.created_by
  returning id into rid;

  select coalesce((select value::numeric from public.club_settings
    where club_id=target_club and key='euromillions_fine_per_miss'),0.10)
  into fine_unit;

  for p in select * from public.euromillions_players where club_id=target_club and status='active' loop
    mn:=5-(select count(*) from unnest(p.numbers) n where n=any(p_numbers));
    ms:=2-(select count(*) from unnest(p.stars) s where s=any(p_stars));
    insert into public.euromillions_fines(
      club_id,result_id,player_id,missed_numbers,missed_stars,fine_amount
    ) values(target_club,rid,p.id,mn,ms,(mn+ms)*fine_unit)
    on conflict(result_id,player_id) do update set
      missed_numbers=excluded.missed_numbers,
      missed_stars=excluded.missed_stars,
      fine_amount=excluded.fine_amount;
  end loop;
  return rid;
end; $$;

create or replace function public.register_euromillions_week_payment_v1(
  target_club uuid,p_charge uuid,p_payment_method text default null
) returns void language plpgsql security definer set search_path=public as $$
declare c public.euromillions_weekly_charges%rowtype; acc uuid; tx uuid; remaining numeric;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para registar pagamentos.';
  end if;
  select * into c from public.euromillions_weekly_charges
  where id=p_charge and club_id=target_club for update;
  if c.id is null then raise exception 'Cobrança não encontrada.'; end if;
  remaining:=greatest(c.amount-c.paid_amount,0);
  if remaining=0 then return; end if;
  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,'Pagamento Euromilhões',remaining,
    p_payment_method,'euromillions_weekly_charge',c.id,auth.uid()
  ) returning id into tx;
  update public.euromillions_weekly_charges
  set paid_amount=amount,paid_at=now(),payment_method=p_payment_method,transaction_id=tx
  where id=c.id;
end; $$;

create or replace function public.register_euromillions_month_payment_v1(
  target_club uuid,p_player uuid,p_year int,p_month int,p_payment_method text default null
) returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para registar pagamentos.';
  end if;
  perform public.generate_euromillions_charges_v1(target_club,p_year,p_month);
  for r in
    select id from public.euromillions_weekly_charges
    where club_id=target_club and player_id=p_player
      and extract(year from week_start)=p_year
      and extract(month from week_start)=p_month
      and paid_amount<amount
    order by week_start
  loop
    perform public.register_euromillions_week_payment_v1(target_club,r.id,p_payment_method);
  end loop;
end; $$;

create or replace function public.register_euromillions_fine_payment_v1(
  target_club uuid,p_player uuid,p_amount numeric default null,p_payment_method text default null
) returns numeric language plpgsql security definer set search_path=public as $$
declare outstanding numeric; to_pay numeric; remaining numeric; r record; allocation numeric; acc uuid; tx uuid; member_name text;
begin
  if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem permissão para receber multas.'; end if;
  select m.full_name into member_name
  from public.euromillions_players p join public.members m on m.id=p.member_id
  where p.id=p_player and p.club_id=target_club;
  if member_name is null then raise exception 'Jogador não encontrado.'; end if;
  select coalesce(sum(greatest(fine_amount-paid_amount,0)),0) into outstanding
  from public.euromillions_fines where club_id=target_club and player_id=p_player;
  if outstanding<=0 then raise exception 'Este jogador não tem multas em dívida.'; end if;
  to_pay:=case when p_amount is null then outstanding else least(p_amount,outstanding) end;
  if to_pay<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões - Multas') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões - Multas não encontrada.'; end if;
  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,'Pagamento multas Euromilhões - '||member_name,
    to_pay,p_payment_method,'euromillions_fine_payment',p_player,auth.uid()
  ) returning id into tx;
  remaining:=to_pay;
  for r in
    select id,fine_amount,paid_amount from public.euromillions_fines
    where club_id=target_club and player_id=p_player and paid_amount<fine_amount
    order by created_at,id for update
  loop
    exit when remaining<=0;
    allocation:=least(remaining,r.fine_amount-r.paid_amount);
    update public.euromillions_fines set
      paid_amount=paid_amount+allocation,
      paid_at=case when paid_amount+allocation>=fine_amount then now() else paid_at end,
      payment_method=p_payment_method,transaction_id=tx
    where id=r.id;
    remaining:=remaining-allocation;
  end loop;
  return to_pay;
end; $$;

create or replace function public.inventory_operation_v1(
  target_club uuid,p_product uuid,p_operation text,p_quantity numeric,
  p_unit_price numeric default null,p_description text default null,p_payment_method text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_product public.products%rowtype;
  v_new_stock numeric; v_new_reserved numeric; v_account uuid; v_cost_center uuid;
  v_transaction uuid; v_kind public.stock_movement_kind; v_total numeric;
begin
  if p_operation='sale' then
    if not public.has_club_permission(target_club,'sellInventory') then
      raise exception 'Sem autorização para registar vendas.';
    end if;
  elsif not public.has_club_permission(target_club,'manageInventory') then
    raise exception 'Sem autorização para gerir inventário.';
  end if;
  if p_quantity<=0 then raise exception 'A quantidade deve ser superior a zero.'; end if;
  select * into v_product from public.products
  where id=p_product and club_id=target_club and active=true for update;
  if not found then raise exception 'Artigo não encontrado ou inativo.'; end if;
  v_new_stock:=v_product.current_stock;
  v_new_reserved:=v_product.reserved_stock;
  if p_operation='entry' then v_new_stock:=v_new_stock+p_quantity; v_kind:='purchase';
  elsif p_operation='adjustment_in' then v_new_stock:=v_new_stock+p_quantity; v_kind:='adjustment';
  elsif p_operation='adjustment_out' then v_new_stock:=v_new_stock-p_quantity; v_kind:='adjustment';
  elsif p_operation='reserve' then
    if v_new_stock-v_new_reserved<p_quantity then raise exception 'Stock disponível insuficiente para a reserva.'; end if;
    v_new_reserved:=v_new_reserved+p_quantity; v_kind:='transfer';
  elsif p_operation='release' then
    if v_new_reserved<p_quantity then raise exception 'Reserva insuficiente.'; end if;
    v_new_reserved:=v_new_reserved-p_quantity; v_kind:='return';
  elsif p_operation='sale' then
    if v_new_stock-v_new_reserved<p_quantity then raise exception 'Stock disponível insuficiente para a venda.'; end if;
    v_new_stock:=v_new_stock-p_quantity; v_kind:='sale';
  else raise exception 'Operação de inventário inválida.';
  end if;
  if v_new_stock<0 or v_new_reserved<0 or v_new_reserved>v_new_stock then
    raise exception 'O stock não pode ficar negativo nem abaixo do stock reservado.';
  end if;
  update public.products set current_stock=v_new_stock,reserved_stock=v_new_reserved where id=v_product.id;
  insert into public.stock_movements(club_id,product_id,kind,quantity,unit_cost,notes,created_by)
  values(
    target_club,v_product.id,v_kind,
    case when p_operation in ('adjustment_out','sale') then -p_quantity else p_quantity end,
    coalesce(p_unit_price,v_product.cost),nullif(trim(coalesce(p_description,'')),''),auth.uid()
  );
  if p_operation='sale' then
    v_total:=p_quantity*coalesce(p_unit_price,v_product.sale_price);
    select id into v_account from public.treasury_accounts
    where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
    if v_account is null then raise exception 'Conta Club House não encontrada.'; end if;
    select id into v_cost_center from public.cost_centers
    where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
    insert into public.treasury_transactions(
      club_id,kind,account_id,cost_center_id,transaction_date,description,amount,
      payment_method,source_type,source_id,created_by
    ) values(
      target_club,'income',v_account,v_cost_center,current_date,
      coalesce(nullif(trim(coalesce(p_description,'')),''),'Venda '||v_product.name),
      v_total,p_payment_method,'inventory_sale',v_product.id,auth.uid()
    ) returning id into v_transaction;
  end if;
  return jsonb_build_object(
    'product_id',v_product.id,'current_stock',v_new_stock,
    'reserved_stock',v_new_reserved,'transaction_id',v_transaction
  );
end; $$;
