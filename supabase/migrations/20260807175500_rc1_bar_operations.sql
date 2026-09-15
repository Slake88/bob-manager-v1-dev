alter table public.products add column if not exists purchase_unit text;
alter table public.products add column if not exists consumption_unit text;
alter table public.products add column if not exists units_per_purchase numeric(12,4) not null default 1;
alter table public.products add column if not exists purchase_cost numeric(12,2) not null default 0;

create table if not exists public.bar_operations (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade, event_id uuid references public.events(id) on delete set null,
  operation_type text not null check (operation_type in ('purchase','sale','offer','internal','waste','adjustment_in','adjustment_out')),
  purchase_units numeric(12,3), consumption_quantity numeric(12,3) not null,
  unit_price numeric(12,2) not null default 0, total_amount numeric(12,2) not null default 0,
  payment_method text, notes text, treasury_transaction_id uuid references public.treasury_transactions(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);

create table if not exists public.bar_consumption_sessions (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null, source text not null default 'manual' check (source in ('manual','ocr')),
  status text not null default 'draft' check (status in ('draft','confirmed','cancelled')), raw_payload jsonb, notes text,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now(), confirmed_at timestamptz
);
create table if not exists public.bar_consumption_session_items (
  id uuid primary key default gen_random_uuid(), session_id uuid not null references public.bar_consumption_sessions(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade, quantity numeric(12,3) not null check (quantity > 0),
  operation_type text not null default 'sale' check (operation_type in ('sale','offer','internal','waste')),
  unit_price numeric(12,2) not null default 0, notes text, created_at timestamptz not null default now()
);

alter table public.bar_operations enable row level security;
alter table public.bar_consumption_sessions enable row level security;
alter table public.bar_consumption_session_items enable row level security;

drop policy if exists bar_operations_select on public.bar_operations;
create policy bar_operations_select on public.bar_operations for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists bar_operations_manage on public.bar_operations;
create policy bar_operations_manage on public.bar_operations for all to authenticated using (public.has_club_permission(club_id,'manageBar')) with check (public.has_club_permission(club_id,'manageBar'));
drop policy if exists bar_sessions_select on public.bar_consumption_sessions;
create policy bar_sessions_select on public.bar_consumption_sessions for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists bar_sessions_manage on public.bar_consumption_sessions;
create policy bar_sessions_manage on public.bar_consumption_sessions for all to authenticated using (public.has_club_permission(club_id,'manageBar')) with check (public.has_club_permission(club_id,'manageBar'));
drop policy if exists bar_session_items_select on public.bar_consumption_session_items;
create policy bar_session_items_select on public.bar_consumption_session_items for select to authenticated using (exists(select 1 from public.bar_consumption_sessions s where s.id=session_id and public.has_club_permission(s.club_id,'viewInventory')));
drop policy if exists bar_session_items_manage on public.bar_consumption_session_items;
create policy bar_session_items_manage on public.bar_consumption_session_items for all to authenticated using (exists(select 1 from public.bar_consumption_sessions s where s.id=session_id and public.has_club_permission(s.club_id,'manageBar'))) with check (exists(select 1 from public.bar_consumption_sessions s where s.id=session_id and public.has_club_permission(s.club_id,'manageBar')));

drop policy if exists products_insert on public.products;
create policy products_insert on public.products for insert to authenticated with check (public.has_club_permission(club_id,'manageInventory') or public.has_club_permission(club_id,'manageMerchandising') or public.has_club_permission(club_id,'manageBar'));
drop policy if exists products_update on public.products;
create policy products_update on public.products for update to authenticated using (public.has_club_permission(club_id,'manageInventory') or public.has_club_permission(club_id,'manageMerchandising') or public.has_club_permission(club_id,'manageBar')) with check (public.has_club_permission(club_id,'manageInventory') or public.has_club_permission(club_id,'manageMerchandising') or public.has_club_permission(club_id,'manageBar'));
drop policy if exists stock_movements_insert on public.stock_movements;
create policy stock_movements_insert on public.stock_movements for insert to authenticated with check ((public.has_club_permission(club_id,'manageInventory') or public.has_club_permission(club_id,'sellInventory') or public.has_club_permission(club_id,'manageMerchandising') or public.has_club_permission(club_id,'manageBar')) and created_by=auth.uid());

create or replace function public.bar_operation_v1(target_club uuid,p_product uuid,p_operation text,p_quantity numeric,p_event uuid default null,p_purchase_units numeric default null,p_unit_price numeric default null,p_payment_method text default null,p_notes text default null,p_post_financial boolean default true)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_product public.products%rowtype; v_delta numeric; v_new_stock numeric; v_total numeric:=0; v_kind public.stock_movement_kind; v_account uuid; v_cost_center uuid; v_tx uuid; v_desc text;
begin
  if not public.has_club_permission(target_club,'manageBar') then raise exception 'Sem autorização para gerir o Bar.'; end if;
  if p_quantity<=0 then raise exception 'A quantidade deve ser superior a zero.'; end if;
  select * into v_product from public.products where id=p_product and club_id=target_club and inventory_area='bar' and active=true for update;
  if not found then raise exception 'Artigo de Bar não encontrado ou inativo.'; end if;
  if p_event is not null and not exists(select 1 from public.events where id=p_event and club_id=target_club) then raise exception 'Evento inválido.'; end if;
  if p_operation in ('purchase','adjustment_in') then v_delta:=p_quantity; else v_delta:=-p_quantity; end if;
  v_new_stock:=coalesce(v_product.current_stock,0)+v_delta;
  if v_new_stock<0 then raise exception 'Stock insuficiente. Disponível: %',coalesce(v_product.current_stock,0); end if;
  if p_operation='purchase' then v_kind:='purchase'; elsif p_operation='sale' then v_kind:='sale'; elsif p_operation='waste' then v_kind:='loss'; elsif p_operation in ('offer','internal') then v_kind:='event_consumption'; else v_kind:='adjustment'; end if;
  v_total:=case when p_operation='purchase' then coalesce(p_purchase_units,0)*coalesce(p_unit_price,v_product.purchase_cost,v_product.cost,0) when p_operation='sale' then p_quantity*coalesce(p_unit_price,v_product.sale_price,0) else 0 end;
  update public.products set current_stock=v_new_stock where id=v_product.id;
  insert into public.stock_movements(club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by) values(target_club,p_product,p_event,v_kind,v_delta,coalesce(p_unit_price,v_product.cost,0),nullif(trim(coalesce(p_notes,'')),''),auth.uid());
  v_desc:=case p_operation when 'purchase' then 'Compra Bar - ' when 'sale' then 'Venda Bar - ' when 'offer' then 'Oferta Bar - ' when 'internal' then 'Consumo interno Bar - ' when 'waste' then 'Quebra Bar - ' else 'Ajuste Bar - ' end || v_product.name;
  if p_post_financial and p_operation in ('purchase','sale') and v_total>0 then
    select id into v_account from public.treasury_accounts where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
    if v_account is null then raise exception 'Conta Club House não encontrada.'; end if;
    select id into v_cost_center from public.cost_centers where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
    insert into public.treasury_transactions(club_id,kind,account_id,cost_center_id,event_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by)
    values(target_club,case when p_operation='sale' then 'income'::public.transaction_kind else 'expense'::public.transaction_kind end,v_account,v_cost_center,p_event,current_date,v_desc,v_total,p_payment_method,'bar_operation',p_product,auth.uid()) returning id into v_tx;
  end if;
  insert into public.bar_operations(club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,payment_method,notes,treasury_transaction_id,created_by)
  values(target_club,p_product,p_event,p_operation,p_purchase_units,p_quantity,coalesce(p_unit_price,0),v_total,p_payment_method,nullif(trim(coalesce(p_notes,'')),''),v_tx,auth.uid());
  perform public.emit_domain_event(target_club,'BarOperationRecorded','inventory',p_product,jsonb_build_object('title',v_desc,'description',p_quantity::text||' '||coalesce(v_product.consumption_unit,v_product.unit,'unid.'),'module_code','inventory','route','inventory','priority',case when v_new_stock<=coalesce(v_product.minimum_stock,0) then 'medium' else 'low' end));
  return jsonb_build_object('product_id',p_product,'current_stock',v_new_stock,'transaction_id',v_tx);
end; $$;
grant execute on function public.bar_operation_v1(uuid,uuid,text,numeric,uuid,numeric,numeric,text,text,boolean) to authenticated;
