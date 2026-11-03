create or replace function public.register_euromillions_fine_payment_v1(
  target_club uuid,
  p_player uuid,
  p_amount numeric default null,
  p_payment_method text default null
)
returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare
  outstanding numeric;
  to_pay numeric;
  remaining numeric;
  r record;
  allocation numeric;
  acc uuid;
  tx uuid;
  member_name text;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then
    raise exception 'Sem permissão para receber multas.';
  end if;

  select m.full_name into member_name
  from public.euromillions_players p
  join public.members m on m.id=p.member_id
  where p.id=p_player and p.club_id=target_club;
  if member_name is null then raise exception 'Jogador não encontrado.'; end if;

  select coalesce(sum(greatest(fine_amount-paid_amount,0)),0) into outstanding
  from public.euromillions_fines
  where club_id=target_club and player_id=p_player;

  if outstanding<=0 then raise exception 'Este jogador não tem multas em dívida.'; end if;
  to_pay := case when p_amount is null then outstanding else least(p_amount,outstanding) end;
  if to_pay<=0 then raise exception 'O valor deve ser superior a zero.'; end if;

  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões - Multas') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões - Multas não encontrada.'; end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,
    'Pagamento multas Euromilhões - ' || member_name,
    to_pay,p_payment_method,'euromillions_fine_payment',p_player,auth.uid()
  ) returning id into tx;

  remaining := to_pay;
  for r in
    select id,fine_amount,paid_amount from public.euromillions_fines
    where club_id=target_club and player_id=p_player and paid_amount<fine_amount
    order by created_at,id for update
  loop
    exit when remaining<=0;
    allocation := least(remaining,r.fine_amount-r.paid_amount);
    update public.euromillions_fines set
      paid_amount=paid_amount+allocation,
      paid_at=case when paid_amount+allocation>=fine_amount then now() else paid_at end,
      payment_method=p_payment_method,
      transaction_id=tx
    where id=r.id;
    remaining := remaining-allocation;
  end loop;
  return to_pay;
end;
$$;

create or replace function public.register_euromillions_manual_prize_v1(
  target_club uuid,
  p_result uuid,
  p_player uuid,
  p_amount numeric,
  p_payment_method text default null,
  p_category integer default 13
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  prize_id uuid;
  acc uuid;
  tx uuid;
  member_name text;
  hit_n int := 0;
  hit_s int := 0;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then
    raise exception 'Sem permissão para registar prémios.';
  end if;
  if p_amount<=0 then raise exception 'O valor do prémio deve ser superior a zero.'; end if;
  if p_category<1 or p_category>13 then raise exception 'Categoria de prémio inválida.'; end if;

  if not exists(select 1 from public.euromillions_results where id=p_result and club_id=target_club) then
    raise exception 'Sorteio não encontrado.';
  end if;

  select m.full_name into member_name
  from public.euromillions_players p
  join public.members m on m.id=p.member_id
  where p.id=p_player and p.club_id=target_club;
  if member_name is null then raise exception 'Jogador não encontrado.'; end if;

  select
    (select count(*) from unnest(p.numbers) n where n=any(r.numbers)),
    (select count(*) from unnest(p.stars) s where s=any(r.stars))
  into hit_n,hit_s
  from public.euromillions_players p
  cross join public.euromillions_results r
  where p.id=p_player and r.id=p_result;

  insert into public.euromillions_prizes(
    club_id,result_id,player_id,category,matched_numbers,matched_stars,prize_amount,received_amount,received_at,payment_method
  ) values(
    target_club,p_result,p_player,p_category,coalesce(hit_n,0),coalesce(hit_s,0),p_amount,p_amount,now(),p_payment_method
  )
  on conflict (result_id,player_id) do update set
    category=excluded.category,
    matched_numbers=excluded.matched_numbers,
    matched_stars=excluded.matched_stars,
    prize_amount=public.euromillions_prizes.prize_amount + excluded.prize_amount,
    received_amount=public.euromillions_prizes.received_amount + excluded.received_amount,
    received_at=now(),
    payment_method=excluded.payment_method
  returning id into prize_id;

  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,
    'Prémio Euromilhões - ' || member_name,
    p_amount,p_payment_method,'euromillions_prize_manual',prize_id,auth.uid()
  ) returning id into tx;

  update public.euromillions_prizes set transaction_id=tx where id=prize_id;
  return prize_id;
end;
$$;

grant execute on function public.register_euromillions_fine_payment_v1(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.register_euromillions_manual_prize_v1(uuid,uuid,uuid,numeric,text,integer) to authenticated;
