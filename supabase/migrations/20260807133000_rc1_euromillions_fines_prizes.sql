alter table public.euromillions_fines
  add column if not exists paid_amount numeric(10,2) not null default 0 check (paid_amount >= 0),
  add column if not exists paid_at timestamptz,
  add column if not exists payment_method text,
  add column if not exists transaction_id uuid references public.treasury_transactions(id);

alter table public.euromillions_results
  add column if not exists official_draw_number text,
  add column if not exists prize_table jsonb not null default '{}'::jsonb,
  add column if not exists source text not null default 'manual',
  add column if not exists imported_at timestamptz;

create table if not exists public.euromillions_prizes (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  result_id uuid not null references public.euromillions_results(id) on delete cascade,
  player_id uuid not null references public.euromillions_players(id) on delete cascade,
  category integer not null check (category between 1 and 13),
  matched_numbers integer not null check (matched_numbers between 0 and 5),
  matched_stars integer not null check (matched_stars between 0 and 2),
  prize_amount numeric(14,2) not null default 0 check (prize_amount >= 0),
  received_amount numeric(14,2) not null default 0 check (received_amount >= 0),
  received_at timestamptz,
  payment_method text,
  transaction_id uuid references public.treasury_transactions(id),
  created_at timestamptz not null default now(),
  unique (result_id, player_id)
);

insert into public.treasury_accounts (
  club_id,name,account_type,opening_balance,opening_date,active,icon,allows_negative
)
select c.id,'Euromilhões - Multas','fund',0,current_date,true,'🎯',false
from public.clubs c
where not exists (
  select 1 from public.treasury_accounts a
  where a.club_id=c.id and lower(a.name)=lower('Euromilhões - Multas')
);

create or replace function public.euromillions_prize_category_v1(p_numbers int, p_stars int)
returns int language sql immutable as $$
  select case
    when p_numbers=5 and p_stars=2 then 1
    when p_numbers=5 and p_stars=1 then 2
    when p_numbers=5 and p_stars=0 then 3
    when p_numbers=4 and p_stars=2 then 4
    when p_numbers=4 and p_stars=1 then 5
    when p_numbers=3 and p_stars=2 then 6
    when p_numbers=4 and p_stars=0 then 7
    when p_numbers=2 and p_stars=2 then 8
    when p_numbers=3 and p_stars=1 then 9
    when p_numbers=3 and p_stars=0 then 10
    when p_numbers=1 and p_stars=2 then 11
    when p_numbers=2 and p_stars=1 then 12
    when p_numbers=2 and p_stars=0 then 13
    else null end;
$$;

create or replace function public.process_euromillions_official_result_v1(
  target_club uuid,
  p_draw_date date,
  p_draw_number text,
  p_numbers integer[],
  p_stars integer[],
  p_prizes jsonb default '{}'::jsonb,
  p_source text default 'official'
)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  rid uuid;
  fine_unit numeric;
  p record;
  hit_n int;
  hit_s int;
  miss_n int;
  miss_s int;
  cat int;
  prize numeric;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  if cardinality(p_numbers)<>5 or cardinality(p_stars)<>2 then raise exception 'Resultado inválido.'; end if;

  insert into public.euromillions_results(
    club_id,draw_date,numbers,stars,created_by,official_draw_number,prize_table,source,imported_at
  ) values(
    target_club,p_draw_date,p_numbers,p_stars,auth.uid(),p_draw_number,coalesce(p_prizes,'{}'::jsonb),coalesce(p_source,'official'),now()
  )
  on conflict (club_id,draw_date) do update set
    numbers=excluded.numbers,stars=excluded.stars,created_by=excluded.created_by,
    official_draw_number=excluded.official_draw_number,prize_table=excluded.prize_table,
    source=excluded.source,imported_at=excluded.imported_at
  returning id into rid;

  select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_fine_per_miss'),0.10) into fine_unit;

  for p in select * from public.euromillions_players where club_id=target_club and status='active' loop
    hit_n := (select count(*) from unnest(p.numbers) n where n=any(p_numbers));
    hit_s := (select count(*) from unnest(p.stars) s where s=any(p_stars));
    miss_n := 5-hit_n;
    miss_s := 2-hit_s;

    insert into public.euromillions_fines(club_id,result_id,player_id,missed_numbers,missed_stars,fine_amount)
    values(target_club,rid,p.id,miss_n,miss_s,(miss_n+miss_s)*fine_unit)
    on conflict (result_id,player_id) do update set
      missed_numbers=excluded.missed_numbers,missed_stars=excluded.missed_stars,fine_amount=excluded.fine_amount;

    cat := public.euromillions_prize_category_v1(hit_n,hit_s);
    if cat is not null then
      prize := coalesce((p_prizes->>cat::text)::numeric,0);
      if prize > 0 then
        insert into public.euromillions_prizes(club_id,result_id,player_id,category,matched_numbers,matched_stars,prize_amount)
        values(target_club,rid,p.id,cat,hit_n,hit_s,prize)
        on conflict (result_id,player_id) do update set
          category=excluded.category,matched_numbers=excluded.matched_numbers,
          matched_stars=excluded.matched_stars,prize_amount=excluded.prize_amount;
      else
        delete from public.euromillions_prizes where result_id=rid and player_id=p.id and received_amount=0;
      end if;
    else
      delete from public.euromillions_prizes where result_id=rid and player_id=p.id and received_amount=0;
    end if;
  end loop;
  return rid;
end; $$;

create or replace function public.register_euromillions_fine_payment_v1(
  target_club uuid,p_player uuid,p_amount numeric default null,p_payment_method text default null
)
returns numeric language plpgsql security definer set search_path=public as $$
declare outstanding numeric; to_pay numeric; remaining numeric; r record; allocation numeric; acc uuid; tx uuid;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then raise exception 'Sem permissão para receber multas.'; end if;
  select coalesce(sum(greatest(fine_amount-paid_amount,0)),0) into outstanding
  from public.euromillions_fines where club_id=target_club and player_id=p_player;
  if outstanding<=0 then raise exception 'Este jogador não tem multas em dívida.'; end if;
  to_pay := case when p_amount is null then outstanding else least(p_amount,outstanding) end;
  if to_pay<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select id into acc from public.treasury_accounts where club_id=target_club and lower(name)=lower('Euromilhões - Multas') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões - Multas não encontrada.'; end if;
  insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
  values(target_club,'income',acc,current_date,'Pagamento de multas Euromilhões',to_pay,p_payment_method,'euromillions_fine_payment',p_player,auth.uid()) returning id into tx;
  remaining := to_pay;
  for r in select id,fine_amount,paid_amount from public.euromillions_fines
    where club_id=target_club and player_id=p_player and paid_amount<fine_amount order by created_at,id for update
  loop
    exit when remaining<=0;
    allocation := least(remaining,r.fine_amount-r.paid_amount);
    update public.euromillions_fines set paid_amount=paid_amount+allocation,
      paid_at=case when paid_amount+allocation>=fine_amount then now() else paid_at end,
      payment_method=p_payment_method,transaction_id=tx where id=r.id;
    remaining := remaining-allocation;
  end loop;
  return to_pay;
end; $$;

create or replace function public.register_euromillions_prize_receipt_v1(
  target_club uuid,p_prize uuid,p_amount numeric default null,p_payment_method text default null
)
returns numeric language plpgsql security definer set search_path=public as $$
declare pr public.euromillions_prizes%rowtype; remaining numeric; received numeric; acc uuid; tx uuid;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then raise exception 'Sem permissão para receber prémios.'; end if;
  select * into pr from public.euromillions_prizes where id=p_prize and club_id=target_club for update;
  if pr.id is null then raise exception 'Prémio não encontrado.'; end if;
  remaining := greatest(pr.prize_amount-pr.received_amount,0);
  if remaining<=0 then raise exception 'Este prémio já está totalmente recebido.'; end if;
  received := case when p_amount is null then remaining else least(p_amount,remaining) end;
  if received<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
  select id into acc from public.treasury_accounts where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
  values(target_club,'income',acc,current_date,'Prémio Euromilhões',received,p_payment_method,'euromillions_prize',pr.id,auth.uid()) returning id into tx;
  update public.euromillions_prizes set received_amount=received_amount+received,
    received_at=case when received_amount+received>=prize_amount then now() else received_at end,
    payment_method=p_payment_method,transaction_id=tx where id=pr.id;
  return received;
end; $$;

alter table public.euromillions_prizes enable row level security;
drop policy if exists euromillions_prizes_read on public.euromillions_prizes;
create policy euromillions_prizes_read on public.euromillions_prizes for select to authenticated using (public.has_club_access(club_id));

grant execute on function public.process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text) to authenticated;
grant execute on function public.register_euromillions_fine_payment_v1(uuid,uuid,numeric,text) to authenticated;
grant execute on function public.register_euromillions_prize_receipt_v1(uuid,uuid,numeric,text) to authenticated;
revoke execute on function public.process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text) from anon, public;
revoke execute on function public.register_euromillions_fine_payment_v1(uuid,uuid,numeric,text) from anon, public;
revoke execute on function public.register_euromillions_prize_receipt_v1(uuid,uuid,numeric,text) from anon, public;
