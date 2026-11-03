-- Direct dinner result, not accounting net profit. No historical sales backfill.
-- Financial data lives separately from the authenticated operational roster.
begin;
create schema if not exists bob_dinner_private;
revoke all on schema bob_dinner_private from public, anon, authenticated;

alter table public.weekly_dinners add constraint weekly_dinners_club_id_id_unique unique(club_id,id);
alter table public.treasury_transactions add constraint dinner_treasury_club_id_id_unique unique(club_id,id);
alter table public.bar_sales add column weekly_dinner_id uuid;
alter table public.bar_sales add constraint bar_sales_weekly_dinner_fk
  foreign key(club_id,weekly_dinner_id) references public.weekly_dinners(club_id,id);
create index bar_sales_dinner_idx on public.bar_sales(club_id,weekly_dinner_id,status);
alter table public.bar_sale_presets add column counts_as_dinner_meal boolean not null default false;
update public.bar_sale_presets set counts_as_dinner_meal=true where lower(btrim(name))='jantar';
alter table public.bar_sale_items
  add column unit_cost_snapshot numeric(18,6) check(unit_cost_snapshot>=0 and unit_cost_snapshot<>'NaN'::numeric),
  add column cost_total_snapshot numeric(18,2) check(cost_total_snapshot>=0 and cost_total_snapshot<>'NaN'::numeric),
  add column dinner_component_snapshot text check(dinner_component_snapshot in ('meal','bar','excluded'));

-- Existing BAR RLS admits operational users. Cost snapshots are financial data:
-- revoke table-wide SELECT and preserve SELECT on every operational column.
-- Only the permission-checked financial RPCs expose stock costs.
do $$ declare columns text; begin
  select string_agg(quote_ident(attname),',' order by attnum) into columns
    from pg_attribute where attrelid='public.bar_sale_items'::regclass
      and attnum>0 and not attisdropped
      and attname not in ('unit_cost_snapshot','cost_total_snapshot');
  revoke select on public.bar_sale_items from public,anon,authenticated;
  execute format('grant select (%s) on public.bar_sale_items to authenticated',columns);
end $$;

create table public.weekly_dinner_finances (
  id uuid not null default gen_random_uuid() unique,
  dinner_id uuid primary key,
  club_id uuid not null references public.clubs(id),
  financial_status text not null default 'open' check(financial_status in ('open','closed')),
  meal_mode text not null default 'automatic' check(meal_mode in ('automatic','manual')),
  manual_meal_quantity numeric(12,3) not null default 0 check(manual_meal_quantity>=0 and manual_meal_quantity<>'NaN'::numeric),
  manual_meal_revenue numeric(18,2) not null default 0 check(manual_meal_revenue>=0 and manual_meal_revenue<>'NaN'::numeric),
  food_cost_manual numeric(18,2) not null default 0 check(food_cost_manual>=0 and food_cost_manual<>'NaN'::numeric),
  other_cost_manual numeric(18,2) not null default 0 check(other_cost_manual>=0 and other_cost_manual<>'NaN'::numeric),
  notes text,
  snapshot jsonb,
  revision integer not null default 0 check(revision>=0),
  closed_at timestamptz,
  closed_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  foreign key(club_id,dinner_id) references public.weekly_dinners(club_id,id),
  unique(club_id,dinner_id),
  check(financial_status<>'closed' or (snapshot is not null and closed_at is not null and closed_by is not null))
);
create table public.weekly_dinner_expenses (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id),
  dinner_id uuid not null,
  transaction_id uuid not null unique,
  cost_kind text not null check(cost_kind in ('food','other')),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  foreign key(club_id,dinner_id) references public.weekly_dinners(club_id,id),
  foreign key(club_id,transaction_id) references public.treasury_transactions(club_id,id)
);
create index weekly_dinner_expenses_dinner_idx on public.weekly_dinner_expenses(club_id,dinner_id);
create table public.weekly_dinner_financial_snapshots (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id),
  dinner_id uuid not null,
  revision integer not null,
  snapshot jsonb not null,
  closed_at timestamptz not null default now(),
  closed_by uuid not null references public.profiles(id),
  foreign key(club_id,dinner_id) references public.weekly_dinners(club_id,id),
  unique(dinner_id,revision)
);
-- Dinner-specific corrections never mutate completed sale-line snapshots.
-- Overrides do not follow a sale to a different dinner; its original context
-- and all INSERT/UPDATE/DELETE corrections remain in the existing audit log.
alter table public.bar_sale_items add constraint dinner_sale_items_club_id_id_unique unique(club_id,id);
create table public.weekly_dinner_sale_item_classifications (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id),
  dinner_id uuid not null,
  sale_item_id uuid not null,
  component_override text not null check(component_override in ('meal','bar')),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  foreign key(club_id,dinner_id) references public.weekly_dinners(club_id,id),
  foreign key(club_id,sale_item_id) references public.bar_sale_items(club_id,id),
  unique(dinner_id,sale_item_id)
);
create index dinner_item_classifications_item_idx on public.weekly_dinner_sale_item_classifications(club_id,sale_item_id);
-- SELECT only: writes are validated, serialized RPC operations, never direct DML.
do $$ declare t text; begin
  foreach t in array array['weekly_dinner_finances','weekly_dinner_expenses','weekly_dinner_financial_snapshots','weekly_dinner_sale_item_classifications'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant select on public.%I to authenticated',t);
    execute format('create policy dinner_financial_read on public.%I for select to authenticated using
      (auth.uid() is not null and public.has_club_access(club_id)
       and public.has_club_permission(club_id,''viewFinancialReports''))',t);
  end loop;
  foreach t in array array['weekly_dinner_finances','weekly_dinner_expenses','weekly_dinner_sale_item_classifications'] loop
    execute format('create trigger trg_audit_stamp_v1 before insert or update on public.%I
      for each row execute function public.audit_stamp_row_v1()',t);
    execute format('create trigger trg_audit_capture_v1 after insert or update or delete on public.%I
      for each row execute function public.audit_capture_row_v1()',t);
  end loop;
end $$;

create function bob_dinner_private.require_access(target_club uuid,p_write boolean default false)
returns void language plpgsql security invoker set search_path=public as $$
begin
  if auth.uid() is null or not public.has_club_access(target_club)
    or not public.has_club_permission(target_club,'viewFinancialReports')
    or (p_write and not public.financial_manager_v1(target_club)) then
    raise exception 'Sem autorização financeira.' using errcode='42501';
  end if;
end $$;
revoke all on function bob_dinner_private.require_access(uuid,boolean) from public,anon,authenticated;

create function bob_dinner_private.guard_sale() returns trigger
language plpgsql security definer set search_path=public as $$
declare d uuid; c uuid; ids uuid[]; s text;
begin
  if TG_OP='DELETE' then ids:=array[old.weekly_dinner_id]; c:=old.club_id;
  elsif TG_OP='UPDATE' then ids:=array[old.weekly_dinner_id,new.weekly_dinner_id]; c:=new.club_id;
  else ids:=array[new.weekly_dinner_id]; c:=new.club_id; end if;
  -- Lock dinner rows in deterministic order: close and sale completion serialize.
  for d in select distinct x from unnest(ids) x where x is not null order by x loop
    perform 1 from public.weekly_dinners where id=d and club_id=c for update;
    if not found then raise exception 'Jantar inválido para este clube.'; end if;
    select financial_status into s from public.weekly_dinner_finances where dinner_id=d;
    if s='closed' then raise exception 'Reabre o fecho financeiro antes de alterar as vendas.'; end if;
  end loop;
  if TG_OP='DELETE' then return old; end if;
  if new.weekly_dinner_id is not null and exists(select 1 from public.weekly_dinners
    where id=new.weekly_dinner_id and (status='cancelled' or (status='closed' and new.status='draft'))) then
    raise exception 'Jantar cancelado ou encerrado operacionalmente.';
  end if;
  return new;
end $$;
revoke all on function bob_dinner_private.guard_sale() from public,anon,authenticated;
create trigger trg_dinner_sale_guard before insert or update or delete on public.bar_sales
for each row execute function bob_dinner_private.guard_sale();

create function bob_dinner_private.snapshot_line() returns trigger
language plpgsql security definer set search_path=public as $$
declare s public.bar_sales%rowtype; product public.products%rowtype; is_meal boolean;
begin
  if TG_OP in ('UPDATE','DELETE') and exists(
    select 1 from public.bar_sales where id=old.sale_id and status='completed') then
    raise exception 'As linhas de uma venda concluída são imutáveis.';
  end if;
  select * into s from public.bar_sales where id=case when TG_OP='DELETE' then old.sale_id else new.sale_id end;
  if s.status='completed' then
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
revoke all on function bob_dinner_private.snapshot_line() from public,anon,authenticated;
create trigger trg_dinner_line_snapshot before insert or update or delete on public.bar_sale_items
for each row execute function bob_dinner_private.snapshot_line();

create function public.create_bar_sale_v3(
  target_club uuid,p_customer_label text default null,p_customer_type text default 'public',
  p_member uuid default null,p_source_mode text default 'manual',p_event uuid default null,
  p_notes text default null,p_weekly_dinner uuid default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid; begin
  result:=public.create_bar_sale_v2(target_club,p_customer_label,p_customer_type,p_member,p_source_mode,p_event,p_notes);
  update public.bar_sales set weekly_dinner_id=p_weekly_dinner where id=result;
  return result;
end $$;
create function public.complete_bar_sale_v3(
  target_club uuid,p_sale uuid,p_lines jsonb,p_payment_method text,
  p_account uuid default null,p_customer_label text default null,p_customer_type text default 'public',
  p_member uuid default null,p_event uuid default null,p_notes text default null,p_weekly_dinner uuid default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para concluir vendas.' using errcode='42501'; end if;
  -- Explicit NULL clears the draft dinner choice. event_id is kept independent.
  update public.bar_sales set weekly_dinner_id=p_weekly_dinner
    where id=p_sale and club_id=target_club and status='draft';
  if not found then raise exception 'Rascunho não encontrado.'; end if;
  result:=public.complete_bar_sale_v2(target_club,p_sale,p_lines,p_payment_method,p_account,
    p_customer_label,p_customer_type,p_member,p_event,p_notes);
  return result||jsonb_build_object('weekly_dinner_id',p_weekly_dinner);
end $$;

create function bob_dinner_private.live_result(target_club uuid,p_dinner uuid)
returns jsonb language plpgsql stable security invoker set search_path=public as $$
declare f public.weekly_dinner_finances%rowtype; b record; e record;
  meal_q numeric; meal_r numeric; food numeric; others numeric; revenue numeric; cost numeric;
  links jsonb; sales jsonb;
begin
  select * into f from public.weekly_dinner_finances where dinner_id=p_dinner and club_id=target_club;
  with dinner_lines as (
    select i.*, c.component_override,
      coalesce(c.component_override,i.dinner_component_snapshot) effective_component
    from public.bar_sales s join public.bar_sale_items i on i.sale_id=s.id and i.club_id=s.club_id
      left join public.weekly_dinner_sale_item_classifications c
        on c.club_id=s.club_id and c.dinner_id=p_dinner and c.sale_item_id=i.id
    where s.club_id=target_club and s.weekly_dinner_id=p_dinner and s.status='completed'
  )
  select coalesce(sum(i.quantity) filter(where i.effective_component='meal'),0) meal_quantity,
    coalesce(sum(i.line_total) filter(where i.effective_component='meal'),0) meal_revenue,
    coalesce(sum(i.line_total) filter(where i.effective_component='bar'),0) beverage_revenue,
    coalesce(sum(i.cost_total_snapshot) filter(where i.effective_component='bar'),0) beverage_cost,
    count(*) filter(where (i.effective_component='bar' and i.cost_total_snapshot is null)
      or i.effective_component is null) missing_cost_count,
    coalesce(sum(i.line_total) filter(where i.effective_component='excluded'),0) excluded_revenue,
    count(*) filter(where i.effective_component='excluded') excluded_line_count,
    coalesce(jsonb_agg(jsonb_build_object('sale_item_id',i.id,'sale_id',i.sale_id,
      'description',i.description,'quantity',i.quantity,'unit_price',i.unit_price,'line_total',i.line_total,
      'original_component',i.dinner_component_snapshot,'component_override',i.component_override,
      'effective_component',i.effective_component) order by i.sale_id,i.id)
      filter(where i.dinner_component_snapshot='excluded' and i.line_total>0),'[]'::jsonb) classification_lines
  into b from dinner_lines i;
  -- Reversed expense originals contribute zero; reversal entries are never links.
  select coalesce(sum(t.amount) filter(where l.cost_kind='food' and not exists(
      select 1 from public.treasury_transactions r where r.reversal_of=t.id)),0) food,
    coalesce(sum(t.amount) filter(where l.cost_kind='other' and not exists(
      select 1 from public.treasury_transactions r where r.reversal_of=t.id)),0) other
    into e from public.weekly_dinner_expenses l join public.treasury_transactions t on t.id=l.transaction_id
    where l.club_id=target_club and l.dinner_id=p_dinner;
  meal_q:=case when f.meal_mode='manual' then f.manual_meal_quantity else b.meal_quantity end;
  meal_r:=case when f.meal_mode='manual' then f.manual_meal_revenue else b.meal_revenue end;
  food:=coalesce(f.food_cost_manual,0)+e.food; others:=coalesce(f.other_cost_manual,0)+e.other;
  revenue:=meal_r+b.beverage_revenue; cost:=food+b.beverage_cost+others;
  select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'transaction_id',t.id,'cost_kind',l.cost_kind,
    'description',t.description,'amount',t.amount,'reversed',exists(select 1 from public.treasury_transactions r where r.reversal_of=t.id))
    order by t.transaction_date,t.id),'[]'::jsonb) into links
    from public.weekly_dinner_expenses l join public.treasury_transactions t on t.id=l.transaction_id
    where l.club_id=target_club and l.dinner_id=p_dinner;
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'customer_label',s.customer_label,'total_amount',s.total_amount,'completed_at',s.completed_at)
    order by s.completed_at,s.id),'[]'::jsonb) into sales from public.bar_sales s
    where s.club_id=target_club and s.weekly_dinner_id=p_dinner and s.status='completed';
  return jsonb_build_object('meal_quantity',meal_q,'meal_revenue',meal_r,'food_cost',food,'meal_profit',meal_r-food,
    'bar_meal_quantity',b.meal_quantity,'bar_meal_revenue',b.meal_revenue,'beverage_revenue',b.beverage_revenue,
    'beverage_cost',case when b.missing_cost_count=0 then b.beverage_cost else null end,
    'beverage_profit',case when b.missing_cost_count=0 then b.beverage_revenue-b.beverage_cost else null end,
    'food_cost_linked',e.food,'other_cost_linked',e.other,'other_costs',others,'total_revenue',revenue,
    'total_cost',case when b.missing_cost_count=0 then cost else null end,
    'result',case when b.missing_cost_count=0 then revenue-cost else null end,
    'margin_percent',case when b.missing_cost_count>0 then null when revenue>0 then (revenue-cost)/revenue*100 else 0 end,
    'missing_cost_count',b.missing_cost_count,'excluded_revenue',b.excluded_revenue,'excluded_line_count',b.excluded_line_count,'classification_lines',b.classification_lines,'expense_links',links,'sales',sales);
end $$;
revoke all on function bob_dinner_private.live_result(uuid,uuid) from public,anon,authenticated;

create function public.weekly_dinner_finance_v1(target_club uuid,p_dinner uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare f public.weekly_dinner_finances%rowtype; result jsonb; revisions jsonb; begin
  perform bob_dinner_private.require_access(target_club);
  if not exists(select 1 from public.weekly_dinners where id=p_dinner and club_id=target_club) then
    raise exception 'Jantar não encontrado.'; end if;
  select * into f from public.weekly_dinner_finances where dinner_id=p_dinner and club_id=target_club;
  result:=case when f.financial_status='closed' then f.snapshot
    else bob_dinner_private.live_result(target_club,p_dinner) end;
  select coalesce(jsonb_agg(jsonb_build_object('revision',revision,'closed_at',closed_at,'snapshot',snapshot)
    order by revision desc),'[]'::jsonb) into revisions from public.weekly_dinner_financial_snapshots
    where dinner_id=p_dinner and club_id=target_club;
  return result||jsonb_build_object('dinner_id',p_dinner,'financial_status',coalesce(f.financial_status,'none'),
    'meal_mode',coalesce(f.meal_mode,'automatic'),'manual_meal_quantity',coalesce(f.manual_meal_quantity,0),
    'manual_meal_revenue',coalesce(f.manual_meal_revenue,0),'food_cost_manual',coalesce(f.food_cost_manual,0),
    'other_cost_manual',coalesce(f.other_cost_manual,0),'notes',f.notes,'closed_at',f.closed_at,'closed_by',f.closed_by,
    'revision',coalesce(f.revision,0),'previous_snapshots',revisions);
end $$;

create function public.save_weekly_dinner_finance_v1(target_club uuid,p_dinner uuid,
  p_meal_mode text,p_meal_quantity numeric,p_meal_revenue numeric,p_food_cost numeric,p_other_cost numeric,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform bob_dinner_private.require_access(target_club,true);
  perform 1 from public.weekly_dinners where id=p_dinner and club_id=target_club for update;
  if not found then raise exception 'Jantar não encontrado.'; end if;
  if exists(select 1 from public.weekly_dinner_finances where dinner_id=p_dinner and financial_status='closed') then
    raise exception 'Reabre o fecho financeiro antes de alterar valores.'; end if;
  if p_meal_mode not in ('automatic','manual') or p_meal_mode is null
    or p_meal_quantity is null or p_meal_quantity<0 or p_meal_revenue is null or p_meal_revenue<0
    or p_food_cost is null or p_food_cost<0 or p_other_cost is null or p_other_cost<0 then
    raise exception 'Valores financeiros inválidos.'; end if;
  if p_meal_quantity::text in ('NaN','Infinity','-Infinity')
    or p_meal_revenue::text in ('NaN','Infinity','-Infinity')
    or p_food_cost::text in ('NaN','Infinity','-Infinity')
    or p_other_cost::text in ('NaN','Infinity','-Infinity') then
    raise exception 'Valores financeiros têm de ser finitos.'; end if;
  insert into public.weekly_dinner_finances(club_id,dinner_id,meal_mode,manual_meal_quantity,manual_meal_revenue,
    food_cost_manual,other_cost_manual,notes,created_by,updated_by)
    values(target_club,p_dinner,p_meal_mode,p_meal_quantity,p_meal_revenue,p_food_cost,p_other_cost,p_notes,auth.uid(),auth.uid())
    on conflict(dinner_id) do update set meal_mode=excluded.meal_mode,manual_meal_quantity=excluded.manual_meal_quantity,
      manual_meal_revenue=excluded.manual_meal_revenue,food_cost_manual=excluded.food_cost_manual,
      other_cost_manual=excluded.other_cost_manual,notes=excluded.notes,updated_at=now(),updated_by=auth.uid();
end $$;

create function public.link_weekly_dinner_expense_v1(target_club uuid,p_dinner uuid,p_transaction uuid,p_kind text,p_remove boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare t public.treasury_transactions%rowtype; begin
  perform bob_dinner_private.require_access(target_club,true);
  perform 1 from public.weekly_dinners where id=p_dinner and club_id=target_club for update;
  if not found then raise exception 'Jantar não encontrado.'; end if;
  if exists(select 1 from public.weekly_dinner_finances where dinner_id=p_dinner and financial_status='closed') then
    raise exception 'Reabre o fecho financeiro.'; end if;
  if p_remove then
    delete from public.weekly_dinner_expenses where dinner_id=p_dinner and transaction_id=p_transaction and club_id=target_club;
    return;
  end if;
  select * into t from public.treasury_transactions where id=p_transaction and club_id=target_club for update;
  if not found or t.kind::text<>'expense' or t.reversal_of is not null
    or exists(select 1 from public.treasury_transactions where reversal_of=t.id) then
    raise exception 'Apenas despesas não revertidas do mesmo clube.'; end if;
  -- BAR/inventory purchases are already recognized through stock consumption.
  -- Linking them as food/other would silently count inventory costs twice.
  if t.source_type in ('bar','bar_purchase','bar_operation','inventory','stock_purchase') then
    raise exception 'Compra de stock: custo reconhecido através do consumo, não nesta ligação.'; end if;
  insert into public.weekly_dinner_expenses(club_id,dinner_id,transaction_id,cost_kind,created_by,updated_by)
    values(target_club,p_dinner,p_transaction,p_kind,auth.uid(),auth.uid());
end $$;

create function public.set_weekly_dinner_financial_closed_v1(target_club uuid,p_dinner uuid,p_closed boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare f public.weekly_dinner_finances%rowtype; result jsonb; begin
  perform bob_dinner_private.require_access(target_club,true);
  perform 1 from public.weekly_dinners where id=p_dinner and club_id=target_club for update;
  if not found then raise exception 'Jantar não encontrado.'; end if;
  insert into public.weekly_dinner_finances(club_id,dinner_id,created_by,updated_by)
    values(target_club,p_dinner,auth.uid(),auth.uid()) on conflict(dinner_id) do nothing;
  select * into f from public.weekly_dinner_finances where dinner_id=p_dinner for update;
  if p_closed is null then raise exception 'Estado inválido.'; end if;
  if p_closed and f.financial_status<>'closed' then
    perform t.id from public.treasury_transactions t join public.weekly_dinner_expenses l on l.transaction_id=t.id
      where l.dinner_id=p_dinner order by t.id for update of t;
    if exists(select 1 from public.bar_sales where weekly_dinner_id=p_dinner and status='draft') then
      raise exception 'Existem vendas em rascunho associadas ao jantar.'; end if;
    result:=bob_dinner_private.live_result(target_club,p_dinner);
    -- Excluded items remain unclassified, never silently included as beverages.
    -- line_total is constrained >= 0: any positive excluded line makes this
    -- sum positive. Resolve its association before recording a final snapshot.
    if (result->>'excluded_revenue')::numeric>0 then
      raise exception 'Existem vendas do BAR por classificar neste jantar. Classifica ou corrige essas vendas antes de fechar financeiramente.';
    end if;
    if (result->>'missing_cost_count')::integer>0 then
      raise exception 'Vendas antigas sem custo/classificação fiável: não é possível fechar.'; end if;
    insert into public.weekly_dinner_financial_snapshots(club_id,dinner_id,revision,snapshot,closed_by)
      values(target_club,p_dinner,f.revision+1,result||jsonb_build_object('meal_mode',f.meal_mode,
        'food_cost_manual',f.food_cost_manual,'other_cost_manual',f.other_cost_manual,'notes',f.notes),auth.uid());
    update public.weekly_dinner_finances set financial_status='closed',snapshot=result,revision=f.revision+1,
      closed_at=now(),closed_by=auth.uid(),updated_at=now(),updated_by=auth.uid() where dinner_id=p_dinner;
  elsif not p_closed and f.financial_status='closed' then
    -- Retain the previous snapshot and append-only revision archive on reopen.
    update public.weekly_dinner_finances set financial_status='open',updated_at=now(),updated_by=auth.uid() where dinner_id=p_dinner;
  end if;
  return public.weekly_dinner_finance_v1(target_club,p_dinner);
end $$;

create function public.classify_weekly_dinner_sale_item_v1(
  target_club uuid,p_dinner uuid,p_sale_item uuid,p_component text default null
) returns void language plpgsql security definer set search_path=public as $$
declare item public.bar_sale_items%rowtype; begin
  perform bob_dinner_private.require_access(target_club,true);
  -- Share the dinner lock with close/reopen and sale association changes.
  -- Do not lock sale rows after dinner rows: sale triggers use the reverse order.
  perform 1 from public.weekly_dinners where id=p_dinner and club_id=target_club for update;
  if not found then raise exception 'Jantar não encontrado neste clube.'; end if;
  if exists(select 1 from public.weekly_dinner_finances where dinner_id=p_dinner and financial_status='closed') then
    raise exception 'Reabre o fecho financeiro antes de alterar classificações.'; end if;
  select i.* into item from public.bar_sale_items i join public.bar_sales s
    on s.id=i.sale_id and s.club_id=i.club_id
    where i.id=p_sale_item and i.club_id=target_club and s.weekly_dinner_id=p_dinner and s.status='completed';
  if not found then raise exception 'Linha de venda não encontrada neste jantar.'; end if;
  if item.dinner_component_snapshot is distinct from 'excluded' or item.line_total<=0 then
    raise exception 'Apenas receita originalmente por classificar pode ser corrigida.'; end if;
  if p_component is null then
    delete from public.weekly_dinner_sale_item_classifications
      where club_id=target_club and dinner_id=p_dinner and sale_item_id=p_sale_item;
    return;
  end if;
  if p_component not in ('meal','bar') then raise exception 'Classificação financeira inválida.'; end if;
  if p_component='bar' and (item.cost_total_snapshot is null or item.cost_total_snapshot<0
    or item.cost_total_snapshot::text in ('NaN','Infinity','-Infinity')) then
    raise exception 'Não é possível classificar como BAR sem custo histórico de stock fiável.'; end if;
  insert into public.weekly_dinner_sale_item_classifications(club_id,dinner_id,sale_item_id,component_override,created_by,updated_by)
    values(target_club,p_dinner,p_sale_item,p_component,auth.uid(),auth.uid())
    on conflict(dinner_id,sale_item_id) do update set component_override=excluded.component_override,
      updated_at=now(),updated_by=auth.uid();
end $$;

create function public.assign_bar_sale_dinner_v1(target_club uuid,p_sale uuid,p_dinner uuid default null)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform bob_dinner_private.require_access(target_club,true);
  -- Explicit correction only. No historical date-based auto association.
  update public.bar_sales set weekly_dinner_id=p_dinner,updated_by=auth.uid(),updated_at=now()
    where club_id=target_club and id=p_sale and status='completed';
  if not found then raise exception 'Venda concluída não encontrada.'; end if;
end $$;

create function public.weekly_dinner_finance_choices_v1(target_club uuid,p_dinner uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare expenses jsonb; sales jsonb; begin
  perform bob_dinner_private.require_access(target_club,true);
  if not exists(select 1 from public.weekly_dinners where id=p_dinner and club_id=target_club) then raise exception 'Jantar inválido.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'description',t.description,'amount',t.amount,
    'transaction_date',t.transaction_date) order by t.transaction_date desc,t.id),'[]'::jsonb) into expenses
    from public.treasury_transactions t where t.club_id=target_club and t.kind::text='expense'
      and t.reversal_of is null and not exists(select 1 from public.treasury_transactions r where r.reversal_of=t.id)
      and not exists(select 1 from public.weekly_dinner_expenses l where l.transaction_id=t.id)
      and coalesce(t.source_type,'') not in ('bar','bar_purchase','bar_operation','inventory','stock_purchase');
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'customer_label',s.customer_label,'total_amount',s.total_amount,
    'completed_at',s.completed_at) order by s.completed_at desc,s.id),'[]'::jsonb) into sales
    from public.bar_sales s where s.club_id=target_club and s.status='completed' and s.weekly_dinner_id is null;
  return jsonb_build_object('expenses',expenses,'sales',sales);
end $$;

create function public.weekly_dinner_financial_history_v1(target_club uuid,p_year integer)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare rows jsonb; totals record; begin
  perform bob_dinner_private.require_access(target_club);
  if p_year is null or p_year<1900 or p_year>2200 then raise exception 'Ano inválido.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'dinner_date',d.dinner_date,'dish',d.dish,
    'financial_status',coalesce(f.financial_status,'none'),'summary',case when f.financial_status='closed' then f.snapshot else null end)
    order by d.dinner_date desc,d.id),'[]'::jsonb) into rows
    from public.weekly_dinners d left join public.weekly_dinner_finances f on f.dinner_id=d.id
    where d.club_id=target_club and extract(year from d.dinner_date)=p_year;
  select count(*) n,coalesce(sum((f.snapshot->>'total_revenue')::numeric),0) revenue,
    coalesce(sum((f.snapshot->>'total_cost')::numeric),0) cost,coalesce(sum((f.snapshot->>'result')::numeric),0) result
    into totals from public.weekly_dinners d join public.weekly_dinner_finances f on f.dinner_id=d.id
    where d.club_id=target_club and extract(year from d.dinner_date)=p_year and f.financial_status='closed';
  return jsonb_build_object('rows',rows,'closed_count',totals.n,'total_revenue',totals.revenue,'total_cost',totals.cost,
    'result',totals.result,'margin_percent',case when totals.revenue>0 then totals.result/totals.revenue*100 else 0 end);
end $$;

-- Operational selector exposes only dinner labels, never closing amounts.
create function public.bar_weekly_dinner_choices_v1(target_club uuid)
returns table(id uuid,dinner_date date,dish text,status text)
language plpgsql stable security definer set search_path=public as $$ begin
  if auth.uid() is null or not public.has_club_access(target_club)
    or not public.has_club_permission(target_club,'viewBar') then
    raise exception 'Sem autorização BAR.' using errcode='42501'; end if;
  return query select d.id,d.dinner_date,d.dish,d.status from public.weekly_dinners d
    where d.club_id=target_club and d.status not in ('cancelled','closed')
      and not exists(select 1 from public.weekly_dinner_finances f
        where f.dinner_id=d.id and f.financial_status='closed')
    order by d.dinner_date desc,d.id;
end $$;

-- Only the explicitly authorized public RPC surface is executable.
do $$ declare signature regprocedure; begin
  for signature in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('create_bar_sale_v3','complete_bar_sale_v3',
      'weekly_dinner_finance_v1','save_weekly_dinner_finance_v1','link_weekly_dinner_expense_v1',
      'set_weekly_dinner_financial_closed_v1','assign_bar_sale_dinner_v1','classify_weekly_dinner_sale_item_v1',
      'weekly_dinner_finance_choices_v1','weekly_dinner_financial_history_v1','bar_weekly_dinner_choices_v1') loop
    execute format('revoke all on function %s from public,anon',signature);
    execute format('grant execute on function %s to authenticated',signature);
  end loop;
end $$;
commit;
