create or replace function public.inventory_sync_aggregate_stock_v1(target_club uuid,p_product uuid,p_variant uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform set_config('bob.skip_stock_balance_sync','1',true);
  if p_variant is null then
    update public.products p set
      current_stock=(select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b where b.club_id=target_club and b.product_id=p.id and b.variant_id is null),
      reserved_stock=(select coalesce(sum(b.reserved_quantity),0) from public.inventory_stock_balances b where b.club_id=target_club and b.product_id=p.id and b.variant_id is null)
    where p.id=p_product and p.club_id=target_club;
  else
    update public.product_variants pv set
      current_stock=(select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b where b.club_id=target_club and b.product_id=p_product and b.variant_id=pv.id),
      reserved_stock=(select coalesce(sum(b.reserved_quantity),0) from public.inventory_stock_balances b where b.club_id=target_club and b.product_id=p_product and b.variant_id=pv.id)
    where pv.id=p_variant and pv.product_id=p_product;
    update public.products p set
      current_stock=(select coalesce(sum(pv.current_stock),0) from public.product_variants pv where pv.product_id=p.id and pv.active=true),
      reserved_stock=(select coalesce(sum(pv.reserved_stock),0) from public.product_variants pv where pv.product_id=p.id and pv.active=true)
    where p.id=p_product and p.club_id=target_club;
  end if;
  perform set_config('bob.skip_stock_balance_sync','0',true);
end $$;
revoke all on function public.inventory_sync_aggregate_stock_v1(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.inventory_expire_reservations_internal_v1(target_club uuid default null)
returns integer language plpgsql security definer set search_path=public as $$
declare r record; v_count integer:=0;
begin
  for r in select id,club_id,product_id,variant_id,location_id,quantity from public.stock_reservations
    where status='active' and expires_at<=now() and (target_club is null or club_id=target_club)
    order by expires_at,id for update skip locked
  loop
    update public.inventory_stock_balances b
    set reserved_quantity=greatest(0,b.reserved_quantity-r.quantity),updated_at=now(),updated_by=null
    where b.club_id=r.club_id and b.product_id=r.product_id and b.variant_id is not distinct from r.variant_id and b.location_id=r.location_id;
    perform public.inventory_sync_aggregate_stock_v1(r.club_id,r.product_id,r.variant_id);
    update public.stock_reservations set status='expired',released_at=now(),release_reason='Prazo de 30 dias atingido',updated_at=now() where id=r.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;
revoke all on function public.inventory_expire_reservations_internal_v1(uuid) from public,anon,authenticated;

create or replace function public.inventory_reservation_create_v1(
  target_club uuid,p_product uuid,p_variant uuid,p_location uuid,p_quantity numeric,p_member uuid default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_member uuid; v_balance public.inventory_stock_balances%rowtype; v_expired numeric:=0; v_reservation uuid;
begin
  if not public.has_club_permission(target_club,'viewInventory') then raise exception 'Sem permissão para reservar stock.'; end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'A quantidade deve ser superior a zero.'; end if;
  perform public.inventory_expire_reservations_internal_v1(target_club);
  if p_member is null then
    select m.id into v_member from public.members m where m.club_id=target_club and m.profile_id=auth.uid() order by m.created_at limit 1;
  else v_member:=p_member; end if;
  if v_member is null or not exists(select 1 from public.members m where m.id=v_member and m.club_id=target_club) then raise exception 'Membro inválido para este clube.'; end if;
  if not public.has_club_permission(target_club,'manageInventory') and not exists(select 1 from public.members m where m.id=v_member and m.club_id=target_club and m.profile_id=auth.uid()) then raise exception 'Só pode criar reservas em seu próprio nome.'; end if;
  if not exists(select 1 from public.products p where p.id=p_product and p.club_id=target_club and p.active=true) then raise exception 'Produto não encontrado ou inativo.'; end if;
  if exists(select 1 from public.product_variants where product_id=p_product and active=true) and p_variant is null then raise exception 'Seleciona a variante do produto.'; end if;
  if p_variant is not null and not exists(select 1 from public.product_variants where id=p_variant and product_id=p_product and active=true) then raise exception 'Variante inválida.'; end if;
  select * into v_balance from public.inventory_stock_balances b where b.club_id=target_club and b.product_id=p_product and b.variant_id is not distinct from p_variant and b.location_id=p_location for update;
  if not found then raise exception 'Não existe stock nesse local.'; end if;
  select coalesce(sum(l.quantity),0) into v_expired from public.stock_lots l
   where l.club_id=target_club and l.product_id=p_product and l.variant_id is not distinct from p_variant and l.location_id=p_location and l.quantity>0
   and (l.status in ('expired','quarantined') or (l.expires_at is not null and l.expires_at<current_date));
  if v_balance.quantity-v_balance.reserved_quantity-v_expired<p_quantity then raise exception 'Stock disponível insuficiente para a reserva.'; end if;
  perform public.inventory_balance_apply_internal_v1(target_club,p_product,p_variant,p_location,0,p_quantity);
  perform public.inventory_sync_aggregate_stock_v1(target_club,p_product,p_variant);
  insert into public.stock_reservations(club_id,product_id,variant_id,location_id,member_id,quantity,status,reserved_at,expires_at,notes,created_by)
  values(target_club,p_product,p_variant,p_location,v_member,p_quantity,'active',now(),now()+interval '30 days',nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v_reservation;
  return v_reservation;
end $$;
revoke all on function public.inventory_reservation_create_v1(uuid,uuid,uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.inventory_reservation_create_v1(uuid,uuid,uuid,uuid,numeric,uuid,text) to authenticated;

create or replace function public.inventory_reservation_close_v1(target_club uuid,p_reservation uuid,p_action text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.stock_reservations%rowtype; v_status text; v_is_owner boolean;
begin
  if p_action not in ('cancel','release') then raise exception 'Ação de reserva inválida.'; end if;
  select * into r from public.stock_reservations where id=p_reservation and club_id=target_club and status='active' for update;
  if not found then raise exception 'Reserva não encontrada ou já encerrada.'; end if;
  select exists(select 1 from public.members m where m.id=r.member_id and m.profile_id=auth.uid()) into v_is_owner;
  if p_action='cancel' then
    if not (v_is_owner or public.has_club_permission(target_club,'manageInventory')) then raise exception 'Sem permissão para cancelar esta reserva.'; end if;
    v_status:='cancelled';
  else
    if not public.has_club_permission(target_club,'manageInventory') then raise exception 'Sem permissão para libertar reservas.'; end if;
    v_status:='released';
  end if;
  perform public.inventory_balance_apply_internal_v1(target_club,r.product_id,r.variant_id,r.location_id,0,-r.quantity);
  perform public.inventory_sync_aggregate_stock_v1(target_club,r.product_id,r.variant_id);
  update public.stock_reservations set status=v_status,released_at=now(),released_by=auth.uid(),release_reason=coalesce(nullif(trim(coalesce(p_reason,'')),''),case when v_status='cancelled' then 'Cancelada pelo membro' else 'Libertada pelo responsável' end),updated_at=now() where id=r.id;
  return jsonb_build_object('reservation_id',r.id,'status',v_status,'quantity',r.quantity);
end $$;
revoke all on function public.inventory_reservation_close_v1(uuid,uuid,text,text) from public,anon;
grant execute on function public.inventory_reservation_close_v1(uuid,uuid,text,text) to authenticated;

create or replace function public.inventory_reservations_v1(target_club uuid)
returns table(id uuid,product_id uuid,product_name text,variant_id uuid,variant_name text,location_id uuid,location_name text,member_id uuid,member_name text,quantity numeric,status text,reserved_at timestamptz,expires_at timestamptz,days_remaining integer,notes text,can_cancel boolean)
language plpgsql security definer set search_path=public as $$
declare v_manage boolean:=public.has_club_permission(target_club,'manageInventory');
begin
  if not public.has_club_permission(target_club,'viewInventory') then raise exception 'Sem permissão para consultar reservas.'; end if;
  perform public.inventory_expire_reservations_internal_v1(target_club);
  return query select r.id,r.product_id,p.name,r.variant_id,pv.name,r.location_id,l.name,r.member_id,m.full_name,r.quantity,r.status,r.reserved_at,r.expires_at,
    greatest(0,ceil(extract(epoch from (r.expires_at-now()))/86400.0)::int),r.notes,(v_manage or m.profile_id=auth.uid())
  from public.stock_reservations r join public.products p on p.id=r.product_id left join public.product_variants pv on pv.id=r.variant_id join public.inventory_locations l on l.id=r.location_id join public.members m on m.id=r.member_id
  where r.club_id=target_club and (v_manage or m.profile_id=auth.uid())
  order by case when r.status='active' then 0 else 1 end,r.expires_at,r.created_at desc;
end $$;
revoke all on function public.inventory_reservations_v1(uuid) from public,anon;
grant execute on function public.inventory_reservations_v1(uuid) to authenticated;