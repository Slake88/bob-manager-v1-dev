-- Bar: selectable treasury account + dedicated permission.
-- President and Treasurer receive it by default; Super Admin is automatically allowed by has_club_permission().

alter table public.club_role_permissions disable trigger user;
insert into public.club_role_permissions (club_id, role_key, permission_key, allowed, updated_by, updated_at)
select c.id, r.role_key, 'selectBarFinancialAccount', true, null, now()
from public.clubs c
cross join (values ('president'), ('treasurer')) as r(role_key)
on conflict (club_id, role_key, permission_key)
do update set allowed=excluded.allowed, updated_at=excluded.updated_at;
alter table public.club_role_permissions enable trigger user;

create or replace function public.bar_operation_v2(
  target_club uuid,
  p_product uuid,
  p_operation text,
  p_quantity numeric,
  p_event uuid default null,
  p_purchase_units numeric default null,
  p_unit_price numeric default null,
  p_payment_method text default null,
  p_notes text default null,
  p_post_financial boolean default true,
  p_account uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_product public.products%rowtype;
  v_delta numeric;
  v_new_stock numeric;
  v_total numeric:=0;
  v_kind public.stock_movement_kind;
  v_account uuid;
  v_cost_center uuid;
  v_tx uuid;
  v_desc text;
  v_purchase_unit_cost numeric;
  v_new_average_cost numeric;
begin
  if not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para gerir o Bar.';
  end if;
  if p_quantity<=0 then raise exception 'A quantidade deve ser superior a zero.'; end if;

  select * into v_product
  from public.products
  where id=p_product and club_id=target_club and inventory_area='bar' and active=true
  for update;
  if not found then raise exception 'Artigo de Bar não encontrado ou inativo.'; end if;

  if p_event is not null and not exists(select 1 from public.events where id=p_event and club_id=target_club) then
    raise exception 'Evento inválido.';
  end if;

  if p_operation in ('purchase','adjustment_in') then v_delta:=p_quantity; else v_delta:=-p_quantity; end if;
  v_new_stock:=coalesce(v_product.current_stock,0)+v_delta;
  if v_new_stock<0 then raise exception 'Stock insuficiente. Disponível: %',coalesce(v_product.current_stock,0); end if;

  if p_operation='purchase' then v_kind:='purchase';
  elsif p_operation='sale' then v_kind:='sale';
  elsif p_operation='waste' then v_kind:='loss';
  elsif p_operation in ('offer','internal') then v_kind:='event_consumption';
  else v_kind:='adjustment'; end if;

  v_total:=case
    when p_operation='purchase' then coalesce(p_purchase_units,0)*coalesce(p_unit_price,v_product.purchase_cost,0)
    when p_operation='sale' then p_quantity*coalesce(p_unit_price,v_product.sale_price,0)
    else 0
  end;

  if p_operation='purchase' then
    if coalesce(v_product.units_per_purchase,0)<=0 then raise exception 'Conversão da embalagem de compra inválida.'; end if;
    v_purchase_unit_cost:=coalesce(p_unit_price,v_product.purchase_cost,0)/v_product.units_per_purchase;
    if v_new_stock>0 then
      v_new_average_cost:=((coalesce(v_product.current_stock,0)*coalesce(v_product.cost,0))+(p_quantity*v_purchase_unit_cost))/v_new_stock;
    else
      v_new_average_cost:=v_purchase_unit_cost;
    end if;
    update public.products
      set current_stock=v_new_stock,
          purchase_cost=coalesce(p_unit_price,purchase_cost),
          cost=v_new_average_cost
      where id=v_product.id;
  else
    update public.products set current_stock=v_new_stock where id=v_product.id;
  end if;

  insert into public.stock_movements(club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by)
  values(target_club,p_product,p_event,v_kind,v_delta,
    case when p_operation='purchase' then v_purchase_unit_cost else coalesce(v_product.cost,0) end,
    nullif(trim(coalesce(p_notes,'')),''),auth.uid());

  v_desc:=case p_operation
    when 'purchase' then 'Compra Bar - '
    when 'sale' then 'Venda Bar - '
    when 'offer' then 'Oferta Bar - '
    when 'internal' then 'Consumo interno Bar - '
    when 'waste' then 'Quebra Bar - '
    else 'Ajuste Bar - '
  end || v_product.name;

  if p_post_financial and p_operation in ('purchase','sale') and v_total>0 then
    if p_account is not null then
      if not public.has_club_permission(target_club,'selectBarFinancialAccount') then
        raise exception 'Sem autorização para escolher a conta financeira do Bar.';
      end if;
      select id into v_account from public.treasury_accounts
      where id=p_account and club_id=target_club and active=true;
      if v_account is null then raise exception 'Conta financeira inválida ou inativa.'; end if;
    else
      select id into v_account from public.treasury_accounts
      where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;
      if v_account is null then
        select id into v_account from public.treasury_accounts
        where club_id=target_club and active=true order by created_at limit 1;
      end if;
      if v_account is null then raise exception 'Não existe nenhuma conta financeira ativa.'; end if;
    end if;

    select id into v_cost_center from public.cost_centers
    where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;

    insert into public.treasury_transactions(
      club_id,kind,account_id,cost_center_id,event_id,transaction_date,description,amount,payment_method,source_type,source_id,created_by
    ) values(
      target_club,
      case when p_operation='sale' then 'income'::public.transaction_kind else 'expense'::public.transaction_kind end,
      v_account,v_cost_center,p_event,current_date,v_desc,v_total,p_payment_method,'bar_operation',p_product,auth.uid()
    ) returning id into v_tx;
  end if;

  insert into public.bar_operations(
    club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,payment_method,notes,treasury_transaction_id,created_by
  ) values(
    target_club,p_product,p_event,p_operation,p_purchase_units,p_quantity,coalesce(p_unit_price,0),v_total,p_payment_method,
    nullif(trim(coalesce(p_notes,'')),''),v_tx,auth.uid()
  );

  perform public.emit_domain_event(
    target_club,'BarOperationRecorded','inventory',p_product,
    jsonb_build_object('title',v_desc,'description',p_quantity::text||' '||coalesce(v_product.consumption_unit,v_product.unit,'unid.'),
      'module_code','inventory','route','inventory','priority',case when v_new_stock<=coalesce(v_product.minimum_stock,0) then 'medium' else 'low' end)
  );

  return jsonb_build_object(
    'product_id',p_product,'current_stock',v_new_stock,
    'average_unit_cost',case when p_operation='purchase' then v_new_average_cost else coalesce(v_product.cost,0) end,
    'transaction_id',v_tx,'account_id',v_account
  );
end;
$$;

grant execute on function public.bar_operation_v2(uuid,uuid,text,numeric,uuid,numeric,numeric,text,text,boolean,uuid) to authenticated;
