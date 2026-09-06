create or replace function public.reverse_euromillions_prize_receipt_v1(
  target_club uuid,
  p_prize uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  pr public.euromillions_prizes%rowtype;
  old_pr jsonb;
  new_pr jsonb;
  tx record;
  reversal_id uuid;
  first_reversal uuid;
  reversed_total numeric := 0;
  hit_n int := 0;
  hit_s int := 0;
  expected_cat int;
  expected_prize numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;
  if not public.has_club_permission(target_club,'manageLottery') then
    raise exception 'Sem permissão para reverter prémios.';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'Indica o motivo da reversão.';
  end if;

  select * into pr
  from public.euromillions_prizes
  where id=p_prize and club_id=target_club
  for update;

  if pr.id is null then
    raise exception 'Prémio não encontrado.';
  end if;
  if coalesce(pr.received_amount,0) <= 0 then
    raise exception 'Este prémio não tem recebimentos por reverter.';
  end if;

  old_pr := to_jsonb(pr);

  for tx in
    select t.*
    from public.treasury_transactions t
    where t.club_id=target_club
      and t.source_id=pr.id
      and t.source_type in ('euromillions_prize','euromillions_prize_manual')
      and t.kind='income'
      and not exists (
        select 1
        from public.treasury_transactions r
        where r.club_id=target_club and r.reversal_of=t.id
      )
    order by t.created_at, t.id
    for update
  loop
    insert into public.treasury_transactions(
      club_id,kind,account_id,transaction_date,description,amount,
      payment_method,notes,source_type,source_id,reversal_of,created_by
    ) values (
      target_club,'expense',tx.account_id,current_date,
      'Reversão — '||tx.description,tx.amount,
      tx.payment_method,trim(p_reason),'euromillions_prize_reversal',pr.id,tx.id,auth.uid()
    ) returning id into reversal_id;

    if first_reversal is null then first_reversal := reversal_id; end if;
    reversed_total := reversed_total + tx.amount;
  end loop;

  if reversed_total <= 0 then
    raise exception 'Não foi encontrado o movimento financeiro do prémio para reverter.';
  end if;
  if abs(reversed_total - pr.received_amount) > 0.005 then
    raise exception 'Os movimentos financeiros do prémio não coincidem com o valor recebido.';
  end if;

  select
    (select count(*) from unnest(p.numbers) n where n=any(r.numbers)),
    (select count(*) from unnest(p.stars) s where s=any(r.stars))
  into hit_n, hit_s
  from public.euromillions_players p
  join public.euromillions_results r on r.id=pr.result_id
  where p.id=pr.player_id and p.club_id=target_club and r.club_id=target_club;

  expected_cat := public.euromillions_prize_category_v1(coalesce(hit_n,0),coalesce(hit_s,0));
  if expected_cat is not null then
    select coalesce((r.prize_table->>expected_cat::text)::numeric,0)
      into expected_prize
    from public.euromillions_results r
    where r.id=pr.result_id and r.club_id=target_club;
  end if;

  if expected_cat is null or coalesce(expected_prize,0) <= 0 then
    delete from public.euromillions_prizes where id=pr.id;
    new_pr := null;
  else
    update public.euromillions_prizes
    set category=expected_cat,
        matched_numbers=coalesce(hit_n,0),
        matched_stars=coalesce(hit_s,0),
        prize_amount=expected_prize,
        received_amount=0,
        received_at=null,
        payment_method=null,
        transaction_id=null,
        updated_at=now(),
        updated_by=auth.uid()
    where id=pr.id
    returning to_jsonb(public.euromillions_prizes.*) into new_pr;
  end if;

  perform public.audit_event(
    target_club,
    'reverse_euromillions_prize_receipt',
    'euromillions_prize',
    pr.id::text,
    old_pr,
    new_pr,
    trim(p_reason)
  );

  return first_reversal;
end;
$function$;
