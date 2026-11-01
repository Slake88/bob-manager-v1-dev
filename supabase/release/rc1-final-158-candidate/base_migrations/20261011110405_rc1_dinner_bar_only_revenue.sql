-- BAR is the only source of new dinner meal revenue. No data backfill or UPDATE
-- of legacy settings, frozen snapshots or archived revisions is performed.
-- Reopening uses this live calculation; historical closed results keep their
-- original snapshot, including any old manual meal revenue.
begin;

create or replace function bob_dinner_private.live_result(target_club uuid,p_dinner uuid)
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
  meal_q:=b.meal_quantity;
  meal_r:=b.meal_revenue;
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

create or replace function public.save_weekly_dinner_finance_v1(target_club uuid,p_dinner uuid,
  p_meal_mode text,p_meal_quantity numeric,p_meal_revenue numeric,p_food_cost numeric,p_other_cost numeric,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$ begin
  perform bob_dinner_private.require_access(target_club,true);
  perform 1 from public.weekly_dinners where id=p_dinner and club_id=target_club for update;
  if not found then raise exception 'Jantar não encontrado.'; end if;
  if exists(select 1 from public.weekly_dinner_finances where dinner_id=p_dinner and financial_status='closed') then
    raise exception 'Reabre o fecho financeiro antes de alterar valores.'; end if;
  -- Retain the signature for old clients, but reject new manual meal revenue.
  if p_meal_mode is distinct from 'automatic' or p_meal_quantity is distinct from 0::numeric
    or p_meal_revenue is distinct from 0::numeric then
    raise exception 'As refeições e receitas são registadas exclusivamente no BAR.'; end if;
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

revoke all on function bob_dinner_private.live_result(uuid,uuid) from public,anon,authenticated;
revoke all on function public.save_weekly_dinner_finance_v1(uuid,uuid,text,numeric,numeric,numeric,numeric,text) from public,anon;
grant execute on function public.save_weekly_dinner_finance_v1(uuid,uuid,text,numeric,numeric,numeric,numeric,text) to authenticated;
commit;
