-- BAR-origin reversal: original sales, lines, stock and treasury entries survive.
-- The generic Treasury RPC remains unchanged: BAR is corrected at its origin.
begin;
alter table public.bar_sales drop constraint bar_sales_status_check;
alter table public.bar_sales add constraint bar_sales_status_check
  check(status in ('draft','completed','cancelled','reversed'));
alter table public.bar_sales add constraint bar_sales_reversal_club_id_id_unique unique(club_id,id);

create table public.bar_sale_reversals (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id),
  sale_id uuid not null unique,
  original_transaction_id uuid not null unique,
  reversal_transaction_id uuid not null unique,
  reason text not null check(length(btrim(reason))>=3),
  created_at timestamptz not null default now(),
  created_by uuid not null references public.profiles(id),
  foreign key(club_id,sale_id) references public.bar_sales(club_id,id),
  foreign key(club_id,original_transaction_id) references public.treasury_transactions(club_id,id),
  foreign key(club_id,reversal_transaction_id) references public.treasury_transactions(club_id,id)
);
alter table public.bar_sale_reversals enable row level security;
create policy bar_sale_reversals_read on public.bar_sale_reversals for select to authenticated
  using(auth.uid() is not null and public.has_club_access(club_id) and public.has_club_permission(club_id,'viewBar'));
revoke all on public.bar_sale_reversals from public,anon,authenticated;
grant select on public.bar_sale_reversals to authenticated;
create trigger trg_bar_sale_reversal_audit after insert on public.bar_sale_reversals
  for each row execute function public.audit_capture_row_v1();

-- Authenticated table DML cannot counterfeit a reversal or resurrect its sale.
-- The record is inserted by the guarded RPC before its terminal status change.
create function bob_dinner_private.guard_bar_sale_reversal() returns trigger
language plpgsql security definer set search_path=public as $$ begin
  if TG_OP='INSERT' then
    if new.status='reversed' then raise exception 'A anulação exige uma venda concluída.'; end if;
    return new;
  end if;
  if old.status='reversed' then raise exception 'Uma venda anulada é imutável.'; end if;
  if TG_OP='DELETE' then
    if old.status='completed' then raise exception 'Não é permitido apagar uma venda concluída.'; end if;
    return old;
  end if;
  if old.status='completed' and new.status not in ('completed','reversed') then
    raise exception 'Utiliza Anular venda para reverter uma venda concluída.';
  end if;
  -- Fail closed for every current/future business column. Audit stamping only
  -- changes updated_by/updated_at; original creation metadata remains protected.
  if old.status='completed' and new.status='completed' then
    if (to_jsonb(new)-array['updated_by','updated_at','weekly_dinner_id'])
      is distinct from (to_jsonb(old)-array['updated_by','updated_at','weekly_dinner_id']) then
      raise exception 'Os dados de uma venda concluída são imutáveis.';
    end if;
    if new.weekly_dinner_id is distinct from old.weekly_dinner_id then
      -- Match assign_bar_sale_dinner_v1 exactly: auth/club, financial reporting
      -- and financial_manager_v1. manageBar table UPDATE alone is insufficient.
      -- The existing dinner guard still locks/checks both dinners and their close.
      perform bob_dinner_private.require_access(old.club_id,true);
    end if;
  end if;
  if new.status='reversed' then
    if (to_jsonb(new)-array['status','updated_by','updated_at'])
      is distinct from (to_jsonb(old)-array['status','updated_by','updated_at']) then
      raise exception 'A anulação não pode alterar os dados originais da venda.';
    end if;
    if old.status<>'completed' or new.club_id is distinct from old.club_id
      or new.treasury_transaction_id is distinct from old.treasury_transaction_id
      or new.weekly_dinner_id is distinct from old.weekly_dinner_id
      or not exists(select 1 from public.bar_sale_reversals r
        where r.club_id=old.club_id and r.sale_id=old.id and r.original_transaction_id=old.treasury_transaction_id) then
      raise exception 'Utiliza a operação autorizada Anular venda.';
    end if;
  end if;
  return new;
end $$;
revoke all on function bob_dinner_private.guard_bar_sale_reversal() from public,anon,authenticated;
create trigger trg_bar_sale_reversal_guard before insert or update or delete on public.bar_sales
  for each row execute function bob_dinner_private.guard_bar_sale_reversal();

-- Keep the existing snapshot trigger, extending its immutability to reversed sales.
create or replace function bob_dinner_private.snapshot_line() returns trigger
language plpgsql security definer set search_path=public as $$
declare s public.bar_sales%rowtype; product public.products%rowtype; is_meal boolean;
begin
  if TG_OP in ('UPDATE','DELETE') and exists(
    select 1 from public.bar_sales where id=old.sale_id and status in ('completed','reversed')) then
    raise exception 'As linhas de uma venda concluída são imutáveis.';
  end if;
  select * into s from public.bar_sales where id=case when TG_OP='DELETE' then old.sale_id else new.sale_id end;
  if s.status in ('completed','reversed') then
    raise exception 'As linhas de uma venda concluída são imutáveis.';
  end if;
  if TG_OP='DELETE' then return old; end if;
  if s.club_id is distinct from new.club_id then raise exception 'Clube da venda inválido.'; end if;
  -- V2 takes the product lock before insertion. This trigger snapshots the SAME
  -- weighted-average consumption unit cost, including doses/conversion factors.
  -- It also protects new sales completed by legacy V2 clients, without overloads.
  if new.item_kind='stock' then
    select * into product from public.products where id=new.product_id and club_id=new.club_id for update;
    if not found then raise exception 'Produto inválido.'; end if;
    new.unit_cost_snapshot:=product.cost;
    new.cost_total_snapshot:=round(new.quantity*coalesce(new.stock_quantity_per_unit,1)*product.cost,2);
    new.dinner_component_snapshot:='bar';
  elsif new.item_kind='preset' then
    select counts_as_dinner_meal into is_meal from public.bar_sale_presets
      where id=new.preset_id and club_id=new.club_id;
    if not found then raise exception 'Preset inválido.'; end if;
    new.unit_cost_snapshot:=null; new.cost_total_snapshot:=null;
    new.dinner_component_snapshot:=case when is_meal then 'meal' else 'excluded' end;
  else
    -- Explicitly excluded: neither a meal nor a stock beverage. Display the
    -- excluded revenue separately; never silently inflate beverage revenue.
    new.unit_cost_snapshot:=null; new.cost_total_snapshot:=null;
    new.dinner_component_snapshot:='excluded';
  end if;
  return new;
end $$;

create function public.reverse_bar_sale_v1(target_club uuid,p_sale uuid,p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare s public.bar_sales%rowtype; t public.treasury_transactions%rowtype;
  item public.bar_sale_items%rowtype; tx uuid; reversal uuid; quantity_back numeric;
  product uuid; consumed numeric; snapshot_consumed numeric;
begin
  if auth.uid() is null or not public.has_club_access(target_club)
    or not public.has_club_permission(target_club,'manageBar')
    or not public.has_club_permission(target_club,'reverseTreasuryMovement') then
    raise exception 'Sem permissão para anular vendas do BAR.' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Indica o motivo da anulação (mínimo 3 caracteres).'; end if;
  select * into s from public.bar_sales where club_id=target_club and id=p_sale for update;
  if not found then raise exception 'Venda do BAR não encontrada neste clube.'; end if;
  if s.status<>'completed' or exists(select 1 from public.bar_sale_reversals where sale_id=p_sale) then
    raise exception 'Só é possível anular uma venda concluída ainda não anulada.';
  end if;
  -- Same dinner lock as close/association triggers. No frozen snapshot is edited.
  if s.weekly_dinner_id is not null then
    perform 1 from public.weekly_dinners where club_id=target_club and id=s.weekly_dinner_id for update;
    if not found then raise exception 'Jantar inválido para este clube.'; end if;
    if exists(select 1 from public.weekly_dinner_finances where dinner_id=s.weekly_dinner_id and financial_status='closed') then
      raise exception 'Reabre o fecho financeiro do jantar antes de anular esta venda.';
    end if;
  end if;
  select * into t from public.treasury_transactions
    where club_id=target_club and id=s.treasury_transaction_id for update;
  if not found or t.kind::text<>'income' or t.reversal_of is not null
    or t.source_type is distinct from 'bar_sale' or t.source_id is distinct from s.id
    or t.amount is distinct from s.total_amount then
    raise exception 'O movimento financeiro original da venda não é fiável para anulação.';
  end if;
  if exists(select 1 from public.treasury_transactions where reversal_of=t.id) then
    raise exception 'O movimento financeiro desta venda já foi revertido.';
  end if;
  -- Lock products in a deterministic order. Use the sale's immutable dose factors,
  -- never today's product/options/conversion or current average purchase cost.
  for product in select distinct i.product_id from public.bar_sale_items i
    where i.club_id=target_club and i.sale_id=p_sale and i.item_kind='stock' order by i.product_id loop
    perform 1 from public.products where id=product and club_id=target_club for update;
    if not found then raise exception 'Produto original da venda não encontrado.'; end if;
    select sum(i.quantity*i.stock_quantity_per_unit) into snapshot_consumed
      from public.bar_sale_items i where i.club_id=target_club and i.sale_id=p_sale and i.product_id=product and i.item_kind='stock';
    select sum(o.consumption_quantity) into consumed from public.bar_operations o
      where o.club_id=target_club and o.sale_id=p_sale and o.product_id=product and o.operation_type='sale';
    if snapshot_consumed is null or snapshot_consumed<=0 or snapshot_consumed::text in ('NaN','Infinity','-Infinity')
      or consumed is distinct from snapshot_consumed
      or exists(select 1 from public.bar_sale_items i where i.sale_id=p_sale and i.item_kind='stock' and i.product_id=product
        and (i.stock_quantity_per_unit is null or i.stock_quantity_per_unit<=0)) then
      raise exception 'Quantidade de stock histórica não fiável; não é possível anular automaticamente.';
    end if;
  end loop;
  if exists(select 1 from public.bar_sale_items where sale_id=p_sale and item_kind='stock' and product_id is null) then
    raise exception 'Produto original da venda não encontrado.';
  end if;
  -- Same compensating-entry convention as reverse_treasury_transaction_v1.
  -- Its source-module restriction stays intact; no source_type is temporarily changed.
  insert into public.treasury_transactions(club_id,kind,account_id,destination_account_id,category_id,cost_center_id,event_id,
    transaction_date,description,amount,payment_method,notes,source_type,source_id,reversal_of,created_by)
  values(target_club,'expense',t.account_id,null,t.category_id,t.cost_center_id,t.event_id,
    current_date,'Reversão — '||t.description,t.amount,t.payment_method,btrim(p_reason),'reversal',t.id,t.id,auth.uid())
    returning id into tx;
  insert into public.bar_sale_reversals(club_id,sale_id,original_transaction_id,reversal_transaction_id,reason,created_by)
    values(target_club,p_sale,t.id,tx,btrim(p_reason),auth.uid()) returning id into reversal;
  for item in select * from public.bar_sale_items
    where club_id=target_club and sale_id=p_sale and item_kind='stock' order by product_id,id loop
    quantity_back:=item.quantity*item.stock_quantity_per_unit;
    update public.products set current_stock=coalesce(current_stock,0)+quantity_back,updated_by=auth.uid(),updated_at=now()
      where club_id=target_club and id=item.product_id;
    -- Nullable historical cost stays NULL; this is a quantity correction, not a
    -- purchase. Product.cost is deliberately unchanged, preserving average cost.
    insert into public.stock_movements(club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by)
      values(target_club,item.product_id,s.event_id,'adjustment',quantity_back,item.unit_cost_snapshot,
        'Anulação venda '||s.id||' | Linha '||item.id||' | '||btrim(p_reason),auth.uid());
    insert into public.bar_operations(club_id,product_id,event_id,operation_type,consumption_quantity,unit_price,total_amount,
      payment_method,notes,treasury_transaction_id,created_by,sale_id,sale_option_id,sale_option_name,customer_type)
      values(target_club,item.product_id,s.event_id,'adjustment_in',quantity_back,0,0,s.payment_method,
        'Anulação venda '||s.id||' | Linha '||item.id||' | '||btrim(p_reason),tx,auth.uid(),s.id,item.sale_option_id,item.sale_option_name,s.customer_type);
  end loop;
  update public.bar_sales set status='reversed',updated_by=auth.uid(),updated_at=now() where id=s.id;
  return reversal;
end $$;
revoke all on function public.reverse_bar_sale_v1(uuid,uuid,text) from public,anon;
grant execute on function public.reverse_bar_sale_v1(uuid,uuid,text) to authenticated;

-- Resolve only actor names in the club's BAR history; never generic profiles.
-- No emails, costs or other profile details are returned. This avoids own-profile
-- RLS turning another cashier's name into a misleading empty result.
create function public.bar_sale_history_v1(target_club uuid,p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb; begin
  if auth.uid() is null or not public.has_club_access(target_club) or not public.has_club_permission(target_club,'viewBar') then
    raise exception 'Sem permissão para ver o BAR.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(row_data order by completed_at desc,id),'[]'::jsonb) into result from (
    select s.id,s.completed_at,jsonb_build_object('id',s.id,'status',s.status,'completed_at',s.completed_at,
      'total_amount',s.total_amount,'customer_label',s.customer_label,'completed_by',s.completed_by,
      'completed_actor_name',p.full_name,'weekly_dinner_id',s.weekly_dinner_id,
      'reversal_reason',r.reason,'reversed_at',r.created_at,'reversed_by',r.created_by,'reversed_actor_name',rp.full_name,
      'bar_sale_items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'item_kind',i.item_kind,
        'description',i.description,'quantity',i.quantity,'unit_price',i.unit_price,'line_total',i.line_total) order by i.created_at,i.id)
        from public.bar_sale_items i where i.club_id=target_club and i.sale_id=s.id),'[]'::jsonb)) as row_data
    from public.bar_sales s left join public.profiles p on p.id=s.completed_by
      left join public.bar_sale_reversals r on r.club_id=s.club_id and r.sale_id=s.id
      left join public.profiles rp on rp.id=r.created_by
    where s.club_id=target_club and s.status in ('completed','reversed')
    order by s.completed_at desc,s.id limit greatest(1,least(coalesce(p_limit,100),250))
  ) history;
  return result;
end $$;
revoke all on function public.bar_sale_history_v1(uuid,integer) from public,anon;
grant execute on function public.bar_sale_history_v1(uuid,integer) to authenticated;
commit;
