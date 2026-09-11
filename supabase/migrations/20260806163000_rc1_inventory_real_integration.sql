alter table public.products
  add column if not exists reserved_stock numeric not null default 0;

insert into public.treasury_accounts (
  club_id, name, account_type, opening_balance, opening_date,
  active, icon, allows_negative
)
select c.id, 'Club House', 'fund', 0, current_date, true, '🏠', false
from public.clubs c
where not exists (
  select 1 from public.treasury_accounts a
  where a.club_id = c.id and lower(a.name) = lower('Club House')
);

insert into public.cost_centers (club_id, name, code, active)
select c.id, 'Club House', 'CLUB_HOUSE', true
from public.clubs c
where not exists (
  select 1 from public.cost_centers cc
  where cc.club_id = c.id and lower(cc.name) = lower('Club House')
);

create or replace function public.inventory_operation_v1(
  target_club uuid,
  p_product uuid,
  p_operation text,
  p_quantity numeric,
  p_unit_price numeric default null,
  p_description text default null,
  p_payment_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products%rowtype;
  v_new_stock numeric;
  v_new_reserved numeric;
  v_account uuid;
  v_cost_center uuid;
  v_transaction uuid;
  v_kind public.stock_movement_kind;
  v_total numeric;
begin
  if not public.has_club_role(
    target_club,
    array['inventory_manager', 'treasurer', 'admin', 'super_admin']
  ) then
    raise exception 'Sem autorização.';
  end if;

  if p_quantity <= 0 then
    raise exception 'A quantidade deve ser superior a zero.';
  end if;

  select * into v_product
  from public.products
  where id = p_product
    and club_id = target_club
    and active = true
  for update;

  if not found then
    raise exception 'Artigo não encontrado ou inativo.';
  end if;

  v_new_stock := v_product.current_stock;
  v_new_reserved := v_product.reserved_stock;

  if p_operation = 'entry' then
    v_new_stock := v_new_stock + p_quantity;
    v_kind := 'purchase';
  elsif p_operation = 'adjustment_in' then
    v_new_stock := v_new_stock + p_quantity;
    v_kind := 'adjustment';
  elsif p_operation = 'adjustment_out' then
    v_new_stock := v_new_stock - p_quantity;
    v_kind := 'adjustment';
  elsif p_operation = 'reserve' then
    if v_new_stock - v_new_reserved < p_quantity then
      raise exception 'Stock disponível insuficiente para a reserva.';
    end if;
    v_new_reserved := v_new_reserved + p_quantity;
    v_kind := 'transfer';
  elsif p_operation = 'release' then
    if v_new_reserved < p_quantity then
      raise exception 'Reserva insuficiente.';
    end if;
    v_new_reserved := v_new_reserved - p_quantity;
    v_kind := 'return';
  elsif p_operation = 'sale' then
    if v_new_stock - v_new_reserved < p_quantity then
      raise exception 'Stock disponível insuficiente para a venda.';
    end if;
    v_new_stock := v_new_stock - p_quantity;
    v_kind := 'sale';
  else
    raise exception 'Operação de inventário inválida.';
  end if;

  if v_new_stock < 0
      or v_new_reserved < 0
      or v_new_reserved > v_new_stock then
    raise exception 'O stock não pode ficar negativo nem abaixo do stock reservado.';
  end if;

  update public.products
  set current_stock = v_new_stock,
      reserved_stock = v_new_reserved
  where id = v_product.id;

  insert into public.stock_movements (
    club_id, product_id, kind, quantity, unit_cost, notes, created_by
  )
  values (
    target_club,
    v_product.id,
    v_kind,
    case
      when p_operation in ('adjustment_out', 'sale') then -p_quantity
      else p_quantity
    end,
    coalesce(p_unit_price, v_product.cost),
    nullif(trim(coalesce(p_description, '')), ''),
    auth.uid()
  );

  if p_operation = 'sale' then
    v_total := p_quantity * coalesce(p_unit_price, v_product.sale_price);

    select id into v_account
    from public.treasury_accounts
    where club_id = target_club
      and active = true
      and lower(name) = lower('Club House')
    limit 1;

    if v_account is null then
      raise exception 'Conta Club House não encontrada.';
    end if;

    select id into v_cost_center
    from public.cost_centers
    where club_id = target_club
      and active = true
      and lower(name) = lower('Club House')
    limit 1;

    insert into public.treasury_transactions (
      club_id, kind, account_id, cost_center_id, transaction_date,
      description, amount, payment_method, source_type, source_id, created_by
    )
    values (
      target_club,
      'income',
      v_account,
      v_cost_center,
      current_date,
      coalesce(
        nullif(trim(coalesce(p_description, '')), ''),
        'Venda ' || v_product.name
      ),
      v_total,
      p_payment_method,
      'inventory_sale',
      v_product.id,
      auth.uid()
    )
    returning id into v_transaction;
  end if;

  return jsonb_build_object(
    'product_id', v_product.id,
    'current_stock', v_new_stock,
    'reserved_stock', v_new_reserved,
    'transaction_id', v_transaction
  );
end;
$$;

revoke all on function public.inventory_operation_v1(
  uuid, uuid, text, numeric, numeric, text, text
) from public, anon;

grant execute on function public.inventory_operation_v1(
  uuid, uuid, text, numeric, numeric, text, text
) to authenticated;

alter table public.products enable row level security;
alter table public.stock_movements enable row level security;

drop policy if exists products_access on public.products;
drop policy if exists products_manage on public.products;
drop policy if exists products_read on public.products;
drop policy if exists products_select on public.products;
drop policy if exists products_insert on public.products;
drop policy if exists products_update on public.products;
drop policy if exists products_delete on public.products;

create policy products_select
on public.products for select to authenticated
using (public.has_club_access(club_id));

create policy products_insert
on public.products for insert to authenticated
with check (
  public.has_club_role(
    club_id,
    array['inventory_manager', 'admin', 'super_admin']
  )
);

create policy products_update
on public.products for update to authenticated
using (
  public.has_club_role(
    club_id,
    array['inventory_manager', 'admin', 'super_admin']
  )
)
with check (
  public.has_club_role(
    club_id,
    array['inventory_manager', 'admin', 'super_admin']
  )
);

create policy products_delete
on public.products for delete to authenticated
using (
  public.has_club_role(club_id, array['admin', 'super_admin'])
);

drop policy if exists stock_movements_access on public.stock_movements;
drop policy if exists stock_movements_manage on public.stock_movements;
drop policy if exists stock_movements_read on public.stock_movements;
drop policy if exists stock_movements_select on public.stock_movements;
drop policy if exists stock_movements_insert on public.stock_movements;

create policy stock_movements_select
on public.stock_movements for select to authenticated
using (public.has_club_access(club_id));

create policy stock_movements_insert
on public.stock_movements for insert to authenticated
with check (
  public.has_club_role(
    club_id,
    array['inventory_manager', 'treasurer', 'admin', 'super_admin']
  )
  and created_by = auth.uid()
);
