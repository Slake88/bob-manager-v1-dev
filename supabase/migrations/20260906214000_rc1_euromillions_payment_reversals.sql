create or replace function public.reverse_euromillions_draw_payment_v1(
  target_club uuid,
  p_charge uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  c public.euromillions_draw_charges%rowtype;
  tx public.treasury_transactions%rowtype;
  reversal_id uuid;
  old_data jsonb;
  new_data jsonb;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para reverter pagamentos.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Indica o motivo da reversão.';
  end if;

  select * into c
  from public.euromillions_draw_charges
  where id=p_charge and club_id=target_club
  for update;

  if c.id is null then
    raise exception 'Cobrança não encontrada.';
  end if;
  if coalesce(c.paid_amount,0) <= 0 then
    raise exception 'Este sorteio não tem pagamento por reverter.';
  end if;

  old_data := to_jsonb(c);

  select t.* into tx
  from public.treasury_transactions t
  where t.club_id=target_club
    and t.id=c.transaction_id
    and t.kind='income'
    and t.source_type='euromillions_draw_charge'
    and not exists (
      select 1 from public.treasury_transactions r
      where r.club_id=target_club and r.reversal_of=t.id
    )
  for update;

  if tx.id is null then
    select t.* into tx
    from public.treasury_transactions t
    where t.club_id=target_club
      and t.source_id=c.id
      and t.kind='income'
      and t.source_type='euromillions_draw_charge'
      and not exists (
        select 1 from public.treasury_transactions r
        where r.club_id=target_club and r.reversal_of=t.id
      )
    order by t.created_at desc, t.id desc
    limit 1
    for update;
  end if;

  if tx.id is null then
    raise exception 'Não foi encontrado o movimento financeiro deste pagamento.';
  end if;
  if abs(tx.amount-c.paid_amount) > 0.005 then
    raise exception 'O movimento financeiro não coincide com o valor pago.';
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,
    payment_method,notes,source_type,source_id,reversal_of,created_by
  ) values (
    target_club,'expense',tx.account_id,current_date,
    'Reversão — '||tx.description,tx.amount,
    tx.payment_method,trim(p_reason),'euromillions_draw_charge_reversal',c.id,tx.id,auth.uid()
  ) returning id into reversal_id;

  update public.euromillions_draw_charges
  set paid_amount=0,
      paid_at=null,
      payment_method=null,
      transaction_id=null,
      updated_at=now(),
      updated_by=auth.uid()
  where id=c.id;

  select to_jsonb(x) into new_data
  from public.euromillions_draw_charges x
  where x.id=c.id;

  perform public.audit_event(
    target_club,
    'reverse_euromillions_draw_payment',
    'euromillions_draw_charge',
    c.id::text,
    old_data,
    new_data,
    trim(p_reason)
  );

  return reversal_id;
end;
$function$;

create or replace function public.reverse_euromillions_month_payment_v1(
  target_club uuid,
  p_player uuid,
  p_year integer,
  p_month integer,
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  reversed_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para reverter pagamentos.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Indica o motivo da reversão.';
  end if;

  for r in
    select id
    from public.euromillions_draw_charges
    where club_id=target_club
      and player_id=p_player
      and extract(year from draw_date)=p_year
      and extract(month from draw_date)=p_month
      and paid_amount>0
    order by draw_date
  loop
    perform public.reverse_euromillions_draw_payment_v1(
      target_club,
      r.id,
      trim(p_reason)
    );
    reversed_count := reversed_count + 1;
  end loop;

  if reversed_count=0 then
    raise exception 'Não existem pagamentos deste mês por reverter.';
  end if;

  return reversed_count;
end;
$function$;

create or replace function public.register_euromillions_month_fine_payment_v1(
  target_club uuid,
  p_player uuid,
  p_year integer,
  p_month integer,
  p_payment_method text default null
)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  outstanding numeric := 0;
  acc uuid;
  tx uuid;
  member_name text;
  has_partial boolean := false;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para receber multas.';
  end if;

  select m.full_name into member_name
  from public.euromillions_players p
  join public.members m on m.id=p.member_id
  where p.id=p_player and p.club_id=target_club;

  if member_name is null then
    raise exception 'Jogador não encontrado.';
  end if;

  select
    coalesce(sum(greatest(f.fine_amount-f.paid_amount,0)),0),
    coalesce(bool_or(f.paid_amount>0 and f.paid_amount<f.fine_amount),false)
  into outstanding, has_partial
  from public.euromillions_fines f
  join public.euromillions_results r on r.id=f.result_id
  where f.club_id=target_club
    and f.player_id=p_player
    and extract(year from r.draw_date)=p_year
    and extract(month from r.draw_date)=p_month;

  if has_partial then
    raise exception 'Existem multas parcialmente pagas neste mês. Regulariza-as individualmente antes de usar o pagamento mensal.';
  end if;
  if outstanding<=0 then
    raise exception 'Este jogador não tem multas deste mês em dívida.';
  end if;

  select id into acc
  from public.treasury_accounts
  where club_id=target_club
    and lower(name)=lower('Euromilhões - Multas')
    and active=true
  limit 1;

  if acc is null then
    raise exception 'Conta Euromilhões - Multas não encontrada.';
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,
    payment_method,source_type,source_id,created_by
  ) values (
    target_club,'income',acc,current_date,
    'Pagamento multas Euromilhões - '||member_name||' - '||lpad(p_month::text,2,'0')||'/'||p_year,
    outstanding,p_payment_method,'euromillions_fine_payment_month',p_player,auth.uid()
  ) returning id into tx;

  update public.euromillions_fines f
  set paid_amount=f.fine_amount,
      paid_at=now(),
      payment_method=p_payment_method,
      transaction_id=tx,
      updated_at=now(),
      updated_by=auth.uid()
  from public.euromillions_results r
  where r.id=f.result_id
    and f.club_id=target_club
    and f.player_id=p_player
    and extract(year from r.draw_date)=p_year
    and extract(month from r.draw_date)=p_month
    and f.paid_amount<f.fine_amount;

  perform public.audit_event(
    target_club,
    'register_euromillions_month_fine_payment',
    'euromillions_fine_payment',
    tx::text,
    null,
    jsonb_build_object(
      'player_id',p_player,
      'year',p_year,
      'month',p_month,
      'amount',outstanding,
      'transaction_id',tx
    ),
    null
  );

  return outstanding;
end;
$function$;

create or replace function public.reverse_euromillions_fine_payment_v1(
  target_club uuid,
  p_transaction uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  tx public.treasury_transactions%rowtype;
  reversal_id uuid;
  linked_total numeric := 0;
  linked_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para reverter multas.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Indica o motivo da reversão.';
  end if;

  select t.* into tx
  from public.treasury_transactions t
  where t.id=p_transaction
    and t.club_id=target_club
    and t.kind='income'
    and t.source_type in ('euromillions_fine_payment','euromillions_fine_payment_month')
  for update;

  if tx.id is null then
    raise exception 'Pagamento de multas não encontrado.';
  end if;
  if exists (
    select 1 from public.treasury_transactions r
    where r.club_id=target_club and r.reversal_of=tx.id
  ) then
    raise exception 'Este pagamento já foi revertido.';
  end if;

  select coalesce(sum(f.paid_amount),0), count(*)
  into linked_total, linked_count
  from public.euromillions_fines f
  where f.club_id=target_club
    and f.transaction_id=tx.id
    and f.paid_amount>0;

  if linked_count=0 then
    raise exception 'Não existem multas associadas a este movimento.';
  end if;
  if abs(linked_total-tx.amount) > 0.005 then
    raise exception 'As multas associadas não coincidem com o movimento financeiro; reversão bloqueada por segurança.';
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,
    payment_method,notes,source_type,source_id,reversal_of,created_by
  ) values (
    target_club,'expense',tx.account_id,current_date,
    'Reversão — '||tx.description,tx.amount,
    tx.payment_method,trim(p_reason),'euromillions_fine_payment_reversal',tx.source_id,tx.id,auth.uid()
  ) returning id into reversal_id;

  update public.euromillions_fines
  set paid_amount=0,
      paid_at=null,
      payment_method=null,
      transaction_id=null,
      updated_at=now(),
      updated_by=auth.uid()
  where club_id=target_club
    and transaction_id=tx.id;

  perform public.audit_event(
    target_club,
    'reverse_euromillions_fine_payment',
    'euromillions_fine_payment',
    tx.id::text,
    to_jsonb(tx),
    jsonb_build_object('reversal_transaction_id',reversal_id),
    trim(p_reason)
  );

  return reversal_id;
end;
$function$;
