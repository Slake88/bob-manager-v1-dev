create table public.bar_product_sale_options (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null,
  stock_quantity numeric(12,3) not null check (stock_quantity > 0),
  public_price numeric(12,2) not null default 0 check (public_price >= 0),
  member_price numeric(12,2) not null default 0 check (member_price >= 0),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now()
);

create unique index bar_product_sale_options_product_name_uq
  on public.bar_product_sale_options(product_id, lower(name));
create index bar_product_sale_options_product_idx
  on public.bar_product_sale_options(product_id, active, sort_order, name);

alter table public.bar_product_sale_options enable row level security;
create policy bar_product_sale_options_select
on public.bar_product_sale_options for select to authenticated
using (public.has_club_permission(club_id, 'viewBar'));
create policy bar_product_sale_options_manage
on public.bar_product_sale_options for all to authenticated
using (public.has_club_permission(club_id, 'manageBar'))
with check (public.has_club_permission(club_id, 'manageBar'));
revoke all on public.bar_product_sale_options from anon;
grant select, insert, update, delete on public.bar_product_sale_options to authenticated;

insert into public.bar_product_sale_options(
  club_id, product_id, name, stock_quantity, public_price, member_price,
  sort_order, active, created_by, updated_by
)
select
  p.club_id,
  p.id,
  case
    when nullif(btrim(coalesce(p.consumption_unit,'')),'') is null then 'Unidade'
    when lower(btrim(p.consumption_unit)) in ('1','unit','unidade','unid.') then 'Unidade'
    else btrim(p.consumption_unit)
  end,
  1,
  coalesce(p.sale_price,0),
  coalesce(p.sale_price,0),
  10,
  p.active,
  p.created_by,
  coalesce(p.updated_by,p.created_by)
from public.products p
where p.inventory_area='bar'
  and not exists (
    select 1 from public.bar_product_sale_options o where o.product_id=p.id
  );

alter table public.bar_sales
  add column customer_type text not null default 'public',
  add column member_id uuid references public.members(id) on delete set null;
alter table public.bar_sales
  add constraint bar_sales_customer_type_check check (customer_type in ('public','member'));
create index bar_sales_member_idx on public.bar_sales(club_id, member_id, completed_at desc);

alter table public.bar_sale_items
  add column sale_option_id uuid references public.bar_product_sale_options(id) on delete set null,
  add column sale_option_name text,
  add column stock_quantity_per_unit numeric(12,3),
  add column price_tier text;
alter table public.bar_sale_items
  add constraint bar_sale_items_stock_quantity_check
    check (stock_quantity_per_unit is null or stock_quantity_per_unit > 0),
  add constraint bar_sale_items_price_tier_check
    check (price_tier is null or price_tier in ('public','member'));

alter table public.bar_operations
  add column sale_id uuid references public.bar_sales(id) on delete set null,
  add column sale_option_id uuid references public.bar_product_sale_options(id) on delete set null,
  add column sale_option_name text,
  add column customer_type text;
alter table public.bar_operations
  add constraint bar_operations_customer_type_check
    check (customer_type is null or customer_type in ('public','member'));
create index bar_operations_sale_idx on public.bar_operations(sale_id);

create or replace function public.save_bar_product_v3(
  target_club uuid,
  p_product uuid,
  p_name text,
  p_sku text,
  p_category text,
  p_description text,
  p_supplier text,
  p_purchase_unit text,
  p_consumption_unit text,
  p_units_per_purchase numeric,
  p_purchase_cost numeric,
  p_minimum_stock numeric,
  p_sale_options jsonb
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_product_id uuid;
  v_option jsonb;
  v_option_id uuid;
  v_name text;
  v_stock_quantity numeric;
  v_public_price numeric;
  v_member_price numeric;
  v_sort integer;
  v_first_public numeric:=0;
  v_count integer:=0;
  v_updated integer;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para gerir artigos do Bar.';
  end if;
  if nullif(btrim(coalesce(p_name,'')),'') is null then
    raise exception 'Indica o nome do artigo.';
  end if;
  if coalesce(p_units_per_purchase,0)<=0 then
    raise exception 'A quantidade por embalagem de compra deve ser superior a zero.';
  end if;
  if coalesce(p_purchase_cost,0)<0 or coalesce(p_minimum_stock,0)<0 then
    raise exception 'Custos e stock mínimo não podem ser negativos.';
  end if;
  if p_sale_options is null or jsonb_typeof(p_sale_options)<>'array' or jsonb_array_length(p_sale_options)=0 then
    raise exception 'Define pelo menos uma forma de venda.';
  end if;

  for v_option in select value from jsonb_array_elements(p_sale_options)
  loop
    v_name:=nullif(btrim(coalesce(v_option->>'name','')),'');
    if v_name is null then raise exception 'Todas as formas de venda precisam de nome.'; end if;
    begin
      v_stock_quantity:=(v_option->>'stock_quantity')::numeric;
      v_public_price:=(v_option->>'public_price')::numeric;
      v_member_price:=(v_option->>'member_price')::numeric;
    exception when others then
      raise exception 'Quantidade ou preço inválido numa forma de venda.';
    end;
    if coalesce(v_stock_quantity,0)<=0 then raise exception 'A quantidade de stock por venda deve ser superior a zero.'; end if;
    if coalesce(v_public_price,0)<0 or coalesce(v_member_price,0)<0 then raise exception 'Os preços não podem ser negativos.'; end if;
    v_count:=v_count+1;
    if v_count=1 then v_first_public:=v_public_price; end if;
  end loop;

  if p_product is null then
    insert into public.products(
      club_id,inventory_area,name,sku,category,description,supplier,unit,
      purchase_unit,consumption_unit,units_per_purchase,purchase_cost,cost,
      sale_price,minimum_stock,current_stock,reserved_stock,active,created_by,updated_by
    ) values (
      target_club,'bar',btrim(p_name),nullif(btrim(coalesce(p_sku,'')),''),
      coalesce(nullif(btrim(coalesce(p_category,'')),''),'Bebidas'),
      nullif(btrim(coalesce(p_description,'')),''),nullif(btrim(coalesce(p_supplier,'')),''),
      coalesce(nullif(btrim(coalesce(p_consumption_unit,'')),''),'unidade'),
      coalesce(nullif(btrim(coalesce(p_purchase_unit,'')),''),'unidade'),
      coalesce(nullif(btrim(coalesce(p_consumption_unit,'')),''),'unidade'),
      p_units_per_purchase,coalesce(p_purchase_cost,0),coalesce(p_purchase_cost,0)/p_units_per_purchase,
      v_first_public,coalesce(p_minimum_stock,0),0,0,true,auth.uid(),auth.uid()
    ) returning id into v_product_id;
  else
    select id into v_product_id
    from public.products
    where id=p_product and club_id=target_club and inventory_area='bar'
    for update;
    if v_product_id is null then raise exception 'Artigo do Bar não encontrado.'; end if;

    update public.products set
      name=btrim(p_name),
      sku=nullif(btrim(coalesce(p_sku,'')),''),
      category=coalesce(nullif(btrim(coalesce(p_category,'')),''),'Bebidas'),
      description=nullif(btrim(coalesce(p_description,'')),''),
      supplier=nullif(btrim(coalesce(p_supplier,'')),''),
      unit=coalesce(nullif(btrim(coalesce(p_consumption_unit,'')),''),'unidade'),
      purchase_unit=coalesce(nullif(btrim(coalesce(p_purchase_unit,'')),''),'unidade'),
      consumption_unit=coalesce(nullif(btrim(coalesce(p_consumption_unit,'')),''),'unidade'),
      units_per_purchase=p_units_per_purchase,
      purchase_cost=coalesce(p_purchase_cost,0),
      cost=coalesce(p_purchase_cost,0)/p_units_per_purchase,
      sale_price=v_first_public,
      minimum_stock=coalesce(p_minimum_stock,0),
      updated_by=auth.uid(),updated_at=now()
    where id=v_product_id;

    update public.bar_product_sale_options
    set active=false, updated_by=auth.uid(), updated_at=now()
    where product_id=v_product_id and club_id=target_club;
  end if;

  v_sort:=0;
  for v_option in select value from jsonb_array_elements(p_sale_options)
  loop
    v_sort:=v_sort+10;
    v_name:=btrim(v_option->>'name');
    v_stock_quantity:=(v_option->>'stock_quantity')::numeric;
    v_public_price:=(v_option->>'public_price')::numeric;
    v_member_price:=(v_option->>'member_price')::numeric;
    v_option_id:=null;
    begin
      if nullif(v_option->>'id','') is not null then v_option_id:=(v_option->>'id')::uuid; end if;
    exception when others then
      raise exception 'Identificador inválido numa forma de venda.';
    end;

    if v_option_id is not null then
      update public.bar_product_sale_options set
        name=v_name,stock_quantity=v_stock_quantity,public_price=v_public_price,
        member_price=v_member_price,sort_order=v_sort,active=true,
        updated_by=auth.uid(),updated_at=now()
      where id=v_option_id and product_id=v_product_id and club_id=target_club;
      get diagnostics v_updated = row_count;
      if v_updated=0 then raise exception 'Forma de venda inválida para este artigo.'; end if;
    else
      insert into public.bar_product_sale_options(
        club_id,product_id,name,stock_quantity,public_price,member_price,sort_order,active,created_by,updated_by
      ) values (
        target_club,v_product_id,v_name,v_stock_quantity,v_public_price,v_member_price,v_sort,true,auth.uid(),auth.uid()
      );
    end if;
  end loop;

  return jsonb_build_object('id',v_product_id);
end;
$$;
revoke all on function public.save_bar_product_v3(uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,jsonb) from public,anon;
grant execute on function public.save_bar_product_v3(uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,jsonb) to authenticated;

create or replace function public.create_bar_sale_v2(
  target_club uuid,
  p_customer_label text default null,
  p_customer_type text default 'public',
  p_member uuid default null,
  p_source_mode text default 'manual',
  p_event uuid default null,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_id uuid;
  v_label text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para criar vendas no Bar.';
  end if;
  if p_source_mode not in ('manual','ocr') then raise exception 'Modo de venda inválido.'; end if;
  if p_customer_type not in ('public','member') then raise exception 'Tipo de cliente inválido.'; end if;
  if p_event is not null and not exists(select 1 from public.events where id=p_event and club_id=target_club) then
    raise exception 'Evento inválido.';
  end if;
  if p_member is not null then
    if p_customer_type<>'member' then raise exception 'Um membro só pode ser associado a preço de membro.'; end if;
    select coalesce(nullif(btrim(nickname),''),full_name) into v_label
    from public.members
    where id=p_member and club_id=target_club and status::text in ('active','full_color','honorary');
    if v_label is null then raise exception 'Membro inválido ou sem acesso ao preço de membro.'; end if;
  end if;
  v_label:=coalesce(nullif(btrim(coalesce(p_customer_label,'')),''),v_label);
  if p_customer_type='member' and p_member is null and v_label is null then
    raise exception 'Indica o membro ou o nome da conta de grupo.';
  end if;

  insert into public.bar_sales(
    club_id,event_id,source_mode,status,customer_label,customer_type,member_id,
    notes,created_by,updated_by
  ) values (
    target_club,p_event,p_source_mode,'draft',v_label,p_customer_type,p_member,
    nullif(btrim(coalesce(p_notes,'')),''),auth.uid(),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.create_bar_sale_v2(uuid,text,text,uuid,text,uuid,text) from public,anon;
grant execute on function public.create_bar_sale_v2(uuid,text,text,uuid,text,uuid,text) to authenticated;

create or replace function public.complete_bar_sale_v2(
  target_club uuid,
  p_sale uuid,
  p_lines jsonb,
  p_payment_method text,
  p_account uuid default null,
  p_customer_label text default null,
  p_customer_type text default 'public',
  p_member uuid default null,
  p_event uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path='public'
as $$
declare
  v_sale public.bar_sales%rowtype;
  r jsonb;
  v_kind text;
  v_product_id uuid;
  v_preset_id uuid;
  v_option_id uuid;
  v_product public.products%rowtype;
  v_preset public.bar_sale_presets%rowtype;
  v_option public.bar_product_sale_options%rowtype;
  v_description text;
  v_quantity numeric;
  v_stock_per_unit numeric;
  v_stock_total numeric;
  v_unit_price numeric;
  v_line_total numeric;
  v_total numeric:=0;
  v_account uuid;
  v_cost_center uuid;
  v_tx uuid;
  v_new_stock numeric;
  v_event uuid;
  v_customer text;
  v_notes text;
  v_line_count integer:=0;
  v_member_label text;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para concluir vendas no Bar.';
  end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Adiciona pelo menos um artigo à venda.';
  end if;
  if nullif(btrim(coalesce(p_payment_method,'')),'') is null then raise exception 'Seleciona o método de pagamento.'; end if;
  if p_customer_type not in ('public','member') then raise exception 'Tipo de cliente inválido.'; end if;

  select * into v_sale from public.bar_sales
  where id=p_sale and club_id=target_club for update;
  if not found then raise exception 'Venda do Bar não encontrada.'; end if;
  if v_sale.status<>'draft' then raise exception 'Esta venda já não está em rascunho.'; end if;

  if p_member is not null then
    if p_customer_type<>'member' then raise exception 'Um membro só pode ser associado a preço de membro.'; end if;
    select coalesce(nullif(btrim(nickname),''),full_name) into v_member_label
    from public.members
    where id=p_member and club_id=target_club and status::text in ('active','full_color','honorary');
    if v_member_label is null then raise exception 'Membro inválido ou sem acesso ao preço de membro.'; end if;
  end if;

  v_event:=coalesce(p_event,v_sale.event_id);
  if v_event is not null and not exists(select 1 from public.events where id=v_event and club_id=target_club) then
    raise exception 'Evento inválido.';
  end if;
  v_customer:=coalesce(nullif(btrim(coalesce(p_customer_label,'')),''),v_member_label,v_sale.customer_label);
  if p_customer_type='member' and p_member is null and nullif(btrim(coalesce(v_customer,'')),'') is null then
    raise exception 'Indica o membro ou o nome da conta de grupo.';
  end if;
  v_notes:=nullif(btrim(coalesce(p_notes,v_sale.notes,'')),'');

  for r in select value from jsonb_array_elements(p_lines)
  loop
    v_kind:=coalesce(nullif(btrim(r->>'kind'),''),'stock');
    begin v_quantity:=(r->>'quantity')::numeric;
    exception when others then raise exception 'Quantidade inválida numa linha da venda.'; end;
    if v_quantity is null or v_quantity<=0 then raise exception 'Todas as quantidades têm de ser superiores a zero.'; end if;

    if v_kind='stock' then
      begin
        v_product_id:=(r->>'product_id')::uuid;
        v_option_id:=(r->>'sale_option_id')::uuid;
      exception when others then raise exception 'Artigo ou forma de venda inválida.'; end;
      select * into v_product from public.products
      where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true;
      if not found then raise exception 'Artigo do Bar inválido ou inativo.'; end if;
      select * into v_option from public.bar_product_sale_options
      where id=v_option_id and product_id=v_product_id and club_id=target_club and active=true;
      if not found then raise exception 'Forma de venda inválida ou inativa para %.',v_product.name; end if;
      v_stock_per_unit:=v_option.stock_quantity;
      v_unit_price:=case when p_customer_type='member' then v_option.member_price else v_option.public_price end;
      v_description:=v_product.name||' · '||v_option.name;
    elsif v_kind='preset' then
      begin v_preset_id:=(r->>'preset_id')::uuid;
      exception when others then raise exception 'Item fixo inválido.'; end;
      select * into v_preset from public.bar_sale_presets
      where id=v_preset_id and club_id=target_club and active=true;
      if not found then raise exception 'Item fixo do Bar inválido ou inativo.'; end if;
      if coalesce(v_preset.unit_price,0)<=0 then raise exception 'Define primeiro o preço de %.',v_preset.name; end if;
      v_stock_per_unit:=null;
      v_unit_price:=v_preset.unit_price;
      v_description:=v_preset.name;
    elsif v_kind='other' then
      v_description:=nullif(btrim(coalesce(r->>'description','')),'');
      if v_description is null then raise exception 'Indica a descrição do item Outro.'; end if;
      begin v_unit_price:=(r->>'unit_price')::numeric;
      exception when others then raise exception 'Preço inválido no item Outro.'; end;
      if v_unit_price is null or v_unit_price<0 then raise exception 'Preço inválido no item Outro.'; end if;
      v_stock_per_unit:=null;
    else
      raise exception 'Tipo de linha de venda inválido.';
    end if;

    v_line_total:=round(v_quantity*v_unit_price,2);
    v_total:=v_total+v_line_total;
    v_line_count:=v_line_count+1;
  end loop;
  if v_total<=0 then raise exception 'O total da venda tem de ser superior a zero.'; end if;

  if p_account is not null then
    if not public.has_club_permission(target_club,'selectBarFinancialAccount') then
      raise exception 'Sem autorização para escolher a conta financeira do Bar.';
    end if;
    select id into v_account from public.treasury_accounts
    where id=p_account and club_id=target_club and active=true;
    if v_account is null then raise exception 'Conta financeira inválida ou inativa.'; end if;
  else
    select id into v_account from public.treasury_accounts
    where club_id=target_club and active=true and lower(name)=lower('Caixa') limit 1;
    if v_account is null then
      select id into v_account from public.treasury_accounts
      where club_id=target_club and active=true order by created_at limit 1;
    end if;
    if v_account is null then raise exception 'Não existe nenhuma conta financeira ativa.'; end if;
  end if;

  select id into v_cost_center from public.cost_centers
  where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;

  insert into public.treasury_transactions(
    club_id,kind,account_id,cost_center_id,event_id,transaction_date,
    description,amount,payment_method,notes,source_type,source_id,created_by
  ) values (
    target_club,'income'::public.transaction_kind,v_account,v_cost_center,v_event,current_date,
    case when v_customer is null then 'Venda Bar' else 'Venda Bar - '||v_customer end,
    v_total,p_payment_method,v_notes,'bar_sale',p_sale,auth.uid()
  ) returning id into v_tx;

  delete from public.bar_sale_items where sale_id=p_sale and club_id=target_club;

  for r in select value from jsonb_array_elements(p_lines)
  loop
    v_kind:=coalesce(nullif(btrim(r->>'kind'),''),'stock');
    v_quantity:=(r->>'quantity')::numeric;
    v_product_id:=null; v_preset_id:=null; v_option_id:=null; v_stock_per_unit:=null;

    if v_kind='stock' then
      v_product_id:=(r->>'product_id')::uuid;
      v_option_id:=(r->>'sale_option_id')::uuid;
      select * into v_product from public.products
      where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true for update;
      if not found then raise exception 'Artigo do Bar inválido ou inativo.'; end if;
      select * into v_option from public.bar_product_sale_options
      where id=v_option_id and product_id=v_product_id and club_id=target_club and active=true;
      if not found then raise exception 'Forma de venda inválida ou inativa para %.',v_product.name; end if;
      v_stock_per_unit:=v_option.stock_quantity;
      v_stock_total:=v_quantity*v_stock_per_unit;
      v_new_stock:=coalesce(v_product.current_stock,0)-v_stock_total;
      if v_new_stock<0 then
        raise exception 'Stock insuficiente de %. Disponível: % %',v_product.name,coalesce(v_product.current_stock,0),coalesce(v_product.consumption_unit,'unid.');
      end if;
      v_unit_price:=case when p_customer_type='member' then v_option.member_price else v_option.public_price end;
      v_description:=v_product.name||' · '||v_option.name;
      v_line_total:=round(v_quantity*v_unit_price,2);

      update public.products set current_stock=v_new_stock,updated_by=auth.uid(),updated_at=now() where id=v_product.id;
      insert into public.stock_movements(
        club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by
      ) values (
        target_club,v_product.id,v_event,'sale',-v_stock_total,coalesce(v_product.cost,0),
        concat_ws(' | ','Venda Bar',v_option.name,v_customer,'Venda '||p_sale::text),auth.uid()
      );
      insert into public.bar_operations(
        club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,
        unit_price,total_amount,payment_method,notes,treasury_transaction_id,created_by,
        sale_id,sale_option_id,sale_option_name,customer_type
      ) values (
        target_club,v_product.id,v_event,'sale',null,v_stock_total,v_unit_price,v_line_total,
        p_payment_method,concat_ws(' | ',v_option.name,v_customer,'Venda '||p_sale::text),v_tx,auth.uid(),
        p_sale,v_option.id,v_option.name,p_customer_type
      );
    elsif v_kind='preset' then
      v_preset_id:=(r->>'preset_id')::uuid;
      select * into v_preset from public.bar_sale_presets
      where id=v_preset_id and club_id=target_club and active=true;
      if not found then raise exception 'Item fixo do Bar inválido ou inativo.'; end if;
      v_unit_price:=v_preset.unit_price;
      v_description:=v_preset.name;
      v_line_total:=round(v_quantity*v_unit_price,2);
    else
      v_description:=nullif(btrim(coalesce(r->>'description','')),'');
      v_unit_price:=(r->>'unit_price')::numeric;
      v_line_total:=round(v_quantity*v_unit_price,2);
    end if;

    insert into public.bar_sale_items(
      club_id,sale_id,item_kind,product_id,preset_id,sale_option_id,sale_option_name,
      stock_quantity_per_unit,price_tier,description,quantity,unit_price,line_total
    ) values (
      target_club,p_sale,v_kind,v_product_id,v_preset_id,v_option_id,
      case when v_kind='stock' then v_option.name else null end,
      v_stock_per_unit,p_customer_type,v_description,v_quantity,v_unit_price,v_line_total
    );
  end loop;

  update public.bar_sales set
    event_id=v_event,customer_label=v_customer,customer_type=p_customer_type,member_id=p_member,
    payment_method=p_payment_method,total_amount=v_total,treasury_transaction_id=v_tx,notes=v_notes,
    status='completed',completed_by=auth.uid(),completed_at=now(),updated_by=auth.uid(),updated_at=now()
  where id=p_sale;

  perform public.emit_domain_event(
    target_club,'BarSaleCompleted','bar',p_sale,
    jsonb_build_object(
      'title','Venda Bar concluída',
      'description',coalesce(v_customer,'Venda')||' · '||to_char(v_total,'FM999999990.00')||' €',
      'module_code','bar','route','bar','priority','low','sale_id',p_sale,'transaction_id',v_tx
    )
  );

  return jsonb_build_object(
    'sale_id',p_sale,'transaction_id',v_tx,'account_id',v_account,
    'line_count',v_line_count,'total',v_total,'customer_type',p_customer_type,'member_id',p_member
  );
end;
$$;
revoke all on function public.complete_bar_sale_v2(uuid,uuid,jsonb,text,uuid,text,text,uuid,uuid,text) from public,anon;
grant execute on function public.complete_bar_sale_v2(uuid,uuid,jsonb,text,uuid,text,text,uuid,uuid,text) to authenticated;
