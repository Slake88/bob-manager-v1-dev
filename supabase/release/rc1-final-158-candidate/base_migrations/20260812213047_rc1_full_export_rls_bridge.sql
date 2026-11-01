-- Commit 20 hardening: fixed Direction export must not depend on module RLS.
-- This is a NEW migration layered on top of 20260812210544.

create or replace function public.club_export_dataset_v1(
  target_club uuid,
  p_export uuid,
  p_dataset text,
  p_offset integer default 0,
  p_limit integer default 1000
)
returns setof jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_export public.exports%rowtype;
  v_section text;
  v_sensitive boolean := false;
  v_sql text;
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 1000);
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  select *
    into v_export
  from public.exports
  where id = p_export
    and club_id = target_club
    and requested_by = auth.uid()
    and status = 'running';

  if not found then
    raise exception 'Exportação ativa não encontrada.';
  end if;

  case p_dataset
    when 'membros/membros.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_number,t.full_name,t.nickname,t.email,t.phone,t.birth_date,t.joined_at,t.status,t.prospect_joined_at,t.full_colors_at,t.primary_role,t.additional_roles,t.photo_path from public.members t where t.club_id = $1 order by t.member_number, t.id offset $2 limit $3) row_data';
    when 'membros/dados_sensiveis.csv' then
      v_section := 'members';
      v_sensitive := true;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_number,t.full_name,t.tax_number,t.address,t.postal_code,t.locality,t.emergency_contact,t.notes from public.members t where t.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'membros/motas.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.brand,t.model,t.year,t.registration,t.nickname,t.primary_motorcycle,t.active,t.acquired_on,t.retired_on,t.notes from public.member_motorcycles t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'membros/cargos.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.position_id,t.is_primary,t.starts_at,t.ends_at from public.member_positions t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'membros/estados_historico.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.old_status,t.new_status,t.changed_at,t.changed_by,t.notes from public.member_status_history t where t.club_id = $1 order by t.changed_at, t.id offset $2 limit $3) row_data';
    when 'membros/timeline.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.event_type,t.title,t.description,t.event_date,t.visibility,t.source_type,t.source_id from public.member_timeline t where t.club_id = $1 order by t.event_date, t.id offset $2 limit $3) row_data';
    when 'membros/patches.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.product_id,t.variant_id,t.patch_name,t.variant_name,t.status,t.requested_at,t.approved_at,t.delivered_at,t.delivery_location_name,t.notes from public.member_patch_awards t where t.club_id = $1 order by t.requested_at, t.id offset $2 limit $3) row_data';
    when 'membros/manutencao.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.motorcycle_id,t.service_date,t.service_type,t.description,t.odometer_km,t.workshop,t.cost,t.next_service_date,t.next_service_km,t.notes from public.maintenance_records t where t.club_id = $1 order by t.service_date, t.id offset $2 limit $3) row_data';
    when 'membros/manutencao_anexos.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.maintenance_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size from public.maintenance_attachments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'tesouraria/contas.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.account_type,t.iban,t.opening_balance,t.opening_date,t.active,t.allows_negative from public.treasury_accounts t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/categorias.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.direction,t.active from public.treasury_categories t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/centros_custo.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.code,t.active from public.cost_centers t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/movimentos.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.kind,t.account_id,t.destination_account_id,t.category_id,t.cost_center_id,t.event_id,t.transaction_date,t.description,t.amount,t.payment_method,t.notes,t.source_type,t.source_id,t.reversal_of,t.created_at from public.treasury_transactions t where t.club_id = $1 order by t.transaction_date, t.id offset $2 limit $3) row_data';
    when 'financeiro/pedidos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.request_type,t.category,t.batch_id,t.amount,t.description,t.due_date,t.status,t.review_note,t.payment_method,t.treasury_account_id,t.treasury_transaction_id,t.submitted_at,t.paid_at,t.source_type,t.source_id,t.created_at from public.financial_requests t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'financeiro/pedidos_anexos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.request_id,t.kind,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at from public.financial_request_attachments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'financeiro/documentos_movimentos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.transaction_id,t.document_type,t.origin,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.is_primary,t.created_at from public.financial_transaction_documents t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'quotas/planos.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.amount,t.frequency,t.due_day,t.active from public.fee_plans t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'quotas/obrigacoes.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.fee_plan_id,t.reference_year,t.reference_month,t.due_date,t.amount,t.paid_amount,t.status,t.notes,t.obligation_type from public.fee_obligations t where t.club_id = $1 order by t.due_date, t.id offset $2 limit $3) row_data';
    when 'quotas/pagamentos.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.obligation_id,t.transaction_id,t.amount,t.paid_at,t.received_by,t.notes from public.fee_payments t where t.club_id = $1 order by t.paid_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/participantes.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.status,t.numbers,t.stars,t.created_at from public.euromillions_players t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/sorteios.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.week,t.start_date,t.end_date,t.unit_cost,t.total_bet,t.prize,t.bulletin_path,t.status,t.created_at from public.euromillions_draws t where t.club_id = $1 order by t.start_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/chaves.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_id,t.numbers,t.stars from public.euromillions_keys t join public.euromillions_draws p on p.id = t.draw_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'euromilhoes/participacoes.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_id,t.member_id,t.amount,t.paid,t.paid_at,t.billing_frequency,t.numbers,t.stars,t.paid_amount,t.balance,t.active,t.payment_method,t.transaction_id from public.euromillions_participations t join public.euromillions_draws p on p.id = t.draw_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'euromilhoes/resultados.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_date,t.numbers,t.stars,t.official_draw_number,t.prize_table,t.source,t.imported_at,t.created_at from public.euromillions_results t where t.club_id = $1 order by t.draw_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/cobrancas.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.player_id,t.week_start,t.draw_date,t.amount,t.paid_amount,t.paid_at,t.payment_method,t.transaction_id from public.euromillions_draw_charges t where t.club_id = $1 order by t.draw_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/multas.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.result_id,t.player_id,t.missed_numbers,t.missed_stars,t.fine_amount,t.paid_amount,t.paid_at,t.payment_method,t.transaction_id,t.created_at from public.euromillions_fines t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/premios.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.result_id,t.player_id,t.category,t.matched_numbers,t.matched_stars,t.prize_amount,t.received_amount,t.received_at,t.payment_method,t.transaction_id,t.created_at from public.euromillions_prizes t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'eventos/eventos.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.location,t.starts_at,t.ends_at,t.status,t.capacity,t.budget,t.event_mode_enabled,t.created_at,t.updated_at from public.events t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'eventos/inscricoes.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.member_id,t.guest_name,t.status,t.checked_in_at,t.notes,t.created_at from public.event_registrations t join public.events p on p.id = t.event_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'eventos/voluntarios.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.member_id,t.function_name,t.status,t.created_at from public.event_volunteers t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'eventos/parceiros.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.partner_type,t.name,t.contact_name,t.phone,t.email,t.agreed_value,t.paid_value,t.notes from public.event_partners t join public.events p on p.id = t.event_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/produtos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.sku,t.category,t.unit,t.cost,t.sale_price,t.minimum_stock,t.current_stock,t.reserved_stock,t.inventory_area,t.description,t.supplier,t.institutional_delivery,t.purchase_unit,t.consumption_unit,t.units_per_purchase,t.purchase_cost,t.active,t.photo_path from public.products t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/variantes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.name,t.sku,t.attributes,t.active,t.current_stock,t.reserved_stock,t.minimum_stock,t.cost,t.sale_price,t.photo_path from public.product_variants t join public.products p on p.id = t.product_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/imagens_produtos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.storage_path,t.is_primary,t.created_at from public.product_images t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/categorias.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.area,t.name,t.active,t.created_at from public.inventory_categories t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/precos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.audience,t.price,t.created_at from public.inventory_prices t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/visibilidade.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.audience,t.allowed,t.created_at from public.inventory_visibility t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/localizacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.location_type,t.event_id,t.parent_id,t.active from public.inventory_locations t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/stock_localizacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.location_id,t.quantity,t.reserved_quantity,t.created_at,t.updated_at from public.inventory_stock_balances t where t.club_id = $1 order by t.updated_at, t.id offset $2 limit $3) row_data';
    when 'inventario/movimentos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.event_id,t.kind,t.quantity,t.unit_cost,t.notes,t.from_location_id,t.to_location_id,t.transfer_group_id,t.created_at from public.stock_movements t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.external_name,t.external_contact,t.status,t.total_amount,t.paid_amount,t.notes,t.created_at,t.updated_at from public.shop_orders t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.order_id,t.product_id,t.variant_id,t.quantity,t.unit_price from public.shop_order_items t join public.shop_orders p on p.id = t.order_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas_pagamentos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.order_id,t.amount,t.payment_method,t.treasury_transaction_id,t.created_at from public.shop_order_payments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_number,t.name,t.category,t.description,t.acquisition_date,t.acquisition_value,t.supplier,t.condition,t.location_id,t.responsible_member_id,t.warranty_until,t.last_maintenance_at,t.next_maintenance_at,t.active,t.notes,t.current_value,t.brand,t.model,t.serial_number,t.qr_code,t.requires_inspection,t.inspection_interval_months,t.last_inspection_at,t.next_inspection_at,t.photo_path from public.inventory_assets t where t.club_id = $1 order by t.asset_number, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_imagens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.storage_path,t.image_type,t.is_primary,t.created_at from public.asset_images t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_eventos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.event_type,t.title,t.description,t.metadata,t.created_at from public.asset_events t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_emprestimos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.borrower_type,t.member_id,t.event_id,t.external_name,t.loaned_at,t.expected_return_at,t.returned_at,t.returned_condition,t.notes,t.return_notes,t.created_at from public.asset_loans t where t.club_id = $1 order by t.loaned_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_manutencao.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.maintenance_date,t.maintenance_type,t.description,t.cost,t.supplier,t.next_due_date,t.account_id,t.payment_method,t.treasury_transaction_id,t.created_at from public.asset_maintenance t where t.club_id = $1 order by t.maintenance_date, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_kits.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.active,t.created_at from public.asset_kits t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_kits_itens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.kit_id,t.asset_id,t.quantity from public.asset_kit_items t join public.asset_kits p on p.id = t.kit_id where p.club_id = $1 offset $2 limit $3) row_data';
    when 'inventario/contagens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.location_id,t.event_id,t.status,t.notes,t.started_by,t.started_at,t.completed_by,t.completed_at from public.inventory_count_sessions t where t.club_id = $1 order by t.started_at, t.id offset $2 limit $3) row_data';
    when 'inventario/contagens_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.session_id,t.product_id,t.variant_id,t.theoretical_qty,t.counted_qty,t.difference,t.unit_cost,t.notes,t.photo_path,t.recounted,t.counted_by,t.counted_at from public.inventory_count_items t join public.inventory_count_sessions p on p.id = t.session_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/bar_operacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.event_id,t.operation_type,t.purchase_units,t.consumption_quantity,t.unit_price,t.total_amount,t.payment_method,t.notes,t.treasury_transaction_id,t.created_at from public.bar_operations t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/bar_sessoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.source,t.status,t.notes,t.created_at,t.confirmed_at from public.bar_consumption_sessions t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/bar_sessoes_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.session_id,t.product_id,t.quantity,t.operation_type,t.unit_price,t.notes,t.created_at from public.bar_consumption_session_items t join public.bar_consumption_sessions p on p.id = t.session_id where p.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'documentos/documentos.csv' then
      v_section := 'documents';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.category,t.description,t.document_date,t.version,t.status,t.expires_at,t.sensitive,t.tags,t.linked_entity_type,t.linked_entity_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at,t.updated_at from public.documents t where t.club_id = $1 and t.sensitive = false order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'documentos/documentos_sensiveis.csv' then
      v_section := 'documents';
      v_sensitive := true;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.category,t.description,t.document_date,t.version,t.status,t.expires_at,t.sensitive,t.tags,t.linked_entity_type,t.linked_entity_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at,t.updated_at from public.documents t where t.club_id = $1 and t.sensitive = true order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'comunicacao/comunicados.csv' then
      v_section := 'communication';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.title,t.body,t.priority,t.audience,t.published_at,t.expires_at,t.requires_acknowledgement,t.created_at,t.updated_at from public.announcements t where t.club_id = $1 order by t.published_at, t.id offset $2 limit $3) row_data';
    when 'comunicacao/confirmacoes_leitura.csv' then
      v_section := 'communication';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.announcement_id,t.profile_id,t.acknowledged_at,t.created_at from public.announcement_acknowledgements t where t.club_id = $1 order by t.acknowledged_at, t.id offset $2 limit $3) row_data';
    when 'agenda/itens.csv' then
      v_section := 'agenda';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.item_type,t.title,t.description,t.starts_at,t.ends_at,t.all_day,t.location,t.audience,t.priority,t.status,t.created_at,t.updated_at from public.agenda_items t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/jantares.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.dinner_date,t.dinner_kind,t.status,t.assigned_member_id,t.external_name,t.dish,t.notes,t.assignment_source,t.generated,t.created_at,t.updated_at from public.weekly_dinners t where t.club_id = $1 order by t.dinner_date, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/rotacao.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.rotation_order,t.enabled,t.availability_status,t.force_included,t.joined_rotation_at,t.notes,t.created_at,t.updated_at from public.weekly_officer_rotation t where t.club_id = $1 order by t.rotation_order, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/ausencias.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.absence_kind,t.starts_on,t.ends_on,t.notes,t.created_at,t.updated_at from public.weekly_officer_absences t where t.club_id = $1 order by t.starts_on, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/trocas.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.dinner_id,t.requester_member_id,t.requested_member_id,t.status,t.requester_note,t.response_note,t.manager_note,t.responded_at,t.responded_by,t.applied_at,t.applied_by,t.created_at,t.updated_at from public.weekly_officer_swap_requests t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'configuracao/clube.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.legal_name,t.slug,t.primary_color,t.currency,t.timezone,t.active,t.created_at,t.updated_at from public.clubs t where t.id = $1 order by t.id offset $2 limit $3) row_data';
    when 'configuracao/cargos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.code,t.name,t.sort_order,t.active,t.created_at,t.updated_at from public.club_positions t where t.club_id = $1 order by t.sort_order, t.id offset $2 limit $3) row_data';
    when 'configuracao/permissoes_cargos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.role_key,t.permission_key,t.allowed,t.updated_at,t.created_at from public.club_role_permissions t where t.club_id = $1 offset $2 limit $3) row_data';
    when 'configuracao/parametros.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.key,t.value,t.created_at,t.updated_at from public.club_settings t where t.club_id = $1 order by t.key, t.id offset $2 limit $3) row_data';
    when 'configuracao/acessos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.profile_id,t.access_role,t.active,t.created_at,t.updated_at from public.club_memberships t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'configuracao/excecoes_permissoes.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.profile_id,t.permission_key,t.allowed,t.updated_at,t.created_at from public.user_permission_overrides t where t.club_id = $1 offset $2 limit $3) row_data';
    when 'auditoria/audit_log.csv' then
      v_section := 'audit';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.actor_id,t.entity_type,t.entity_id,t.action,t.created_at from public.audit_log t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'auditoria/atividade.csv' then
      v_section := 'audit';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.actor_id,t.activity_type,t.title,t.description,t.entity_type,t.entity_id,t.created_at from public.activity_feed t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    else
      raise exception 'Dataset de exportação inválido.';
  end case;

  if not (v_section = any(v_export.modules)) then
    raise exception 'Dataset fora das áreas selecionadas.';
  end if;

  if v_sensitive and not v_export.include_sensitive then
    raise exception 'Dados sensíveis não autorizados nesta exportação.';
  end if;

  if v_sensitive and not (
    public.has_club_permission(target_club, 'viewEmergencyData')
    and public.has_club_permission(target_club, 'viewSensitiveDocuments')
  ) then
    raise exception 'Sem permissão para dados altamente sensíveis.';
  end if;

  return query execute v_sql using target_club, v_offset, v_limit;
end;
$$;

revoke all on function public.club_export_dataset_v1(uuid,uuid,text,integer,integer)
  from public, anon;
grant execute on function public.club_export_dataset_v1(uuid,uuid,text,integer,integer)
  to authenticated, service_role;

create or replace function public.club_export_file_access_v1(
  p_bucket text,
  p_name text
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.exports e
      where e.requested_by = auth.uid()
        and e.status = 'running'
        and e.include_files = true
        and e.requested_at >= now() - interval '2 hours'
        and e.club_id::text = split_part(p_name, '/', 1)
        and public.has_club_role(
          e.club_id,
          array['president','vice_president','admin','administrator','super_admin']::text[]
        )
        and (
          (p_bucket = 'member-photos' and 'members' = any(e.modules))
          or (p_bucket = 'member-maintenance' and 'members' = any(e.modules))
          or (p_bucket = 'financial-documents' and 'financial' = any(e.modules))
          or (p_bucket = 'inventory-media' and 'inventory' = any(e.modules))
          or (
            p_bucket = 'club-documents'
            and 'documents' = any(e.modules)
            and exists (
              select 1
              from public.documents d
              where d.club_id = e.club_id
                and d.storage_path = p_name
                and (
                  d.sensitive = false
                  or (
                    e.include_sensitive = true
                    and public.has_club_permission(e.club_id, 'viewEmergencyData')
                    and public.has_club_permission(e.club_id, 'viewSensitiveDocuments')
                  )
                )
            )
          )
        )
    );
$$;

revoke all on function public.club_export_file_access_v1(text,text)
  from public, anon;
grant execute on function public.club_export_file_access_v1(text,text)
  to authenticated, service_role;

drop policy if exists club_export_files_select on storage.objects;
create policy club_export_files_select
on storage.objects
for select
to authenticated
using (
  bucket_id in (
    'member-photos',
    'member-maintenance',
    'financial-documents',
    'inventory-media',
    'club-documents'
  )
  and public.club_export_file_access_v1(bucket_id, name)
);