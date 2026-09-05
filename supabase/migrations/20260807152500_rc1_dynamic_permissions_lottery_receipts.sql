create or replace function public.register_euromillions_prize_receipt_v1(
  target_club uuid,p_prize uuid,p_amount numeric default null,p_payment_method text default null
) returns numeric language plpgsql security definer set search_path=public as $$
declare
  pr public.euromillions_prizes%rowtype;
  remaining numeric; received numeric; acc uuid; tx uuid; member_name text;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para receber prémios.';
  end if;
  select * into pr from public.euromillions_prizes
  where id=p_prize and club_id=target_club for update;
  if pr.id is null then raise exception 'Prémio não encontrado.'; end if;
  select m.full_name into member_name
  from public.euromillions_players p join public.members m on m.id=p.member_id
  where p.id=pr.player_id;
  remaining:=greatest(pr.prize_amount-pr.received_amount,0);
  if remaining<=0 then raise exception 'Este prémio já está totalmente recebido.'; end if;
  received:=case when p_amount is null then remaining else least(p_amount,remaining) end;
  if received<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,
    'Prémio Euromilhões - '||coalesce(member_name,'Jogador'),
    received,p_payment_method,'euromillions_prize',pr.id,auth.uid()
  ) returning id into tx;
  update public.euromillions_prizes set
    received_amount=received_amount+received,
    received_at=case when received_amount+received>=prize_amount then now() else received_at end,
    payment_method=p_payment_method,transaction_id=tx
  where id=pr.id;
  return received;
end; $$;

create or replace function public.register_euromillions_manual_prize_v1(
  target_club uuid,p_result uuid,p_player uuid,p_amount numeric,
  p_payment_method text default null,p_category integer default 13
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  prize_id uuid; acc uuid; tx uuid; member_name text; hit_n int:=0; hit_s int:=0;
begin
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para registar prémios.';
  end if;
  if p_amount<=0 then raise exception 'O valor do prémio deve ser superior a zero.'; end if;
  if p_category<1 or p_category>13 then raise exception 'Categoria de prémio inválida.'; end if;
  if not exists(select 1 from public.euromillions_results where id=p_result and club_id=target_club) then
    raise exception 'Sorteio não encontrado.';
  end if;
  select m.full_name into member_name
  from public.euromillions_players p join public.members m on m.id=p.member_id
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
    club_id,result_id,player_id,category,matched_numbers,matched_stars,
    prize_amount,received_amount,received_at,payment_method
  ) values(
    target_club,p_result,p_player,p_category,coalesce(hit_n,0),coalesce(hit_s,0),
    p_amount,p_amount,now(),p_payment_method
  )
  on conflict(result_id,player_id) do update set
    category=excluded.category,
    matched_numbers=excluded.matched_numbers,
    matched_stars=excluded.matched_stars,
    prize_amount=public.euromillions_prizes.prize_amount+excluded.prize_amount,
    received_amount=public.euromillions_prizes.received_amount+excluded.received_amount,
    received_at=now(),payment_method=excluded.payment_method
  returning id into prize_id;
  select id into acc from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    source_type,source_id,created_by
  ) values(
    target_club,'income',acc,current_date,'Prémio Euromilhões - '||member_name,
    p_amount,p_payment_method,'euromillions_prize_manual',prize_id,auth.uid()
  ) returning id into tx;
  update public.euromillions_prizes set transaction_id=tx where id=prize_id;
  return prize_id;
end; $$;

create or replace function public.register_euromillions_payment_v1(
  target_club uuid,participation_id uuid,payment_amount numeric,p_payment_method text
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  p public.euromillions_participations%rowtype;
  draw_club uuid; target_account uuid; new_transaction uuid;
begin
  if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem autorização.'; end if;
  if payment_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select ep.* into p from public.euromillions_participations ep
  where ep.id=participation_id for update;
  if p.id is null then raise exception 'Participação não encontrada.'; end if;
  select club_id into draw_club from public.euromillions_draws where id=p.draw_id;
  if draw_club is distinct from target_club then raise exception 'Participação inválida.'; end if;
  if payment_amount>p.balance then raise exception 'O pagamento excede o saldo pendente.'; end if;
  select id into target_account from public.treasury_accounts
  where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if target_account is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(
    club_id,kind,account_id,transaction_date,description,amount,payment_method,
    source_type,source_id,created_by
  ) values(
    target_club,'income',target_account,current_date,'Pagamento Euromilhões',
    payment_amount,p_payment_method,'euromillions_participation',participation_id,auth.uid()
  ) returning id into new_transaction;
  update public.euromillions_participations set
    paid_amount=paid_amount+payment_amount,
    balance=greatest(balance-payment_amount,0),
    paid=(balance-payment_amount<=0),
    paid_at=case when balance-payment_amount<=0 then now() else paid_at end,
    payment_method=p_payment_method,transaction_id=new_transaction
  where id=participation_id;
  return new_transaction;
end; $$;
