create or replace function public.inventory_refresh_lot_status_internal_v1(target_club uuid default null)
returns integer language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  update public.stock_lots l set status=case when l.quantity<=0 then 'depleted' when l.status='quarantined' then 'quarantined' when l.expires_at is not null and l.expires_at<current_date then 'expired' else 'active' end,updated_at=now()
  where (target_club is null or l.club_id=target_club) and l.status is distinct from case when l.quantity<=0 then 'depleted' when l.status='quarantined' then 'quarantined' when l.expires_at is not null and l.expires_at<current_date then 'expired' else 'active' end;
  get diagnostics v_count=row_count; return v_count;
end $$;
revoke all on function public.inventory_refresh_lot_status_internal_v1(uuid) from public,anon,authenticated;

create or replace function public.inventory_lot_receive_v1(target_club uuid,p_product uuid,p_variant uuid,p_location uuid,p_lot_code text,p_quantity numeric,p_received_at date default current_date,p_expires_at date default null,p_unit_cost numeric default null,p_supplier text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_lot public.stock_lots%rowtype;
begin
 if not public.has_club_permission(target_club,'manageInventory') then raise exception 'Sem permissão para receber lotes.'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantidade inválida.'; end if;
 if nullif(trim(coalesce(p_lot_code,'')),'') is null then raise exception 'Indica o número/código do lote.'; end if;
 if p_expires_at is not null and p_expires_at<coalesce(p_received_at,current_date) then raise exception 'A validade não pode ser anterior à receção.'; end if;
 if p_expires_at is not null and p_expires_at<current_date then raise exception 'Não é possível receber um lote já expirado.'; end if;
 if p_unit_cost is not null and p_unit_cost<0 then raise exception 'Custo inválido.'; end if;
 if not exists(select 1 from public.products p where p.id=p_product and p.club_id=target_club and p.active=true) then raise exception 'Produto não encontrado.'; end if;
 if p_variant is not null and not exists(select 1 from public.product_variants where id=p_variant and product_id=p_product and active=true) then raise exception 'Variante inválida.'; end if;
 if not exists(select 1 from public.inventory_locations where id=p_location and club_id=target_club and active=true) then raise exception 'Localização inválida.'; end if;
 select * into v_lot from public.stock_lots l where l.club_id=target_club and l.product_id=p_product and l.variant_id is not distinct from p_variant and l.location_id=p_location and lower(l.lot_code)=lower(trim(p_lot_code)) for update;
 if found then
   if v_lot.status='quarantined' then raise exception 'O lote existente está em quarentena.'; end if;
   update public.stock_lots set initial_quantity=initial_quantity+p_quantity,quantity=quantity+p_quantity,received_at=least(received_at,coalesce(p_received_at,current_date)),expires_at=coalesce(p_expires_at,expires_at),unit_cost=coalesce(p_unit_cost,unit_cost),supplier=coalesce(nullif(trim(coalesce(p_supplier,'')),''),supplier),notes=coalesce(nullif(trim(coalesce(p_notes,'')),''),notes),status='active',updated_at=now() where id=v_lot.id returning * into v_lot;
 else
   insert into public.stock_lots(club_id,product_id,variant_id,location_id,lot_code,received_at,expires_at,initial_quantity,quantity,unit_cost,supplier,status,notes,created_by)
   values(target_club,p_product,p_variant,p_location,trim(p_lot_code),coalesce(p_received_at,current_date),p_expires_at,p_quantity,p_quantity,p_unit_cost,nullif(trim(coalesce(p_supplier,'')),''),'active',nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning * into v_lot;
 end if;
 perform public.inventory_balance_apply_internal_v1(target_club,p_product,p_variant,p_location,p_quantity,0);
 perform public.inventory_sync_aggregate_stock_v1(target_club,p_product,p_variant);
 insert into public.stock_movements(club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by,to_location_id)
 select target_club,p_product,p_variant,'purchase',p_quantity,coalesce(p_unit_cost,pv.cost,p.cost,0),'Entrada do lote '||v_lot.lot_code,auth.uid(),p_location from public.products p left join public.product_variants pv on pv.id=p_variant where p.id=p_product;
 return v_lot.id;
end $$;
revoke all on function public.inventory_lot_receive_v1(uuid,uuid,uuid,uuid,text,numeric,date,date,numeric,text,text) from public,anon;
grant execute on function public.inventory_lot_receive_v1(uuid,uuid,uuid,uuid,text,numeric,date,date,numeric,text,text) to authenticated;

create or replace function public.inventory_lots_v1(target_club uuid)
returns table(id uuid,product_id uuid,product_name text,variant_id uuid,variant_name text,location_id uuid,location_name text,lot_code text,received_at date,expires_at date,initial_quantity numeric,quantity numeric,unit_cost numeric,supplier text,status text,days_to_expiry integer,notes text)
language plpgsql security definer set search_path=public as $$
begin
 if not public.has_club_permission(target_club,'manageInventory') then raise exception 'Sem permissão para consultar lotes e custos.'; end if;
 perform public.inventory_refresh_lot_status_internal_v1(target_club);
 return query select sl.id,sl.product_id,p.name,sl.variant_id,pv.name,sl.location_id,l.name,sl.lot_code,sl.received_at,sl.expires_at,sl.initial_quantity,sl.quantity,sl.unit_cost,sl.supplier,sl.status,case when sl.expires_at is null then null else (sl.expires_at-current_date)::int end,sl.notes from public.stock_lots sl join public.products p on p.id=sl.product_id left join public.product_variants pv on pv.id=sl.variant_id join public.inventory_locations l on l.id=sl.location_id where sl.club_id=target_club order by sl.status,sl.expires_at nulls last,p.name,sl.lot_code;
end $$;
revoke all on function public.inventory_lots_v1(uuid) from public,anon;
grant execute on function public.inventory_lots_v1(uuid) to authenticated;

create or replace function public.inventory_breakage_record_v1(target_club uuid,p_product uuid,p_variant uuid,p_location uuid,p_quantity numeric,p_reason text default 'breakage',p_lot uuid default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_product public.products%rowtype; v_lot public.stock_lots%rowtype; v_cost numeric:=0; v_movement uuid; v_breakage uuid; v_remaining numeric; x record; v_take numeric;
begin
 if not public.has_club_permission(target_club,'manageInventory') then raise exception 'Sem permissão para registar quebras/perdas.'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Quantidade inválida.'; end if;
 if p_reason not in ('breakage','expiry','damage','loss','other') then raise exception 'Motivo inválido.'; end if;
 select * into v_product from public.products where id=p_product and club_id=target_club and active=true; if not found then raise exception 'Produto não encontrado.'; end if;
 if p_variant is not null and not exists(select 1 from public.product_variants where id=p_variant and product_id=p_product and active=true) then raise exception 'Variante inválida.'; end if;
 if p_lot is not null then
   select * into v_lot from public.stock_lots l where l.id=p_lot and l.club_id=target_club and l.product_id=p_product and l.variant_id is not distinct from p_variant and l.location_id=p_location for update;
   if not found then raise exception 'Lote inválido para o artigo/local selecionado.'; end if;
   if v_lot.quantity<p_quantity then raise exception 'Quantidade superior ao stock do lote.'; end if;
   update public.stock_lots set quantity=quantity-p_quantity,updated_at=now() where id=v_lot.id; v_cost:=coalesce(v_lot.unit_cost,0);
 else
   v_remaining:=p_quantity;
   for x in select l.id,l.quantity,l.unit_cost from public.stock_lots l where l.club_id=target_club and l.product_id=p_product and l.variant_id is not distinct from p_variant and l.location_id=p_location and l.quantity>0 and l.status<>'quarantined' order by l.expires_at nulls last,l.received_at,l.created_at for update loop
     exit when v_remaining<=0; v_take:=least(v_remaining,x.quantity); update public.stock_lots set quantity=quantity-v_take,updated_at=now() where id=x.id; if v_cost=0 and x.unit_cost is not null then v_cost:=x.unit_cost; end if; v_remaining:=v_remaining-v_take;
   end loop;
 end if;
 perform public.inventory_balance_apply_internal_v1(target_club,p_product,p_variant,p_location,-p_quantity,0);
 perform public.inventory_sync_aggregate_stock_v1(target_club,p_product,p_variant);
 perform public.inventory_refresh_lot_status_internal_v1(target_club);
 if v_cost=0 then if p_variant is null then v_cost:=coalesce(v_product.cost,0); else select coalesce(pv.cost,v_product.cost,0) into v_cost from public.product_variants pv where pv.id=p_variant; end if; end if;
 insert into public.stock_movements(club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by,from_location_id)
 values(target_club,p_product,p_variant,'loss',-p_quantity,coalesce(v_cost,0),'Quebra/perda ('||p_reason||')'||case when nullif(trim(coalesce(p_notes,'')),'') is null then '' else ': '||trim(p_notes) end,auth.uid(),p_location) returning id into v_movement;
 insert into public.stock_breakages(club_id,product_id,variant_id,location_id,lot_id,quantity,reason,unit_cost,notes,stock_movement_id,created_by)
 values(target_club,p_product,p_variant,p_location,p_lot,p_quantity,p_reason,coalesce(v_cost,0),nullif(trim(coalesce(p_notes,'')),''),v_movement,auth.uid()) returning id into v_breakage;
 return v_breakage;
end $$;
revoke all on function public.inventory_breakage_record_v1(uuid,uuid,uuid,uuid,numeric,text,uuid,text) from public,anon;
grant execute on function public.inventory_breakage_record_v1(uuid,uuid,uuid,uuid,numeric,text,uuid,text) to authenticated;

create or replace function public.inventory_stock_by_location_v1(target_club uuid)
returns table(location_id uuid,location_name text,location_type text,product_id uuid,product_name text,variant_id uuid,variant_name text,sku text,inventory_area text,unit text,quantity numeric,reserved_quantity numeric,available_quantity numeric)
language plpgsql security definer stable set search_path=public as $$
begin
 if not public.has_club_permission(target_club,'viewInventory') then raise exception 'Sem permissão para consultar inventário.'; end if;
 return query select b.location_id,l.name,l.location_type,b.product_id,p.name,b.variant_id,pv.name,coalesce(pv.sku,p.sku),p.inventory_area,p.unit,b.quantity,b.reserved_quantity,greatest(0,b.quantity-b.reserved_quantity-coalesce((select sum(sl.quantity) from public.stock_lots sl where sl.club_id=b.club_id and sl.product_id=b.product_id and sl.variant_id is not distinct from b.variant_id and sl.location_id=b.location_id and sl.quantity>0 and (sl.status in ('expired','quarantined') or (sl.expires_at is not null and sl.expires_at<current_date))),0)) from public.inventory_stock_balances b join public.inventory_locations l on l.id=b.location_id join public.products p on p.id=b.product_id left join public.product_variants pv on pv.id=b.variant_id where b.club_id=target_club and l.active=true and p.active=true order by l.name,p.name,pv.name nulls first;
end $$;
revoke all on function public.inventory_stock_by_location_v1(uuid) from public,anon;
grant execute on function public.inventory_stock_by_location_v1(uuid) to authenticated;

create or replace function public.inventory_advanced_summary_v1(target_club uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_manage boolean; v_member uuid; v_active int:=0; v_expiring int:=0; v_lots int:=0; v_expired int:=0; v_breakages numeric:=0;
begin
 if not public.has_club_permission(target_club,'viewInventory') then raise exception 'Sem permissão para consultar inventário.'; end if;
 v_manage:=public.has_club_permission(target_club,'manageInventory'); perform public.inventory_expire_reservations_internal_v1(target_club); perform public.inventory_refresh_lot_status_internal_v1(target_club);
 if not v_manage then select m.id into v_member from public.members m where m.club_id=target_club and m.profile_id=auth.uid() order by m.created_at limit 1; end if;
 select count(*),count(*) filter(where expires_at<=now()+interval '3 days') into v_active,v_expiring from public.stock_reservations r where r.club_id=target_club and r.status='active' and (v_manage or r.member_id=v_member);
 if v_manage then select count(*) filter(where status='active' and expires_at is not null and expires_at<=current_date+30),count(*) filter(where status='expired' and quantity>0) into v_lots,v_expired from public.stock_lots where club_id=target_club; select coalesce(sum(quantity),0) into v_breakages from public.stock_breakages where club_id=target_club and created_at>=date_trunc('month',now()); end if;
 return jsonb_build_object('active_reservations',v_active,'reservations_expiring_soon',v_expiring,'lots_expiring_30d',v_lots,'expired_lots',v_expired,'breakage_units_month',v_breakages,'can_manage',v_manage);
end $$;
revoke all on function public.inventory_advanced_summary_v1(uuid) from public,anon;
grant execute on function public.inventory_advanced_summary_v1(uuid) to authenticated;
