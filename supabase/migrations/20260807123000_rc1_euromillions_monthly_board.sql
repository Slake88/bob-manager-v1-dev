create table if not exists public.euromillions_players (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  status text not null default 'non_player' check (status in ('active','inactive','non_player')),
  numbers integer[] not null default '{}',
  stars integer[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_id, member_id),
  check (cardinality(numbers) in (0,5)),
  check (cardinality(stars) in (0,2))
);

create table if not exists public.euromillions_weekly_charges (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  player_id uuid not null references public.euromillions_players(id) on delete cascade,
  week_start date not null,
  amount numeric(10,2) not null check (amount >= 0),
  paid_amount numeric(10,2) not null default 0 check (paid_amount >= 0),
  paid_at timestamptz,
  payment_method text,
  transaction_id uuid references public.treasury_transactions(id),
  created_at timestamptz not null default now(),
  unique (club_id, player_id, week_start)
);

create table if not exists public.euromillions_results (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  draw_date date not null,
  numbers integer[] not null,
  stars integer[] not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (club_id, draw_date),
  check (cardinality(numbers)=5),
  check (cardinality(stars)=2)
);

create table if not exists public.euromillions_fines (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  result_id uuid not null references public.euromillions_results(id) on delete cascade,
  player_id uuid not null references public.euromillions_players(id) on delete cascade,
  missed_numbers integer not null default 0,
  missed_stars integer not null default 0,
  fine_amount numeric(10,2) not null default 0,
  created_at timestamptz not null default now(),
  unique (result_id, player_id)
);

insert into public.club_settings (club_id,key,value)
select c.id,'euromillions_weekly_amount','4.40' from public.clubs c
on conflict (club_id,key) do nothing;
insert into public.club_settings (club_id,key,value)
select c.id,'euromillions_fine_per_miss','0.10' from public.clubs c
on conflict (club_id,key) do nothing;
insert into public.euromillions_players (club_id,member_id,status)
select m.club_id,m.id,'non_player' from public.members m
on conflict (club_id,member_id) do nothing;

create or replace function public.sync_euromillions_players_v1(target_club uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  insert into public.euromillions_players (club_id,member_id,status)
  select m.club_id,m.id,'non_player' from public.members m where m.club_id=target_club
  on conflict (club_id,member_id) do nothing;
end; $$;

create or replace function public.generate_euromillions_charges_v1(target_club uuid, p_year int, p_month int)
returns void language plpgsql security definer set search_path=public as $$
declare v_amount numeric; d date; monday date;
begin
  if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
  perform public.sync_euromillions_players_v1(target_club);
  select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_weekly_amount'),4.40) into v_amount;
  d := make_date(p_year,p_month,1);
  while extract(month from d)=p_month loop
    if extract(isodow from d) in (2,5) then
      monday := d - (extract(isodow from d)::int - 1);
      insert into public.euromillions_weekly_charges (club_id,player_id,week_start,amount)
      select target_club,p.id,monday,v_amount from public.euromillions_players p
      where p.club_id=target_club and p.status='active'
      on conflict (club_id,player_id,week_start) do nothing;
    end if;
    d := d + 1;
  end loop;
end; $$;

create or replace function public.register_euromillions_week_payment_v1(target_club uuid,p_charge uuid,p_payment_method text default null)
returns void language plpgsql security definer set search_path=public as $$
declare c public.euromillions_weekly_charges%rowtype; acc uuid; tx uuid; remaining numeric;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then raise exception 'Sem permissão para registar pagamentos.'; end if;
  select * into c from public.euromillions_weekly_charges where id=p_charge and club_id=target_club for update;
  if c.id is null then raise exception 'Cobrança não encontrada.'; end if;
  remaining := greatest(c.amount-c.paid_amount,0);
  if remaining=0 then return; end if;
  select id into acc from public.treasury_accounts where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
  if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
  insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
  values(target_club,'income',acc,current_date,'Pagamento Euromilhões',remaining,p_payment_method,'euromillions_weekly_charge',c.id,auth.uid()) returning id into tx;
  update public.euromillions_weekly_charges set paid_amount=amount,paid_at=now(),payment_method=p_payment_method,transaction_id=tx where id=c.id;
end; $$;

create or replace function public.register_euromillions_month_payment_v1(target_club uuid,p_player uuid,p_year int,p_month int,p_payment_method text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then raise exception 'Sem permissão para registar pagamentos.'; end if;
  perform public.generate_euromillions_charges_v1(target_club,p_year,p_month);
  for r in select id from public.euromillions_weekly_charges where club_id=target_club and player_id=p_player and extract(year from week_start)=p_year and extract(month from week_start)=p_month and paid_amount<amount order by week_start loop
    perform public.register_euromillions_week_payment_v1(target_club,r.id,p_payment_method);
  end loop;
end; $$;

create or replace function public.process_euromillions_result_v1(target_club uuid,p_draw_date date,p_numbers integer[],p_stars integer[])
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid; fine_unit numeric; p record; mn int; ms int;
begin
  if not public.has_club_role(target_club,array['treasurer','admin','super_admin']) then raise exception 'Sem permissão para processar sorteios.'; end if;
  if cardinality(p_numbers)<>5 or cardinality(p_stars)<>2 then raise exception 'Resultado inválido.'; end if;
  insert into public.euromillions_results(club_id,draw_date,numbers,stars,created_by)
  values(target_club,p_draw_date,p_numbers,p_stars,auth.uid())
  on conflict (club_id,draw_date) do update set numbers=excluded.numbers,stars=excluded.stars,created_by=excluded.created_by
  returning id into rid;
  select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_fine_per_miss'),0.10) into fine_unit;
  for p in select * from public.euromillions_players where club_id=target_club and status='active' loop
    mn := 5-(select count(*) from unnest(p.numbers) n where n=any(p_numbers));
    ms := 2-(select count(*) from unnest(p.stars) s where s=any(p_stars));
    insert into public.euromillions_fines(club_id,result_id,player_id,missed_numbers,missed_stars,fine_amount)
    values(target_club,rid,p.id,mn,ms,(mn+ms)*fine_unit)
    on conflict (result_id,player_id) do update set missed_numbers=excluded.missed_numbers,missed_stars=excluded.missed_stars,fine_amount=excluded.fine_amount;
  end loop;
  return rid;
end; $$;

alter table public.euromillions_players enable row level security;
alter table public.euromillions_weekly_charges enable row level security;
alter table public.euromillions_results enable row level security;
alter table public.euromillions_fines enable row level security;

drop policy if exists euromillions_players_read on public.euromillions_players;
create policy euromillions_players_read on public.euromillions_players for select to authenticated using (public.has_club_access(club_id));
drop policy if exists euromillions_players_manage on public.euromillions_players;
create policy euromillions_players_manage on public.euromillions_players for all to authenticated using (public.has_club_role(club_id,array['treasurer','admin','super_admin'])) with check (public.has_club_role(club_id,array['treasurer','admin','super_admin']));
drop policy if exists euromillions_charges_read on public.euromillions_weekly_charges;
create policy euromillions_charges_read on public.euromillions_weekly_charges for select to authenticated using (public.has_club_access(club_id));
drop policy if exists euromillions_results_read on public.euromillions_results;
create policy euromillions_results_read on public.euromillions_results for select to authenticated using (public.has_club_access(club_id));
drop policy if exists euromillions_fines_read on public.euromillions_fines;
create policy euromillions_fines_read on public.euromillions_fines for select to authenticated using (public.has_club_access(club_id));

grant execute on function public.sync_euromillions_players_v1(uuid) to authenticated;
grant execute on function public.generate_euromillions_charges_v1(uuid,int,int) to authenticated;
grant execute on function public.register_euromillions_week_payment_v1(uuid,uuid,text) to authenticated;
grant execute on function public.register_euromillions_month_payment_v1(uuid,uuid,int,int,text) to authenticated;
grant execute on function public.process_euromillions_result_v1(uuid,date,integer[],integer[]) to authenticated;
