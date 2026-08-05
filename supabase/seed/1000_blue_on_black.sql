insert into public.clubs(id,name,legal_name,slug,primary_color,secondary_color,timezone,currency,active,created_at,updated_at)
values('00000000-0000-0000-0000-000000000001','Blue On Black','BOBLEGACY – Associação Motociclista de Ação Solidária e Cultura Biker','blue-on-black','#0C18D2','#000000','Europe/Lisbon','EUR',true,now(),now())
on conflict(id) do update set name=excluded.name;

insert into public.club_positions(id,club_id,code,name,sort_order,active)
select gen_random_uuid(),'00000000-0000-0000-0000-000000000001',v.code,v.name,v.ord,true
from (values
 ('president','Presidente',10),('vice_president','Vice-Presidente',20),('treasurer','Tesoureiro',30),
 ('secretary','Secretário',40),('sergeant_at_arms','Sargento de Armas',50),('road_captain','Road Captain',60),
 ('prospect','Prospect',70),('member','Membro',100),('event_manager','Responsável de Eventos',110),
 ('inventory_manager','Responsável de Inventário',120),('lottery_manager','Responsável do Euromilhões',130),('administrator','Administrador',1)
) v(code,name,ord)
where not exists(select 1 from public.club_positions cp where cp.club_id='00000000-0000-0000-0000-000000000001' and cp.code=v.code);

insert into public.financial_accounts(id,club_id,name,account_type,opening_balance,opening_date,active)
select gen_random_uuid(),'00000000-0000-0000-0000-000000000001',v.name,v.typ,0,current_date,true
from (values ('Caixa','cash'),('Banco CGD','bank')) v(name,typ)
where not exists(select 1 from public.financial_accounts a where a.club_id='00000000-0000-0000-0000-000000000001' and a.name=v.name);

insert into public.funds(id,club_id,name,code,restricted,active)
select gen_random_uuid(),'00000000-0000-0000-0000-000000000001',v.name,v.code,v.restricted,true
from (values ('Quotas','fees',true),('Reserva','reserve',true),('Representação','representation',false),('Marketing','marketing',false),('Euromilhões','lottery',true)) v(name,code,restricted)
where not exists(select 1 from public.funds f where f.club_id='00000000-0000-0000-0000-000000000001' and f.code=v.code);

insert into public.cost_centers(id,club_id,name,code,active)
select gen_random_uuid(),'00000000-0000-0000-0000-000000000001',v.name,v.code,true
from (values ('Administração','admin'),('Club House','clubhouse'),('Representação','representation'),('Marketing','marketing'),('Quotas','fees'),('Euromilhões','lottery'),('Solidariedade','solidarity'),('Merchandising','merch'),('Eventos','events'),('Rock & Ride In','rock_ride')) v(name,code)
where not exists(select 1 from public.cost_centers c where c.club_id='00000000-0000-0000-0000-000000000001' and c.code=v.code);

insert into public.fee_plans(id,club_id,name,frequency,amount,due_day,active,valid_from)
select gen_random_uuid(),'00000000-0000-0000-0000-000000000001','Quota mensal','monthly',25,10,true,current_date
where not exists(select 1 from public.fee_plans where club_id='00000000-0000-0000-0000-000000000001' and name='Quota mensal');
