create or replace function public.asset_maintenance_v1(target_club uuid,p_asset uuid,p_type text,p_date date,p_description text default null,p_cost numeric default 0,p_supplier text default null,p_next_due date default null,p_account uuid default null,p_payment_method text default null,p_post_financial boolean default false)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_name text; v_tx uuid; v_account uuid; begin
if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
select name into v_name from public.inventory_assets where id=p_asset and club_id=target_club and active=true for update;
if v_name is null then raise exception 'Bem patrimonial inválido.'; end if;
if p_type not in ('maintenance','inspection','repair') then raise exception 'Tipo de intervenção inválido.'; end if;
if p_post_financial and coalesce(p_cost,0)>0 then
  if p_account is not null then select id into v_account from public.treasury_accounts where id=p_account and club_id=target_club and active=true;
  else select id into v_account from public.treasury_accounts where club_id=target_club and active=true and lower(name)='caixa' limit 1; end if;
  if v_account is null then raise exception 'Conta financeira inválida.'; end if;
  insert into public.treasury_transactions(club_id,kind,account_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
  values(target_club,'expense',v_account,p_date,'Património - '||v_name,coalesce(p_cost,0),p_payment_method,'asset_maintenance',p_asset,auth.uid()) returning id into v_tx;
end if;
insert into public.asset_maintenance(club_id,asset_id,maintenance_date,maintenance_type,description,cost,supplier,next_due_date,account_id,payment_method,treasury_transaction_id,created_by)
values(target_club,p_asset,p_date,p_type,nullif(trim(coalesce(p_description,'')),''),coalesce(p_cost,0),nullif(trim(coalesce(p_supplier,'')),''),p_next_due,v_account,p_payment_method,v_tx,auth.uid()) returning id into v_id;
if p_type='inspection' then update public.inventory_assets set last_inspection_at=p_date,next_inspection_at=p_next_due,updated_at=now() where id=p_asset;
else update public.inventory_assets set last_maintenance_at=p_date,next_maintenance_at=p_next_due,condition=case when condition='maintenance' then 'good' else condition end,updated_at=now() where id=p_asset; end if;
insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
values(target_club,p_asset,p_type,case p_type when 'inspection' then 'Inspeção registada' when 'repair' then 'Reparação registada' else 'Manutenção registada' end,nullif(trim(coalesce(p_description,'')),''),jsonb_build_object('maintenance_id',v_id,'cost',coalesce(p_cost,0),'next_due',p_next_due),auth.uid());
return v_id; end; $$;
grant execute on function public.asset_maintenance_v1(uuid,uuid,text,date,text,numeric,text,date,uuid,text,boolean) to authenticated;
