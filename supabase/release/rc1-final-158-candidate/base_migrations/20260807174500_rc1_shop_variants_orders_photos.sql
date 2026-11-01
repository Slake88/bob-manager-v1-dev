alter table public.products add column if not exists description text;
alter table public.products add column if not exists supplier text;
alter table public.products add column if not exists photo_path text;
alter table public.products add column if not exists institutional_delivery boolean not null default false;

alter table public.product_variants add column if not exists current_stock numeric(12,2) not null default 0;
alter table public.product_variants add column if not exists reserved_stock numeric(12,2) not null default 0;
alter table public.product_variants add column if not exists minimum_stock numeric(12,2) not null default 0;
alter table public.product_variants add column if not exists cost numeric(12,2);
alter table public.product_variants add column if not exists sale_price numeric(12,2);
alter table public.product_variants add column if not exists photo_path text;
alter table public.product_variants add constraint product_variants_stock_check check (current_stock >= 0 and reserved_stock >= 0 and reserved_stock <= current_stock) not valid;

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade, variant_id uuid references public.product_variants(id) on delete cascade,
  storage_path text not null, is_primary boolean not null default false, created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.shop_orders (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null, external_name text, external_contact text,
  status text not null default 'pending' check (status in ('pending','ordered','received','delivered','cancelled')),
  total_amount numeric(12,2) not null default 0, paid_amount numeric(12,2) not null default 0, notes text,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (member_id is not null or nullif(trim(coalesce(external_name,'')),'') is not null),
  check (total_amount >= 0 and paid_amount >= 0 and paid_amount <= total_amount)
);
create table if not exists public.shop_order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.shop_orders(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict, variant_id uuid references public.product_variants(id) on delete restrict,
  quantity numeric(12,2) not null check (quantity > 0), unit_price numeric(12,2) not null check (unit_price >= 0), created_at timestamptz not null default now()
);
create table if not exists public.shop_order_payments (
  id uuid primary key default gen_random_uuid(), club_id uuid not null references public.clubs(id) on delete cascade,
  order_id uuid not null references public.shop_orders(id) on delete cascade, amount numeric(12,2) not null check (amount > 0),
  payment_method text not null default 'Dinheiro', treasury_transaction_id uuid references public.treasury_transactions(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null, created_at timestamptz not null default now()
);
create index if not exists idx_shop_orders_club_status on public.shop_orders(club_id,status,created_at desc);
create index if not exists idx_shop_order_items_order on public.shop_order_items(order_id);
create index if not exists idx_product_variants_product on public.product_variants(product_id,active);

alter table public.product_images enable row level security;
alter table public.shop_orders enable row level security;
alter table public.shop_order_items enable row level security;
alter table public.shop_order_payments enable row level security;

drop policy if exists product_images_read on public.product_images;
create policy product_images_read on public.product_images for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists product_images_manage on public.product_images;
create policy product_images_manage on public.product_images for all to authenticated using (public.has_club_permission(club_id,'manageMerchandising')) with check (public.has_club_permission(club_id,'manageMerchandising'));
drop policy if exists shop_orders_read on public.shop_orders;
create policy shop_orders_read on public.shop_orders for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists shop_orders_manage on public.shop_orders;
create policy shop_orders_manage on public.shop_orders for all to authenticated using (public.has_club_permission(club_id,'manageMerchandising')) with check (public.has_club_permission(club_id,'manageMerchandising'));
drop policy if exists shop_order_items_read on public.shop_order_items;
create policy shop_order_items_read on public.shop_order_items for select to authenticated using (exists(select 1 from public.shop_orders o where o.id=order_id and public.has_club_permission(o.club_id,'viewInventory')));
drop policy if exists shop_order_items_manage on public.shop_order_items;
create policy shop_order_items_manage on public.shop_order_items for all to authenticated using (exists(select 1 from public.shop_orders o where o.id=order_id and public.has_club_permission(o.club_id,'manageMerchandising'))) with check (exists(select 1 from public.shop_orders o where o.id=order_id and public.has_club_permission(o.club_id,'manageMerchandising')));
drop policy if exists shop_order_payments_read on public.shop_order_payments;
create policy shop_order_payments_read on public.shop_order_payments for select to authenticated using (public.has_club_permission(club_id,'viewInventory'));
drop policy if exists shop_order_payments_manage on public.shop_order_payments;
create policy shop_order_payments_manage on public.shop_order_payments for insert to authenticated with check (public.has_club_permission(club_id,'sellInventory') or public.has_club_permission(club_id,'manageMerchandising'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('inventory-media','inventory-media',true,10485760,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists inventory_media_read on storage.objects;
create policy inventory_media_read on storage.objects for select to authenticated using (bucket_id='inventory-media');
drop policy if exists inventory_media_insert on storage.objects;
create policy inventory_media_insert on storage.objects for insert to authenticated with check (bucket_id='inventory-media' and public.has_club_permission((storage.foldername(name))[1]::uuid,'manageMerchandising'));
drop policy if exists inventory_media_update on storage.objects;
create policy inventory_media_update on storage.objects for update to authenticated using (bucket_id='inventory-media' and public.has_club_permission((storage.foldername(name))[1]::uuid,'manageMerchandising')) with check (bucket_id='inventory-media' and public.has_club_permission((storage.foldername(name))[1]::uuid,'manageMerchandising'));
drop policy if exists inventory_media_delete on storage.objects;
create policy inventory_media_delete on storage.objects for delete to authenticated using (bucket_id='inventory-media' and public.has_club_permission((storage.foldername(name))[1]::uuid,'manageMerchandising'));

create or replace function public.create_shop_order_v1(target_club uuid,p_product uuid,p_variant uuid,p_quantity numeric,p_unit_price numeric,p_member uuid default null,p_external_name text default null,p_external_contact text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='public' as $$
declare v_order uuid; v_product public.products%rowtype; v_variant public.product_variants%rowtype;
begin
 if not public.has_club_permission(target_club,'manageMerchandising') then raise exception 'Sem autorização para gerir encomendas.'; end if;
 if p_quantity<=0 or p_unit_price<0 then raise exception 'Quantidade/preço inválidos.'; end if;
 if p_member is null and nullif(trim(coalesce(p_external_name,'')),'') is null then raise exception 'Indique o membro ou o nome do cliente.'; end if;
 select * into v_product from public.products where id=p_product and club_id=target_club and inventory_area='shop' and active=true; if not found then raise exception 'Artigo não encontrado.'; end if;
 if p_variant is not null then select * into v_variant from public.product_variants where id=p_variant and product_id=p_product and active=true; if not found then raise exception 'Variante não encontrada.'; end if; end if;
 insert into public.shop_orders(club_id,member_id,external_name,external_contact,total_amount,notes,created_by) values(target_club,p_member,nullif(trim(coalesce(p_external_name,'')),''),nullif(trim(coalesce(p_external_contact,'')),''),p_quantity*p_unit_price,nullif(trim(coalesce(p_notes,'')),''),auth.uid()) returning id into v_order;
 insert into public.shop_order_items(order_id,product_id,variant_id,quantity,unit_price) values(v_order,p_product,p_variant,p_quantity,p_unit_price);
 perform public.emit_domain_event(target_club,'ShopOrderCreated','product',p_product,jsonb_build_object('title','Nova encomenda de Loja','description',v_product.name||case when p_variant is not null then ' — '||v_variant.name else '' end||' × '||p_quantity::text,'module_code','inventory','priority','normal','route','inventory'));
 return v_order;
end; $$;

create or replace function public.record_shop_order_payment_v1(target_club uuid,p_order uuid,p_amount numeric,p_payment_method text default 'Dinheiro') returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_order public.shop_orders%rowtype; v_account uuid; v_cost_center uuid; v_tx uuid; v_name text; v_new_paid numeric;
begin
 if not (public.has_club_permission(target_club,'sellInventory') or public.has_club_permission(target_club,'manageMerchandising')) then raise exception 'Sem autorização para receber pagamentos.'; end if;
 if p_amount<=0 then raise exception 'O valor deve ser superior a zero.'; end if;
 select * into v_order from public.shop_orders where id=p_order and club_id=target_club and status<>'cancelled' for update; if not found then raise exception 'Encomenda não encontrada.'; end if;
 if v_order.paid_amount+p_amount>v_order.total_amount then raise exception 'O pagamento ultrapassa o valor em dívida.'; end if;
 select id into v_account from public.treasury_accounts where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1; if v_account is null then raise exception 'Conta Club House não encontrada.'; end if;
 select id into v_cost_center from public.cost_centers where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
 select coalesce(m.full_name,v_order.external_name,'Cliente') into v_name from public.shop_orders o left join public.members m on m.id=o.member_id where o.id=v_order.id;
 insert into public.treasury_transactions(club_id,kind,account_id,cost_center_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by) values(target_club,'income',v_account,v_cost_center,current_date,'Pagamento encomenda Loja - '||v_name,p_amount,p_payment_method,'shop_order',v_order.id,auth.uid()) returning id into v_tx;
 insert into public.shop_order_payments(club_id,order_id,amount,payment_method,treasury_transaction_id,created_by) values(target_club,v_order.id,p_amount,p_payment_method,v_tx,auth.uid());
 v_new_paid:=v_order.paid_amount+p_amount; update public.shop_orders set paid_amount=v_new_paid,updated_at=now() where id=v_order.id;
 return jsonb_build_object('order_id',v_order.id,'paid_amount',v_new_paid,'remaining',v_order.total_amount-v_new_paid,'transaction_id',v_tx);
end; $$;

create or replace function public.reserve_shop_variant_v1(target_club uuid,p_product uuid,p_variant uuid,p_quantity numeric,p_notes text default null) returns jsonb language plpgsql security definer set search_path='public' as $$
declare v_variant public.product_variants%rowtype; v_product public.products%rowtype;
begin
 if not public.has_club_permission(target_club,'manageMerchandising') then raise exception 'Sem autorização para reservar stock.'; end if;
 if p_quantity<=0 then raise exception 'Quantidade inválida.'; end if;
 select * into v_product from public.products where id=p_product and club_id=target_club and active=true; if not found then raise exception 'Artigo não encontrado.'; end if;
 select * into v_variant from public.product_variants where id=p_variant and product_id=p_product and active=true for update; if not found then raise exception 'Variante não encontrada.'; end if;
 if v_variant.current_stock-v_variant.reserved_stock<p_quantity then raise exception 'Stock disponível insuficiente. Use Encomendar para artigos sem stock.'; end if;
 update public.product_variants set reserved_stock=reserved_stock+p_quantity where id=p_variant;
 insert into public.stock_movements(club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by) values(target_club,p_product,p_variant,'transfer',p_quantity,coalesce(v_variant.cost,v_product.cost),coalesce(nullif(trim(coalesce(p_notes,'')),''),'Reserva de stock'),auth.uid());
 return jsonb_build_object('variant_id',p_variant,'reserved_stock',v_variant.reserved_stock+p_quantity);
end; $$;
