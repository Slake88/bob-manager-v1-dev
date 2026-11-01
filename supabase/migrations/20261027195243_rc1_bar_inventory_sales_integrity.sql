-- Bar/Inventory stock and sales integrity hardening.
-- Keeps non-Bar sellInventory sales while requiring manageBar for Bar products.

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
as $function$
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
  if p_operation = 'sale' then
    if not public.has_club_permission(target_club, 'sellInventory') then
      raise exception 'Sem autorização para registar vendas.' using errcode = '42501';
    end if;
  elsif not public.has_club_permission(target_club, 'manageInventory') then
    raise exception 'Sem autorização para gerir inventário.' using errcode = '42501';
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

  -- Inventory sales remain available for non-Bar stock. Bar stock must pass
  -- through an actor with the effective Bar permission.
  if p_operation = 'sale'
     and v_product.inventory_area = 'bar'
     and not public.has_club_permission(target_club, 'manageBar') then
    raise exception 'A venda de artigos do Bar requer a permissão manageBar.'
      using errcode = '42501';
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
$function$;

-- RLS policies are permissive by default and combine with OR. These restrictive
-- policies AND with every permissive policy, so no client can mutate the stock
-- ledger directly. Real application writes use SECURITY DEFINER RPCs owned by
-- the table owner; RLS is enabled but not FORCE-enabled on this table.
drop policy if exists stock_movements_no_client_sale_insert_v1
  on public.stock_movements;
drop policy if exists stock_movements_no_direct_insert_v1
  on public.stock_movements;
drop policy if exists stock_movements_no_direct_update_v1
  on public.stock_movements;
drop policy if exists stock_movements_no_direct_delete_v1
  on public.stock_movements;
create policy stock_movements_no_direct_insert_v1
  on public.stock_movements as restrictive
  for insert to authenticated
  with check (false);
create policy stock_movements_no_direct_update_v1
  on public.stock_movements as restrictive
  for update to authenticated
  using (false)
  with check (false);
create policy stock_movements_no_direct_delete_v1
  on public.stock_movements as restrictive
  for delete to authenticated
  using (false);

-- Deleting a product cascades into stock_movements and Bar operation history.
-- The real client archives products; privileged import rollback remains a
-- SECURITY DEFINER path owned by the table owner and is unaffected because
-- FORCE ROW LEVEL SECURITY is not enabled on products.
drop policy if exists products_no_client_delete_v1 on public.products;
create policy products_no_client_delete_v1
  on public.products as restrictive
  for delete to authenticated
  using (false);

-- Clients may edit product metadata, but stock totals must only be changed by
-- the table owner's checked SECURITY DEFINER operations (Bar, Inventory,
-- inventory counts and reversals), not by direct PostgREST UPDATE.
create or replace function bob_dinner_private.guard_products_stock_write_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $function$
declare
  v_owner name;
begin
  if new.current_stock is distinct from old.current_stock
     or new.reserved_stock is distinct from old.reserved_stock then
    select r.rolname into v_owner
    from pg_catalog.pg_class c
    join pg_catalog.pg_roles r on r.oid = c.relowner
    where c.oid = 'public.products'::regclass;

    if v_owner is null or current_user <> v_owner then
      raise exception 'O stock só pode ser alterado por operações autorizadas de Bar/Inventário.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function bob_dinner_private.guard_products_stock_write_v1()
  from public, anon, authenticated;

drop trigger if exists trg_guard_products_stock_write_v1 on public.products;
create trigger trg_guard_products_stock_write_v1
  before update of current_stock, reserved_stock on public.products
  for each row execute function bob_dinner_private.guard_products_stock_write_v1();
