begin;
-- Reference checks follow existing authorization and precede all writes.
-- Missing and foreign-club UUIDs intentionally have identical errors.
-- SHARE row locks keep validated club_id values stable through the transaction.

-- Fail closed if this is not the expected existing RPC surface: never create
-- a missing SECURITY DEFINER endpoint with PostgreSQL's default PUBLIC ACL.
do $preflight$
declare signature text; function_oid oid;
begin
  foreach signature in array array[
    'public.create_treasury_transaction(uuid,public.transaction_kind,uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text)',
    'public.create_member_with_position(uuid,integer,text,text,text,text,date,uuid)',
    'public.asset_loan_v1(uuid,uuid,text,uuid,uuid,text,timestamptz,text)',
    'public.log_asset_event_v1(uuid,uuid,text,text,text,jsonb)',
    'public.create_shop_order_v1(uuid,uuid,uuid,numeric,numeric,uuid,text,text,text)'
  ] loop
    function_oid := pg_catalog.to_regprocedure(signature);
    if function_oid is null then
      raise exception '2C.7 baseline RPC missing: %', signature using errcode='42883';
    end if;
    if pg_catalog.has_function_privilege('anon',function_oid,'EXECUTE') or exists (
      select 1 from pg_catalog.pg_proc p,
        lateral pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) acl
      where p.oid=function_oid and acl.grantee=0 and acl.privilege_type='EXECUTE'
    ) then
      raise exception '2C.7 baseline RPC ACL mismatch: %', signature using errcode='42501';
    end if;
  end loop;
end;
$preflight$;

create or replace function public.create_treasury_transaction(
  target_club uuid,transaction_kind public.transaction_kind,source_account uuid,
  destination_account uuid,category uuid,cost_center uuid,event_ref uuid,
  movement_date date,movement_description text,movement_amount numeric,
  movement_payment_method text,movement_notes text
) returns uuid language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare transaction_id uuid;
begin
  if transaction_kind='transfer' then
    if not public.has_club_permission(target_club,'transferBetweenAccounts') then
      raise exception 'Sem autorização para transferir entre contas.';
    end if;
  else
    if not public.has_club_permission(target_club,'createTreasuryMovement') then
      raise exception 'Sem autorização para criar movimentos.';
    end if;
  end if;

  if category is not null then
    perform 1 from public.treasury_categories ref where ref.id=category and ref.club_id=target_club for share;
    if not found then
      raise exception 'Categoria: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;
  if cost_center is not null then
    perform 1 from public.cost_centers ref where ref.id=cost_center and ref.club_id=target_club for share;
    if not found then
      raise exception 'Centro de custo: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;
  if event_ref is not null then
    perform 1 from public.events ref where ref.id=event_ref and ref.club_id=target_club for share;
    if not found then
      raise exception 'Evento: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,destination_account_id,category_id,cost_center_id,event_id,
    transaction_date,description,amount,payment_method,notes,created_by
  ) values(
    target_club,transaction_kind,source_account,
    case when transaction_kind='transfer' then destination_account else null end,
    category,cost_center,event_ref,movement_date,movement_description,movement_amount,
    movement_payment_method,movement_notes,auth.uid()
  ) returning id into transaction_id;
  return transaction_id;
end; $$;

create or replace function public.create_member_with_position(
  target_club uuid,new_member_number integer,new_full_name text,new_nickname text,
  new_email text,new_phone text,new_joined_at date,position_ref uuid
) returns uuid language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare member_id uuid;
begin
  if not public.has_club_permission(target_club,'manageMembers') then
    raise exception 'Sem autorização para criar membros.';
  end if;

  if position_ref is not null then
    perform 1 from public.club_positions ref where ref.id=position_ref and ref.club_id=target_club for share;
    if not found then
      raise exception 'Cargo: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;

  insert into public.members(
    club_id,member_number,full_name,nickname,email,phone,joined_at,status
  ) values(
    target_club,new_member_number,new_full_name,new_nickname,new_email,new_phone,new_joined_at,'active'
  ) returning id into member_id;
  if position_ref is not null then
      insert into public.member_positions(club_id,member_id,position_id,is_primary,starts_at)
      values(target_club,member_id,position_ref,true,new_joined_at);
  end if;
  return member_id;
end; $$;

create or replace function public.asset_loan_v1(target_club uuid,p_asset uuid,p_borrower_type text,p_member uuid default null,p_event uuid default null,p_external_name text default null,p_expected_return timestamptz default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_id uuid; v_name text; begin
if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;
select name into v_name from public.inventory_assets where id=p_asset and club_id=target_club and active=true for update;
if v_name is null then raise exception 'Bem patrimonial inválido.'; end if;
if exists(select 1 from public.asset_loans where asset_id=p_asset and returned_at is null) then raise exception 'Este bem já se encontra emprestado ou associado.'; end if;
if p_borrower_type not in ('member','external','event') then raise exception 'Tipo de destinatário inválido.'; end if;

  if p_member is not null then
    perform 1 from public.members ref where ref.id=p_member and ref.club_id=target_club for share;
    if not found then
      raise exception 'Membro: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;
  if p_event is not null then
    perform 1 from public.events ref where ref.id=p_event and ref.club_id=target_club for share;
    if not found then
      raise exception 'Evento: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;

insert into public.asset_loans(club_id,asset_id,borrower_type,member_id,event_id,external_name,expected_return_at,notes,created_by)
values(target_club,p_asset,p_borrower_type,p_member,p_event,nullif(trim(coalesce(p_external_name,'')),''),p_expected_return,nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v_id;
insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
values(target_club,p_asset,'loan','Bem emprestado / associado',nullif(trim(coalesce(p_notes,'')),''),jsonb_build_object('loan_id',v_id,'borrower_type',p_borrower_type,'expected_return_at',p_expected_return),auth.uid());
return v_id; end; $$;

create or replace function public.log_asset_event_v1(target_club uuid,p_asset uuid,p_type text,p_title text,p_description text default null,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_id uuid;
begin
  if not public.has_club_permission(target_club,'manageAssets') then raise exception 'Sem autorização para gerir património.'; end if;

  perform 1 from public.inventory_assets ref where ref.id=p_asset and ref.club_id=target_club for share;
  if not found then
    raise exception 'Bem patrimonial: referência inválida para o clube.' using errcode='22023';
  end if;

  insert into public.asset_events(club_id,asset_id,event_type,title,description,metadata,created_by)
  values(target_club,p_asset,p_type,p_title,p_description,coalesce(p_metadata,'{}'::jsonb),auth.uid()) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.create_shop_order_v1(target_club uuid,p_product uuid,p_variant uuid,p_quantity numeric,p_unit_price numeric,p_member uuid default null,p_external_name text default null,p_external_contact text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_order uuid; v_product public.products%rowtype; v_variant public.product_variants%rowtype;
begin
 if not public.has_club_permission(target_club,'manageMerchandising') then raise exception 'Sem autorização para gerir encomendas.'; end if;
 if p_quantity<=0 or p_unit_price<0 then raise exception 'Quantidade/preço inválidos.'; end if;
 if p_member is null and nullif(trim(coalesce(p_external_name,'')),'') is null then raise exception 'Indique o membro ou o nome do cliente.'; end if;
 select * into v_product from public.products where id=p_product and club_id=target_club and inventory_area='shop' and active=true; if not found then raise exception 'Artigo não encontrado.'; end if;
 if p_variant is not null then select * into v_variant from public.product_variants where id=p_variant and product_id=p_product and active=true; if not found then raise exception 'Variante não encontrada.'; end if; end if;

  if p_member is not null then
    perform 1 from public.members ref where ref.id=p_member and ref.club_id=target_club for share;
    if not found then
      raise exception 'Membro: referência inválida para o clube.' using errcode='22023';
    end if;
  end if;

 insert into public.shop_orders(club_id,member_id,external_name,external_contact,total_amount,notes,created_by) values(target_club,p_member,nullif(trim(coalesce(p_external_name,'')),''),nullif(trim(coalesce(p_external_contact,'')),''),p_quantity*p_unit_price,nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v_order;
 insert into public.shop_order_items(order_id,product_id,variant_id,quantity,unit_price) values(v_order,p_product,p_variant,p_quantity,p_unit_price);
 perform public.emit_domain_event(target_club,'ShopOrderCreated','product',p_product,jsonb_build_object('title','Nova encomenda de Loja','description',v_product.name||case when p_variant is not null then ' — '||v_variant.name else '' end||' × '||p_quantity::text,'module_code','inventory','priority','normal','route','inventory'));
 return v_order;
end; $$;

-- CREATE OR REPLACE preserves existing owner and ACLs; no new grants.
commit;
