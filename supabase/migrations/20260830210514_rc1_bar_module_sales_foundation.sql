alter table public.club_role_permissions disable trigger trg_activity_role_permissions;

insert into public.club_role_permissions (
  club_id, role_key, permission_key, allowed, updated_at
)
select
  club_id, role_key, 'viewBar', allowed, now()
from public.club_role_permissions
where permission_key = 'viewInventory'
on conflict (club_id, role_key, permission_key) do nothing;

alter table public.club_role_permissions enable trigger trg_activity_role_permissions;

create table if not exists public.bar_sale_presets (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  unit_price numeric(12,2) not null default 0 check (unit_price >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (club_id, name)
);

create table if not exists public.bar_sales (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  source_mode text not null default 'manual' check (source_mode in ('manual','ocr')),
  status text not null default 'draft' check (status in ('draft','completed','cancelled')),
  customer_label text,
  payment_method text,
  total_amount numeric(12,2) not null default 0 check (total_amount >= 0),
  treasury_transaction_id uuid references public.treasury_transactions(id) on delete set null,
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz
);

create table if not exists public.bar_sale_items (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  sale_id uuid not null references public.bar_sales(id) on delete cascade,
  item_kind text not null check (item_kind in ('stock','preset','other')),
  product_id uuid references public.products(id) on delete set null,
  preset_id uuid references public.bar_sale_presets(id) on delete set null,
  description text not null,
  quantity numeric(12,3) not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) not null check (line_total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.bar_sale_attachments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  sale_id uuid not null references public.bar_sales(id) on delete cascade,
  storage_path text not null unique,
  original_file_name text not null,
  mime_type text not null,
  file_size bigint not null check (file_size > 0),
  attachment_kind text not null default 'consumption_card' check (attachment_kind in ('consumption_card','other')),
  ocr_status text not null default 'pending' check (ocr_status in ('pending','processing','ready','failed','skipped')),
  ocr_raw_text text,
  ocr_suggestions jsonb not null default '[]'::jsonb,
  ocr_confidence numeric,
  ocr_error text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists bar_sales_club_created_idx
  on public.bar_sales(club_id, created_at desc);
create index if not exists bar_sales_club_status_idx
  on public.bar_sales(club_id, status, created_at desc);
create index if not exists bar_sale_items_sale_idx
  on public.bar_sale_items(sale_id);
create index if not exists bar_sale_attachments_sale_idx
  on public.bar_sale_attachments(sale_id);

insert into public.bar_sale_presets (club_id, name, unit_price, active, sort_order)
select c.id, 'Jantar', 0, true, 10
from public.clubs c
where not exists (
  select 1 from public.bar_sale_presets p
  where p.club_id = c.id and lower(p.name) = lower('Jantar')
);

alter table public.bar_sale_presets enable row level security;
alter table public.bar_sales enable row level security;
alter table public.bar_sale_items enable row level security;
alter table public.bar_sale_attachments enable row level security;

drop policy if exists bar_sale_presets_select on public.bar_sale_presets;
drop policy if exists bar_sale_presets_manage on public.bar_sale_presets;
create policy bar_sale_presets_select
on public.bar_sale_presets for select to authenticated
using (public.has_club_permission(club_id, 'viewBar'));
create policy bar_sale_presets_manage
on public.bar_sale_presets for all to authenticated
using (public.has_club_permission(club_id, 'manageBar'))
with check (public.has_club_permission(club_id, 'manageBar'));

drop policy if exists bar_sales_select on public.bar_sales;
drop policy if exists bar_sales_manage on public.bar_sales;
create policy bar_sales_select
on public.bar_sales for select to authenticated
using (public.has_club_permission(club_id, 'viewBar'));
create policy bar_sales_manage
on public.bar_sales for all to authenticated
using (public.has_club_permission(club_id, 'manageBar'))
with check (public.has_club_permission(club_id, 'manageBar'));

drop policy if exists bar_sale_items_select on public.bar_sale_items;
drop policy if exists bar_sale_items_manage on public.bar_sale_items;
create policy bar_sale_items_select
on public.bar_sale_items for select to authenticated
using (public.has_club_permission(club_id, 'viewBar'));
create policy bar_sale_items_manage
on public.bar_sale_items for all to authenticated
using (public.has_club_permission(club_id, 'manageBar'))
with check (public.has_club_permission(club_id, 'manageBar'));

drop policy if exists bar_sale_attachments_select on public.bar_sale_attachments;
drop policy if exists bar_sale_attachments_manage on public.bar_sale_attachments;
create policy bar_sale_attachments_select
on public.bar_sale_attachments for select to authenticated
using (public.has_club_permission(club_id, 'viewBar'));
create policy bar_sale_attachments_manage
on public.bar_sale_attachments for all to authenticated
using (public.has_club_permission(club_id, 'manageBar'))
with check (public.has_club_permission(club_id, 'manageBar'));

revoke all on public.bar_sale_presets from anon;
revoke all on public.bar_sales from anon;
revoke all on public.bar_sale_items from anon;
revoke all on public.bar_sale_attachments from anon;
grant select, insert, update, delete on public.bar_sale_presets to authenticated;
grant select, insert, update, delete on public.bar_sales to authenticated;
grant select, insert, update, delete on public.bar_sale_items to authenticated;
grant select, insert, update, delete on public.bar_sale_attachments to authenticated;

create or replace function public.financial_storage_access_v2(
  p_name text,
  p_manage boolean default false
)
returns boolean
language plpgsql
stable security definer
set search_path to 'public', 'storage'
as $$
declare
  folders text[];
  v_request uuid;
  v_transaction uuid;
  v_job uuid;
  v_sale uuid;
  v_club uuid;
begin
  if auth.uid() is null then return false; end if;
  folders:=storage.foldername(p_name);
  if coalesce(array_length(folders,1),0)<2 then return false; end if;

  if folders[2]='transactions' then
    if coalesce(array_length(folders,1),0)<3 then return false; end if;
    begin v_transaction:=folders[3]::uuid; exception when invalid_text_representation then return false; end;
    select t.club_id into v_club from public.treasury_transactions t where t.id=v_transaction;
    if not found or folders[1] is distinct from v_club::text then return false; end if;
    if p_manage then
      return public.has_club_permission(v_club,'createTreasuryMovement')
        or public.has_club_permission(v_club,'approveExpenseRequests');
    end if;
    return public.has_club_permission(v_club,'viewTreasury')
      or public.has_club_permission(v_club,'approveExpenseRequests');
  end if;

  if folders[2]='ocr' then
    if coalesce(array_length(folders,1),0)<3 then return false; end if;
    begin v_job:=folders[3]::uuid; exception when invalid_text_representation then return false; end;
    select j.club_id into v_club from public.financial_ocr_jobs j where j.id=v_job;
    if not found or folders[1] is distinct from v_club::text then return false; end if;
    if p_manage then
      return public.has_club_permission(v_club,'manageBar')
        or public.has_club_permission(v_club,'createTreasuryMovement')
        or public.has_club_permission(v_club,'approveExpenseRequests');
    end if;
    return public.has_club_permission(v_club,'manageBar')
      or public.has_club_permission(v_club,'viewBar')
      or public.has_club_permission(v_club,'viewTreasury')
      or public.has_club_permission(v_club,'approveExpenseRequests');
  end if;

  if folders[2]='bar-sales' then
    if coalesce(array_length(folders,1),0)<3 then return false; end if;
    begin v_sale:=folders[3]::uuid; exception when invalid_text_representation then return false; end;
    select s.club_id into v_club from public.bar_sales s where s.id=v_sale;
    if not found or folders[1] is distinct from v_club::text then return false; end if;
    if p_manage then return public.has_club_permission(v_club,'manageBar'); end if;
    return public.has_club_permission(v_club,'viewBar')
      or public.has_club_permission(v_club,'manageBar');
  end if;

  begin v_request:=folders[2]::uuid; exception when invalid_text_representation then return false; end;
  select r.club_id into v_club from public.financial_requests r where r.id=v_request;
  if not found or folders[1] is distinct from v_club::text then return false; end if;
  return public.financial_request_access_v1(v_request);
end;
$$;

create or replace function public.create_bar_sale_v1(
  target_club uuid,
  p_customer_label text default null,
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
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para criar vendas no Bar.';
  end if;
  if p_source_mode not in ('manual','ocr') then
    raise exception 'Modo de venda inválido.';
  end if;
  if p_event is not null and not exists(
    select 1 from public.events where id=p_event and club_id=target_club
  ) then
    raise exception 'Evento inválido.';
  end if;

  insert into public.bar_sales(
    club_id,event_id,source_mode,status,customer_label,notes,created_by,updated_by
  ) values (
    target_club,p_event,p_source_mode,'draft',nullif(btrim(coalesce(p_customer_label,'')),''),
    nullif(btrim(coalesce(p_notes,'')),''),auth.uid(),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.create_bar_sale_v1(uuid,text,text,uuid,text) from public, anon;
grant execute on function public.create_bar_sale_v1(uuid,text,text,uuid,text) to authenticated;

create or replace function public.complete_bar_sale_v1(
  target_club uuid,
  p_sale uuid,
  p_lines jsonb,
  p_payment_method text,
  p_account uuid default null,
  p_customer_label text default null,
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
  v_product public.products%rowtype;
  v_preset public.bar_sale_presets%rowtype;
  v_description text;
  v_quantity numeric;
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
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para concluir vendas no Bar.';
  end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Adiciona pelo menos um artigo à venda.';
  end if;
  if nullif(btrim(coalesce(p_payment_method,'')),'') is null then
    raise exception 'Seleciona o método de pagamento.';
  end if;

  select * into v_sale
  from public.bar_sales
  where id=p_sale and club_id=target_club
  for update;
  if not found then raise exception 'Venda do Bar não encontrada.'; end if;
  if v_sale.status<>'draft' then raise exception 'Esta venda já não está em rascunho.'; end if;

  v_event:=coalesce(p_event,v_sale.event_id);
  if v_event is not null and not exists(
    select 1 from public.events where id=v_event and club_id=target_club
  ) then raise exception 'Evento inválido.'; end if;
  v_customer:=nullif(btrim(coalesce(p_customer_label,v_sale.customer_label,'')),'');
  v_notes:=nullif(btrim(coalesce(p_notes,v_sale.notes,'')),'');

  for r in select value from jsonb_array_elements(p_lines)
  loop
    v_kind:=coalesce(nullif(btrim(r->>'kind'),''),'stock');
    begin
      v_quantity:=(r->>'quantity')::numeric;
    exception when others then
      raise exception 'Quantidade inválida numa linha da venda.';
    end;
    if v_quantity is null or v_quantity<=0 then
      raise exception 'Todas as quantidades têm de ser superiores a zero.';
    end if;

    if v_kind='stock' then
      begin v_product_id:=(r->>'product_id')::uuid;
      exception when others then raise exception 'Artigo de stock inválido.'; end;
      select * into v_product
      from public.products
      where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true;
      if not found then raise exception 'Artigo do Bar inválido ou inativo.'; end if;
      v_unit_price:=coalesce(v_product.sale_price,0);
      v_description:=v_product.name;
    elsif v_kind='preset' then
      begin v_preset_id:=(r->>'preset_id')::uuid;
      exception when others then raise exception 'Item fixo inválido.'; end;
      select * into v_preset
      from public.bar_sale_presets
      where id=v_preset_id and club_id=target_club and active=true;
      if not found then raise exception 'Item fixo do Bar inválido ou inativo.'; end if;
      if coalesce(v_preset.unit_price,0)<=0 then
        raise exception 'Define primeiro o preço de %.',v_preset.name;
      end if;
      v_unit_price:=v_preset.unit_price;
      v_description:=v_preset.name;
    elsif v_kind='other' then
      v_description:=nullif(btrim(coalesce(r->>'description','')),'');
      if v_description is null then raise exception 'Indica a descrição do item Outro.'; end if;
      begin v_unit_price:=(r->>'unit_price')::numeric;
      exception when others then raise exception 'Preço inválido no item Outro.'; end;
      if v_unit_price is null or v_unit_price<0 then raise exception 'Preço inválido no item Outro.'; end if;
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
    select id into v_account
    from public.treasury_accounts
    where id=p_account and club_id=target_club and active=true;
    if v_account is null then raise exception 'Conta financeira inválida ou inativa.'; end if;
  else
    select id into v_account
    from public.treasury_accounts
    where club_id=target_club and active=true and lower(name)=lower('Caixa')
    limit 1;
    if v_account is null then
      select id into v_account
      from public.treasury_accounts
      where club_id=target_club and active=true
      order by created_at
      limit 1;
    end if;
    if v_account is null then raise exception 'Não existe nenhuma conta financeira ativa.'; end if;
  end if;

  select id into v_cost_center
  from public.cost_centers
  where club_id=target_club and active=true and lower(name)=lower('Club House')
  limit 1;

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
    v_product_id:=null;
    v_preset_id:=null;

    if v_kind='stock' then
      v_product_id:=(r->>'product_id')::uuid;
      select * into v_product
      from public.products
      where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true
      for update;
      if not found then raise exception 'Artigo do Bar inválido ou inativo.'; end if;
      v_new_stock:=coalesce(v_product.current_stock,0)-v_quantity;
      if v_new_stock<0 then
        raise exception 'Stock insuficiente de %. Disponível: %',v_product.name,coalesce(v_product.current_stock,0);
      end if;
      v_unit_price:=coalesce(v_product.sale_price,0);
      v_description:=v_product.name;
      v_line_total:=round(v_quantity*v_unit_price,2);

      update public.products set current_stock=v_new_stock where id=v_product.id;
      insert into public.stock_movements(
        club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by
      ) values (
        target_club,v_product.id,v_event,'sale',-v_quantity,coalesce(v_product.cost,0),
        concat_ws(' | ','Venda Bar',v_customer,'Venda '||p_sale::text),auth.uid()
      );
      insert into public.bar_operations(
        club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,
        unit_price,total_amount,payment_method,notes,treasury_transaction_id,created_by
      ) values (
        target_club,v_product.id,v_event,'sale',null,v_quantity,v_unit_price,v_line_total,
        p_payment_method,concat_ws(' | ',v_customer,'Venda '||p_sale::text),v_tx,auth.uid()
      );
    elsif v_kind='preset' then
      v_preset_id:=(r->>'preset_id')::uuid;
      select * into v_preset
      from public.bar_sale_presets
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
      club_id,sale_id,item_kind,product_id,preset_id,description,quantity,unit_price,line_total
    ) values (
      target_club,p_sale,v_kind,v_product_id,v_preset_id,v_description,v_quantity,v_unit_price,v_line_total
    );
  end loop;

  update public.bar_sales
  set event_id=v_event,
      customer_label=v_customer,
      payment_method=p_payment_method,
      total_amount=v_total,
      treasury_transaction_id=v_tx,
      notes=v_notes,
      status='completed',
      completed_by=auth.uid(),
      completed_at=now(),
      updated_by=auth.uid(),
      updated_at=now()
  where id=p_sale;

  perform public.emit_domain_event(
    target_club,'BarSaleCompleted','bar',p_sale,
    jsonb_build_object(
      'title','Venda Bar concluída',
      'description',coalesce(v_customer,'Venda')||' · '||to_char(v_total,'FM999999990.00')||' €',
      'module_code','bar','route','bar','priority','low',
      'sale_id',p_sale,'transaction_id',v_tx
    )
  );

  return jsonb_build_object(
    'sale_id',p_sale,'transaction_id',v_tx,'account_id',v_account,
    'line_count',v_line_count,'total',v_total
  );
end;
$$;

revoke all on function public.complete_bar_sale_v1(uuid,uuid,jsonb,text,uuid,text,uuid,text) from public, anon;
grant execute on function public.complete_bar_sale_v1(uuid,uuid,jsonb,text,uuid,text,uuid,text) to authenticated;
