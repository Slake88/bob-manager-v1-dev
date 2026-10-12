begin;

-- Trigger functions are invoked by PostgreSQL triggers, not through the Data API.
revoke all on function public.enforce_event_capacity_floor_v1()
  from public, anon, authenticated;
revoke all on function public.enforce_event_capacity_seat_v1()
  from public, anon, authenticated;

-- Keep authenticated RPC behavior and manageLottery checks unchanged. This
-- replacement adds an explicit null-auth guard before the existing permission check.
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
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;
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

revoke all on function public.reverse_euromillions_draw_payment_v1(uuid,uuid,text)
  from public, anon;
grant execute on function public.reverse_euromillions_draw_payment_v1(uuid,uuid,text)
  to authenticated;

revoke all on function public.reverse_euromillions_fine_payment_v1(uuid,uuid,text)
  from public, anon;
grant execute on function public.reverse_euromillions_fine_payment_v1(uuid,uuid,text)
  to authenticated;

revoke all on function public.reverse_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)
  from public, anon;
grant execute on function public.reverse_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)
  to authenticated;

revoke all on function public.reverse_euromillions_prize_receipt_v1(uuid,uuid,text)
  from public, anon;
grant execute on function public.reverse_euromillions_prize_receipt_v1(uuid,uuid,text)
  to authenticated;

revoke all on function public.register_euromillions_month_fine_payment_v1(uuid,uuid,integer,integer,text)
  from public, anon;
grant execute on function public.register_euromillions_month_fine_payment_v1(uuid,uuid,integer,integer,text)
  to authenticated;

commit;
