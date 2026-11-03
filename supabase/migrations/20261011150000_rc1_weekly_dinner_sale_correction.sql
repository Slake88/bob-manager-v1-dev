begin;

-- Sale association is an administrative correction. The BAR flow remains the
-- normal source: only completed sales already linked to this dinner count.
create or replace function public.weekly_dinner_finance_choices_v1(
  target_club uuid,p_dinner uuid
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare expenses jsonb; sales jsonb;
begin
  perform bob_dinner_private.require_access(target_club,true);
  if not exists(select 1 from public.weekly_dinners where id=p_dinner and club_id=target_club) then
    raise exception 'Jantar inválido.';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'description',t.description,'amount',t.amount,
    'transaction_date',t.transaction_date) order by t.transaction_date desc,t.id),'[]'::jsonb) into expenses
    from public.treasury_transactions t where t.club_id=target_club and t.kind::text='expense'
      and t.reversal_of is null and not exists(select 1 from public.treasury_transactions r where r.reversal_of=t.id)
      and not exists(select 1 from public.weekly_dinner_expenses l where l.transaction_id=t.id)
      and coalesce(t.source_type,'') not in ('bar','bar_purchase','bar_operation','inventory','stock_purchase');
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'customer_label',s.customer_label,
    'total_amount',s.total_amount,'completed_at',s.completed_at,'weekly_dinner_id',s.weekly_dinner_id,
    'weekly_dinner_dish',d.dish) order by s.completed_at desc,s.id),'[]'::jsonb) into sales
    from public.bar_sales s left join public.weekly_dinners d
      on d.club_id=s.club_id and d.id=s.weekly_dinner_id
    where s.club_id=target_club and s.status='completed';
  return jsonb_build_object('expenses',expenses,'sales',sales);
end $$;

create or replace function public.assign_bar_sale_dinner_v1(
  target_club uuid,p_sale uuid,p_dinner uuid default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform bob_dinner_private.require_access(target_club,true);
  if p_dinner is not null and not exists(
    select 1 from public.weekly_dinners where id=p_dinner and club_id=target_club
  ) then raise exception 'Jantar inválido.'; end if;
  if not exists(select 1 from public.bar_sales where id=p_sale and club_id=target_club and status='completed') then
    raise exception 'Venda concluída não encontrada.';
  end if;
  -- trg_dinner_sale_guard locks both affected dinners and rejects closed ones.
  -- trg_audit_capture_v1 records the association update and actor.
  update public.bar_sales set weekly_dinner_id=p_dinner,updated_by=auth.uid(),updated_at=now()
    where id=p_sale and club_id=target_club;
end $$;

revoke all on function public.weekly_dinner_finance_choices_v1(uuid,uuid) from public,anon;
grant execute on function public.weekly_dinner_finance_choices_v1(uuid,uuid) to authenticated;
revoke all on function public.assign_bar_sale_dinner_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.assign_bar_sale_dinner_v1(uuid,uuid,uuid) to authenticated;

commit;
