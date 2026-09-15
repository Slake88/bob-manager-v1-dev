-- Commit 6: Euromilhões passa de custo semanal para custo por sorteio.
-- A migration já foi validada/aplicada no Supabase real.
alter table public.euromillions_weekly_charges rename to euromillions_draw_charges;
alter table public.euromillions_draw_charges add column if not exists draw_date date;
alter table public.euromillions_draw_charges drop constraint if exists euromillions_weekly_charges_club_id_player_id_week_start_key;
alter table public.euromillions_draw_charges drop constraint if exists euromillions_draw_charges_club_id_player_id_week_start_key;

insert into public.club_settings (club_id,key,value)
select club_id,'euromillions_draw_amount',to_char(greatest(value::numeric / 2,0.01),'FM999999990.00')
from public.club_settings where key='euromillions_weekly_amount'
on conflict (club_id,key) do nothing;
insert into public.club_settings (club_id,key,value)
select c.id,'euromillions_draw_amount','2.20' from public.clubs c
where not exists (select 1 from public.club_settings s where s.club_id=c.id and s.key='euromillions_draw_amount');

update public.euromillions_draw_charges c
set draw_date=c.week_start+1, amount=round(c.amount/2,2), paid_amount=round(c.paid_amount/2,2)
where c.draw_date is null;

insert into public.euromillions_draw_charges
(club_id,player_id,week_start,draw_date,amount,paid_amount,paid_at,payment_method,transaction_id,created_at,created_by,updated_at,updated_by)
select c.club_id,c.player_id,c.week_start,c.week_start+4,c.amount,c.paid_amount,c.paid_at,c.payment_method,c.transaction_id,c.created_at,c.created_by,c.updated_at,c.updated_by
from public.euromillions_draw_charges c
where c.draw_date=c.week_start+1
and not exists (select 1 from public.euromillions_draw_charges x where x.club_id=c.club_id and x.player_id=c.player_id and x.draw_date=c.week_start+4);

alter table public.euromillions_draw_charges alter column draw_date set not null;
create unique index if not exists euromillions_draw_charges_club_player_draw_uidx on public.euromillions_draw_charges(club_id,player_id,draw_date);
create index if not exists euromillions_draw_charges_month_idx on public.euromillions_draw_charges(club_id,draw_date,player_id);

create or replace function public.generate_euromillions_charges_v1(target_club uuid,p_year int,p_month int)
returns void language plpgsql security definer set search_path=public as $$
declare v_amount numeric; d date; monday date;
begin
 if not public.has_club_access(target_club) then raise exception 'Sem acesso ao clube.'; end if;
 perform public.sync_euromillions_players_v1(target_club);
 select coalesce((select value::numeric from public.club_settings where club_id=target_club and key='euromillions_draw_amount'),2.20) into v_amount;
 d:=make_date(p_year,p_month,1);
 while extract(month from d)=p_month loop
  if extract(isodow from d) in (2,5) then
   monday:=d-(extract(isodow from d)::int-1);
   insert into public.euromillions_draw_charges(club_id,player_id,week_start,draw_date,amount)
   select target_club,p.id,monday,d,v_amount from public.euromillions_players p where p.club_id=target_club and p.status='active'
   on conflict (club_id,player_id,draw_date) do nothing;
  end if;
  d:=d+1;
 end loop;
end; $$;

create or replace function public.register_euromillions_draw_payment_v1(target_club uuid,p_charge uuid,p_payment_method text default null)
returns void language plpgsql security definer set search_path=public as $$
declare c public.euromillions_draw_charges%rowtype; acc uuid; tx uuid; remaining numeric;
begin
 if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem permissão para registar pagamentos.'; end if;
 select * into c from public.euromillions_draw_charges where id=p_charge and club_id=target_club for update;
 if c.id is null then raise exception 'Cobrança não encontrada.'; end if;
 remaining:=greatest(c.amount-c.paid_amount,0); if remaining=0 then return; end if;
 select id into acc from public.treasury_accounts where club_id=target_club and lower(name)=lower('Euromilhões') and active=true limit 1;
 if acc is null then raise exception 'Conta Euromilhões não encontrada.'; end if;
 insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
 values(target_club,'income',acc,current_date,'Pagamento Euromilhões - sorteio '||to_char(c.draw_date,'DD/MM/YYYY'),remaining,p_payment_method,'euromillions_draw_charge',c.id,auth.uid()) returning id into tx;
 update public.euromillions_draw_charges set paid_amount=amount,paid_at=now(),payment_method=p_payment_method,transaction_id=tx where id=c.id;
end; $$;

create or replace function public.register_euromillions_month_payment_v1(target_club uuid,p_player uuid,p_year int,p_month int,p_payment_method text default null)
returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
 if not public.has_club_permission(target_club,'manageLottery') then raise exception 'Sem permissão para registar pagamentos.'; end if;
 perform public.generate_euromillions_charges_v1(target_club,p_year,p_month);
 for r in select id from public.euromillions_draw_charges where club_id=target_club and player_id=p_player and extract(year from draw_date)=p_year and extract(month from draw_date)=p_month and paid_amount<amount order by draw_date loop
  perform public.register_euromillions_draw_payment_v1(target_club,r.id,p_payment_method);
 end loop;
end; $$;

drop function if exists public.register_euromillions_week_payment_v1(uuid,uuid,text);
grant execute on function public.register_euromillions_draw_payment_v1(uuid,uuid,text) to authenticated;
grant execute on function public.generate_euromillions_charges_v1(uuid,int,int) to authenticated;
grant execute on function public.register_euromillions_month_payment_v1(uuid,uuid,int,int,text) to authenticated;
alter policy euromillions_charges_read on public.euromillions_draw_charges rename to euromillions_draw_charges_read;
