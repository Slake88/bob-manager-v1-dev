-- Commit 14 — Fundação de Inventário: stock por localização e transferências.

alter table public.inventory_locations
  add column if not exists location_type text not null default 'storage',
  add column if not exists event_id uuid null references public.events(id) on delete set null,
  add column if not exists parent_id uuid null references public.inventory_locations(id) on delete set null;

alter table public.inventory_locations drop constraint if exists inventory_locations_location_type_check;
alter table public.inventory_locations add constraint inventory_locations_location_type_check
  check (location_type in ('storage','clubhouse','event','loan','vehicle','workshop','other'));

update public.inventory_locations
set location_type = case
  when lower(name)=lower('Club House') then 'clubhouse'
  when lower(name)=lower('Em Evento') then 'event'
  when lower(name)=lower('Emprestado') then 'loan'
  when lower(name)=lower('Reboque') then 'vehicle'
  when lower(name)=lower('Oficina') then 'workshop'
  else 'storage'
end;

create unique index if not exists inventory_locations_event_unique_idx
  on public.inventory_locations(club_id,event_id)
  where event_id is not null;

insert into public.inventory_locations(club_id,name,description,active,location_type)
select c.id,'Armazém','Local padrão para stock de Loja',true,'storage'
from public.clubs c
where not exists (
  select 1 from public.inventory_locations l
  where l.club_id=c.id and lower(l.name)=lower('Armazém')
);

insert into public.inventory_locations(club_id,name,description,active,location_type)
select c.id,'Club House','Local padrão para stock de Bar',true,'clubhouse'
from public.clubs c
where not exists (
  select 1 from public.inventory_locations l
  where l.club_id=c.id and lower(l.name)=lower('Club House')
);

create table if not exists public.inventory_stock_balances (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  variant_id uuid null references public.product_variants(id) on delete cascade,
  location_id uuid not null references public.inventory_locations(id) on delete cascade,
  quantity numeric not null default 0 check (quantity >= 0),
  reserved_quantity numeric not null default 0 check (reserved_quantity >= 0 and reserved_quantity <= quantity),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid null default auth.uid()
);

create unique index if not exists inventory_stock_balances_product_location_unique_idx
  on public.inventory_stock_balances(club_id,product_id,location_id)
  where variant_id is null;
create unique index if not exists inventory_stock_balances_variant_location_unique_idx
  on public.inventory_stock_balances(club_id,product_id,variant_id,location_id)
  where variant_id is not null;
create index if not exists inventory_stock_balances_club_location_idx
  on public.inventory_stock_balances(club_id,location_id,product_id);
create index if not exists inventory_stock_balances_product_idx
  on public.inventory_stock_balances(product_id,variant_id);

alter table public.inventory_stock_balances enable row level security;
drop policy if exists inventory_stock_balances_read on public.inventory_stock_balances;
create policy inventory_stock_balances_read
on public.inventory_stock_balances for select to authenticated
using (public.has_club_permission(club_id,'viewInventory'));

revoke all on table public.inventory_stock_balances from public, anon;
revoke insert,update,delete,truncate,references,trigger on table public.inventory_stock_balances from authenticated;
grant select on table public.inventory_stock_balances to authenticated;

drop policy if exists inventory_locations_manage on public.inventory_locations;
create policy inventory_locations_manage
on public.inventory_locations for all to authenticated
using (
  public.has_club_permission(club_id,'manageInventory')
  or public.has_club_permission(club_id,'manageAssets')
)
with check (
  public.has_club_permission(club_id,'manageInventory')
  or public.has_club_permission(club_id,'manageAssets')
);

create or replace function public.inventory_default_location_v1(
  target_club uuid,
  p_area text
)
returns uuid
language plpgsql
security definer
stable
set search_path=public
as $$
declare v_location uuid;
begin
  select id into v_location
  from public.inventory_locations
  where club_id=target_club and active=true
    and lower(name)=lower(case when p_area='bar' then 'Club House' else 'Armazém' end)
  order by created_at
  limit 1;
  if v_location is null then
    raise exception 'Local padrão de inventário não configurado.';
  end if;
  return v_location;
end $$;

revoke all on function public.inventory_default_location_v1(uuid,text) from public, anon, authenticated;

create or replace function public.inventory_balance_apply_internal_v1(
  target_club uuid,
  p_product uuid,
  p_variant uuid,
  p_location uuid,
  p_quantity_delta numeric,
  p_reserved_delta numeric default 0
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
  v_quantity numeric;
  v_reserved numeric;
  v_new_quantity numeric;
  v_new_reserved numeric;
begin
  if not exists (
    select 1 from public.products p
    where p.id=p_product and p.club_id=target_club
  ) then raise exception 'Produto inválido para o clube.'; end if;
  if p_variant is not null and not exists (
    select 1 from public.product_variants pv
    where pv.id=p_variant and pv.product_id=p_product
  ) then raise exception 'Variante inválida para o produto.'; end if;
  if not exists (
    select 1 from public.inventory_locations l
    where l.id=p_location and l.club_id=target_club and l.active=true
  ) then raise exception 'Local de inventário inválido.'; end if;

  select id,quantity,reserved_quantity into v_id,v_quantity,v_reserved
  from public.inventory_stock_balances b
  where b.club_id=target_club and b.product_id=p_product
    and b.location_id=p_location
    and b.variant_id is not distinct from p_variant
  for update;

  if v_id is null then
    v_quantity:=0;
    v_reserved:=0;
  end if;
  v_new_quantity:=v_quantity+coalesce(p_quantity_delta,0);
  v_new_reserved:=v_reserved+coalesce(p_reserved_delta,0);
  if v_new_quantity<0 then raise exception 'Stock insuficiente no local selecionado.'; end if;
  if v_new_reserved<0 or v_new_reserved>v_new_quantity then
    raise exception 'Reserva inválida para o stock do local.';
  end if;

  if v_id is null then
    insert into public.inventory_stock_balances(
      club_id,product_id,variant_id,location_id,quantity,reserved_quantity,updated_by
    ) values (
      target_club,p_product,p_variant,p_location,v_new_quantity,v_new_reserved,auth.uid()
    );
  else
    update public.inventory_stock_balances
    set quantity=v_new_quantity,
        reserved_quantity=v_new_reserved,
        updated_at=now(),
        updated_by=auth.uid()
    where id=v_id;
  end if;
end $$;

revoke all on function public.inventory_balance_apply_internal_v1(uuid,uuid,uuid,uuid,numeric,numeric)
from public, anon, authenticated;

insert into public.inventory_stock_balances(
  club_id,product_id,variant_id,location_id,quantity,reserved_quantity
)
select p.club_id,p.id,pv.id,
       public.inventory_default_location_v1(p.club_id,p.inventory_area),
       greatest(coalesce(pv.current_stock,0),0),
       greatest(least(coalesce(pv.reserved_stock,0),coalesce(pv.current_stock,0)),0)
from public.products p
join public.product_variants pv on pv.product_id=p.id and pv.active=true
where not exists (
  select 1 from public.inventory_stock_balances b
  where b.club_id=p.club_id and b.product_id=p.id and b.variant_id=pv.id
    and b.location_id=public.inventory_default_location_v1(p.club_id,p.inventory_area)
);

insert into public.inventory_stock_balances(
  club_id,product_id,variant_id,location_id,quantity,reserved_quantity
)
select p.club_id,p.id,null,
       public.inventory_default_location_v1(p.club_id,p.inventory_area),
       greatest(coalesce(p.current_stock,0),0),
       greatest(least(coalesce(p.reserved_stock,0),coalesce(p.current_stock,0)),0)
from public.products p
where not exists (select 1 from public.product_variants pv where pv.product_id=p.id and pv.active=true)
  and not exists (
    select 1 from public.inventory_stock_balances b
    where b.club_id=p.club_id and b.product_id=p.id and b.variant_id is null
      and b.location_id=public.inventory_default_location_v1(p.club_id,p.inventory_area)
  );

create or replace function public.inventory_product_balance_sync_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_old_stock numeric:=0;
  v_old_reserved numeric:=0;
  v_location uuid;
begin
  if coalesce(current_setting('bob.skip_stock_balance_sync',true),'')='1' then return new; end if;
  if exists(select 1 from public.product_variants pv where pv.product_id=new.id and pv.active=true) then return new; end if;
  if tg_op='UPDATE' then
    v_old_stock:=coalesce(old.current_stock,0);
    v_old_reserved:=coalesce(old.reserved_stock,0);
  end if;
  v_location:=public.inventory_default_location_v1(new.club_id,new.inventory_area);
  perform public.inventory_balance_apply_internal_v1(
    new.club_id,new.id,null,v_location,
    coalesce(new.current_stock,0)-v_old_stock,
    coalesce(new.reserved_stock,0)-v_old_reserved
  );
  return new;
end $$;

create or replace function public.inventory_variant_balance_sync_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_old_stock numeric:=0;
  v_old_reserved numeric:=0;
  v_club uuid;
  v_area text;
  v_location uuid;
begin
  if coalesce(current_setting('bob.skip_stock_balance_sync',true),'')='1' then return new; end if;
  select club_id,inventory_area into v_club,v_area from public.products where id=new.product_id;
  if tg_op='UPDATE' then
    v_old_stock:=coalesce(old.current_stock,0);
    v_old_reserved:=coalesce(old.reserved_stock,0);
  end if;
  v_location:=public.inventory_default_location_v1(v_club,v_area);
  delete from public.inventory_stock_balances
  where club_id=v_club and product_id=new.product_id and variant_id is null;
  perform public.inventory_balance_apply_internal_v1(
    v_club,new.product_id,new.id,v_location,
    coalesce(new.current_stock,0)-v_old_stock,
    coalesce(new.reserved_stock,0)-v_old_reserved
  );
  return new;
end $$;

revoke all on function public.inventory_product_balance_sync_v1() from public, anon, authenticated;
revoke all on function public.inventory_variant_balance_sync_v1() from public, anon, authenticated;

drop trigger if exists trg_inventory_product_balance_insert on public.products;
create trigger trg_inventory_product_balance_insert
after insert on public.products
for each row execute function public.inventory_product_balance_sync_v1();

drop trigger if exists trg_inventory_product_balance_update on public.products;
create trigger trg_inventory_product_balance_update
after update of current_stock,reserved_stock on public.products
for each row
when (old.current_stock is distinct from new.current_stock or old.reserved_stock is distinct from new.reserved_stock)
execute function public.inventory_product_balance_sync_v1();

drop trigger if exists trg_inventory_variant_balance_insert on public.product_variants;
create trigger trg_inventory_variant_balance_insert
after insert on public.product_variants
for each row execute function public.inventory_variant_balance_sync_v1();

drop trigger if exists trg_inventory_variant_balance_update on public.product_variants;
create trigger trg_inventory_variant_balance_update
after update of current_stock,reserved_stock on public.product_variants
for each row
when (old.current_stock is distinct from new.current_stock or old.reserved_stock is distinct from new.reserved_stock)
execute function public.inventory_variant_balance_sync_v1();

alter table public.stock_movements
  add column if not exists from_location_id uuid null references public.inventory_locations(id) on delete set null,
  add column if not exists to_location_id uuid null references public.inventory_locations(id) on delete set null,
  add column if not exists transfer_group_id uuid null;
create index if not exists stock_movements_from_location_idx on public.stock_movements(from_location_id,created_at desc);
create index if not exists stock_movements_to_location_idx on public.stock_movements(to_location_id,created_at desc);

create or replace function public.inventory_stock_movement_location_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_club uuid; v_area text; v_location uuid;
begin
  if new.from_location_id is not null or new.to_location_id is not null or new.kind='transfer' then return new; end if;
  select club_id,inventory_area into v_club,v_area from public.products where id=new.product_id;
  if v_club is null then return new; end if;
  v_location:=public.inventory_default_location_v1(v_club,v_area);
  if new.quantity<0 then new.from_location_id:=v_location; else new.to_location_id:=v_location; end if;
  return new;
end $$;
revoke all on function public.inventory_stock_movement_location_v1() from public, anon, authenticated;
drop trigger if exists trg_inventory_stock_movement_location on public.stock_movements;
create trigger trg_inventory_stock_movement_location
before insert on public.stock_movements
for each row execute function public.inventory_stock_movement_location_v1();

create or replace function public.inventory_stock_by_location_v1(target_club uuid)
returns table(
  location_id uuid,
  location_name text,
  location_type text,
  product_id uuid,
  product_name text,
  variant_id uuid,
  variant_name text,
  sku text,
  inventory_area text,
  unit text,
  quantity numeric,
  reserved_quantity numeric,
  available_quantity numeric
)
language plpgsql
security definer
stable
set search_path=public
as $$
begin
  if not public.has_club_permission(target_club,'viewInventory') then
    raise exception 'Sem permissão para consultar inventário.';
  end if;
  return query
  select b.location_id,l.name,l.location_type,b.product_id,p.name,b.variant_id,pv.name,
         coalesce(pv.sku,p.sku),p.inventory_area,p.unit,b.quantity,b.reserved_quantity,
         b.quantity-b.reserved_quantity
  from public.inventory_stock_balances b
  join public.inventory_locations l on l.id=b.location_id
  join public.products p on p.id=b.product_id
  left join public.product_variants pv on pv.id=b.variant_id
  where b.club_id=target_club and l.active=true and p.active=true
  order by l.name,p.name,pv.name nulls first;
end $$;

revoke all on function public.inventory_stock_by_location_v1(uuid) from public, anon;
grant execute on function public.inventory_stock_by_location_v1(uuid) to authenticated;

create or replace function public.inventory_transfer_v1(
  target_club uuid,
  p_product uuid,
  p_variant uuid,
  p_from_location uuid,
  p_to_location uuid,
  p_quantity numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_product public.products%rowtype;
  v_cost numeric;
  v_group uuid:=gen_random_uuid();
  v_source numeric;
  v_destination numeric;
begin
  if not public.has_club_permission(target_club,'manageInventory') then
    raise exception 'Sem permissão para transferir stock.';
  end if;
  if p_quantity is null or p_quantity<=0 then raise exception 'A quantidade deve ser superior a zero.'; end if;
  if p_from_location is null or p_to_location is null or p_from_location=p_to_location then
    raise exception 'Seleciona locais de origem e destino diferentes.';
  end if;
  select * into v_product from public.products
  where id=p_product and club_id=target_club and active=true;
  if not found then raise exception 'Produto não encontrado ou inativo.'; end if;
  if exists(select 1 from public.product_variants where product_id=p_product and active=true) and p_variant is null then
    raise exception 'Seleciona a variante do produto.';
  end if;
  if p_variant is not null and not exists(
    select 1 from public.product_variants where id=p_variant and product_id=p_product and active=true
  ) then raise exception 'Variante inválida.'; end if;
  if not exists(select 1 from public.inventory_locations where id=p_from_location and club_id=target_club and active=true)
     or not exists(select 1 from public.inventory_locations where id=p_to_location and club_id=target_club and active=true) then
    raise exception 'Local de inventário inválido.';
  end if;

  perform public.inventory_balance_apply_internal_v1(target_club,p_product,p_variant,p_from_location,-p_quantity,0);
  perform public.inventory_balance_apply_internal_v1(target_club,p_product,p_variant,p_to_location,p_quantity,0);

  select coalesce(pv.cost,v_product.cost) into v_cost
  from public.product_variants pv where pv.id=p_variant;
  if p_variant is null then v_cost:=v_product.cost; end if;

  insert into public.stock_movements(
    club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by,
    from_location_id,to_location_id,transfer_group_id
  ) values (
    target_club,p_product,p_variant,'transfer',p_quantity,coalesce(v_cost,0),
    coalesce(nullif(trim(coalesce(p_notes,'')),''),'Transferência entre localizações'),auth.uid(),
    p_from_location,p_to_location,v_group
  );

  select quantity into v_source from public.inventory_stock_balances
  where club_id=target_club and product_id=p_product and location_id=p_from_location
    and variant_id is not distinct from p_variant;
  select quantity into v_destination from public.inventory_stock_balances
  where club_id=target_club and product_id=p_product and location_id=p_to_location
    and variant_id is not distinct from p_variant;

  return jsonb_build_object(
    'transfer_group_id',v_group,
    'product_id',p_product,
    'variant_id',p_variant,
    'from_location_id',p_from_location,
    'to_location_id',p_to_location,
    'quantity',p_quantity,
    'source_quantity',coalesce(v_source,0),
    'destination_quantity',coalesce(v_destination,0)
  );
end $$;

revoke all on function public.inventory_transfer_v1(uuid,uuid,uuid,uuid,uuid,numeric,text) from public, anon;
grant execute on function public.inventory_transfer_v1(uuid,uuid,uuid,uuid,uuid,numeric,text) to authenticated;

create or replace function public.inventory_count_start_v1(
  target_club uuid,
  p_name text,
  p_location uuid default null,
  p_event uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare sid uuid;
begin
  if not public.has_club_permission(target_club,'performInventoryCount') then
    raise exception 'Sem permissão para realizar inventário físico.';
  end if;
  if p_location is not null and not exists (
    select 1 from public.inventory_locations l
    where l.id=p_location and l.club_id=target_club and l.active=true
  ) then raise exception 'Local de inventário inválido para este clube.'; end if;
  if p_event is not null and not exists (
    select 1 from public.events e where e.id=p_event and e.club_id=target_club
  ) then raise exception 'Evento inválido para este clube.'; end if;

  insert into public.inventory_count_sessions(club_id,name,location_id,event_id,status,notes,started_by)
  values(target_club,coalesce(nullif(trim(p_name),''),'Inventário físico'),p_location,p_event,'counting',nullif(trim(p_notes),''),auth.uid())
  returning id into sid;

  insert into public.inventory_count_items(session_id,product_id,variant_id,theoretical_qty,unit_cost)
  select sid,p.id,pv.id,
         case when p_location is null then pv.current_stock else coalesce(b.quantity,0) end,
         coalesce(pv.cost,p.cost,0)
  from public.products p
  join public.product_variants pv on pv.product_id=p.id and pv.active=true
  left join public.inventory_stock_balances b
    on b.club_id=p.club_id and b.product_id=p.id and b.variant_id=pv.id and b.location_id=p_location
  where p.club_id=target_club and p.active=true;

  insert into public.inventory_count_items(session_id,product_id,variant_id,theoretical_qty,unit_cost)
  select sid,p.id,null,
         case when p_location is null then p.current_stock else coalesce(b.quantity,0) end,
         coalesce(p.cost,0)
  from public.products p
  left join public.inventory_stock_balances b
    on b.club_id=p.club_id and b.product_id=p.id and b.variant_id is null and b.location_id=p_location
  where p.club_id=target_club and p.active=true
    and not exists(select 1 from public.product_variants pv where pv.product_id=p.id and pv.active=true);

  return sid;
end $$;

create or replace function public.inventory_count_finalize_v1(target_club uuid,p_session uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r record;
  s public.inventory_count_sessions%rowtype;
  adjusted int:=0;
  total_diff numeric:=0;
  value_diff numeric:=0;
begin
  if not public.has_club_permission(target_club,'performInventoryCount') then
    raise exception 'Sem permissão para concluir inventário físico.';
  end if;
  select * into s from public.inventory_count_sessions
  where id=p_session and club_id=target_club and status in ('counting','review')
  for update;
  if not found then raise exception 'Sessão não encontrada ou já concluída.'; end if;
  if exists(select 1 from public.inventory_count_items where session_id=p_session and counted_qty is null) then
    raise exception 'Existem artigos por contar.';
  end if;
  if exists(select 1 from public.inventory_count_items where session_id=p_session and counted_qty<0) then
    raise exception 'Existem quantidades negativas na contagem.';
  end if;

  if s.location_id is not null then
    perform set_config('bob.skip_stock_balance_sync','1',true);
  end if;

  for r in select * from public.inventory_count_items where session_id=p_session loop
    if r.difference<>0 then
      if s.location_id is null then
        if r.variant_id is null then
          update public.products set current_stock=r.counted_qty
          where id=r.product_id and club_id=target_club;
        else
          update public.product_variants set current_stock=r.counted_qty
          where id=r.variant_id and product_id=r.product_id;
        end if;
      else
        perform public.inventory_balance_apply_internal_v1(
          target_club,r.product_id,r.variant_id,s.location_id,r.difference,0
        );
        if r.variant_id is null then
          update public.products p
          set current_stock=(
            select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b
            where b.club_id=target_club and b.product_id=p.id and b.variant_id is null
          )
          where p.id=r.product_id and p.club_id=target_club;
        else
          update public.product_variants pv
          set current_stock=(
            select coalesce(sum(b.quantity),0) from public.inventory_stock_balances b
            where b.club_id=target_club and b.product_id=r.product_id and b.variant_id=pv.id
          )
          where pv.id=r.variant_id and pv.product_id=r.product_id;
        end if;
      end if;

      insert into public.stock_movements(
        club_id,product_id,variant_id,kind,quantity,unit_cost,notes,created_by,
        from_location_id,to_location_id
      ) values (
        target_club,r.product_id,r.variant_id,'adjustment',r.difference,r.unit_cost,
        'Ajuste por inventário físico '||p_session::text,auth.uid(),
        case when r.difference<0 then s.location_id else null end,
        case when r.difference>0 then s.location_id else null end
      );
      adjusted:=adjusted+1;
      total_diff:=total_diff+r.difference;
      value_diff:=value_diff+(r.difference*r.unit_cost);
    end if;
  end loop;

  update public.products p
  set current_stock=(select coalesce(sum(pv.current_stock),0) from public.product_variants pv where pv.product_id=p.id and pv.active=true)
  where p.club_id=target_club
    and exists(select 1 from public.inventory_count_items i where i.session_id=p_session and i.product_id=p.id and i.variant_id is not null);

  if s.location_id is not null then
    perform set_config('bob.skip_stock_balance_sync','0',true);
  end if;

  update public.inventory_count_sessions
  set status='completed',completed_by=auth.uid(),completed_at=now()
  where id=p_session and club_id=target_club;

  return jsonb_build_object(
    'adjusted_items',adjusted,
    'net_quantity_difference',total_diff,
    'value_difference',value_diff,
    'location_id',s.location_id
  );
end $$;

revoke all on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) from public, anon;
revoke all on function public.inventory_count_finalize_v1(uuid,uuid) from public, anon;
grant execute on function public.inventory_count_start_v1(uuid,text,uuid,uuid,text) to authenticated;
grant execute on function public.inventory_count_finalize_v1(uuid,uuid) to authenticated;
