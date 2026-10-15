-- Commit 11 — confirmação atómica de uma compra OCR do Bar.
-- Várias linhas de stock -> uma única despesa financeira.

create or replace function public.confirm_bar_ocr_purchase_v1(
  target_club uuid,
  p_job uuid,
  p_lines jsonb,
  p_event uuid default null,
  p_account uuid default null,
  p_payment_method text default 'Dinheiro',
  p_total numeric default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  j public.financial_ocr_jobs%rowtype;
  r jsonb;
  v_product public.products%rowtype;
  v_product_id uuid;
  v_purchase_units numeric;
  v_unit_price numeric;
  v_quantity numeric;
  v_new_stock numeric;
  v_purchase_unit_cost numeric;
  v_new_average_cost numeric;
  v_line_total numeric;
  v_lines_total numeric:=0;
  v_account uuid;
  v_cost_center uuid;
  v_tx uuid;
  v_desc text;
  v_note text;
  v_line_count integer:=0;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para confirmar compras OCR no Bar.';
  end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then
    raise exception 'Seleciona pelo menos uma linha do documento para entrada em stock.';
  end if;

  select * into j from public.financial_ocr_jobs
  where id=p_job and club_id=target_club and source_kind='bar_import' for update;
  if not found then raise exception 'Pedido OCR do Bar não encontrado.'; end if;
  if j.status not in ('ready','reviewed') then raise exception 'O OCR tem de estar pronto/revisto antes da confirmação.'; end if;
  if j.storage_path is null or j.file_size<=0 then raise exception 'Pedido OCR sem documento original.'; end if;

  if p_event is not null and not exists(select 1 from public.events where id=p_event and club_id=target_club) then raise exception 'Evento inválido.'; end if;

  if p_account is not null then
    if not public.has_club_permission(target_club,'selectBarFinancialAccount') then raise exception 'Sem autorização para escolher a conta financeira do Bar.'; end if;
    select id into v_account from public.treasury_accounts where id=p_account and club_id=target_club and active=true;
    if v_account is null then raise exception 'Conta financeira inválida ou inativa.'; end if;
  else
    select id into v_account from public.treasury_accounts where club_id=target_club and active=true and lower(name)=lower('Caixa') limit 1;
    if v_account is null then select id into v_account from public.treasury_accounts where club_id=target_club and active=true order by created_at limit 1; end if;
    if v_account is null then raise exception 'Não existe nenhuma conta financeira ativa.'; end if;
  end if;

  select id into v_cost_center from public.cost_centers
  where club_id=target_club and active=true and lower(name)=lower('Club House') limit 1;

  -- Primeiro valida todas as linhas, antes de qualquer movimento contabilístico.
  for r in select value from jsonb_array_elements(p_lines) loop
    begin
      v_product_id:=(r->>'product_id')::uuid;
      v_purchase_units:=(r->>'purchase_units')::numeric;
      v_unit_price:=(r->>'unit_price')::numeric;
    exception when others then raise exception 'Linha OCR com produto, quantidade ou preço inválido.'; end;
    if v_purchase_units<=0 or v_unit_price<0 then raise exception 'Quantidade e preço das linhas OCR têm de ser válidos.'; end if;
    select * into v_product from public.products
    where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true;
    if not found then raise exception 'Artigo de Bar inválido numa linha OCR.'; end if;
    if coalesce(v_product.units_per_purchase,0)<=0 then raise exception 'Conversão inválida no artigo %.',v_product.name; end if;
    v_lines_total:=v_lines_total+(v_purchase_units*v_unit_price);
    v_line_count:=v_line_count+1;
  end loop;

  if p_total is null or p_total<=0 then p_total:=v_lines_total; end if;
  if p_total<=0 then raise exception 'Total financeiro inválido.'; end if;

  v_desc:='Compra Bar OCR';
  if coalesce(nullif(btrim(j.supplier_name),''),'')<>'' then v_desc:=v_desc||' - '||j.supplier_name; end if;
  v_note:=nullif(btrim(coalesce(p_notes,'')),'');
  if abs(p_total-v_lines_total)>0.01 then
    v_note:=concat_ws(' | ',v_note,
      'OCR: total do documento '||to_char(p_total,'FM999999990.00')||' €; linhas de stock '||to_char(v_lines_total,'FM999999990.00')||' €');
  end if;

  insert into public.treasury_transactions(
    club_id,kind,account_id,cost_center_id,event_id,transaction_date,description,amount,
    payment_method,notes,source_type,source_id,created_by
  ) values (
    target_club,'expense'::public.transaction_kind,v_account,v_cost_center,p_event,
    coalesce(j.document_date,current_date),v_desc,p_total,p_payment_method,v_note,'bar_ocr',j.id,auth.uid()
  ) returning id into v_tx;

  for r in select value from jsonb_array_elements(p_lines) loop
    v_product_id:=(r->>'product_id')::uuid;
    v_purchase_units:=(r->>'purchase_units')::numeric;
    v_unit_price:=(r->>'unit_price')::numeric;
    select * into v_product from public.products
    where id=v_product_id and club_id=target_club and inventory_area='bar' and active=true for update;

    v_quantity:=v_purchase_units*v_product.units_per_purchase;
    v_new_stock:=coalesce(v_product.current_stock,0)+v_quantity;
    v_purchase_unit_cost:=v_unit_price/v_product.units_per_purchase;
    v_new_average_cost:=case when v_new_stock>0 then
      ((coalesce(v_product.current_stock,0)*coalesce(v_product.cost,0))+(v_quantity*v_purchase_unit_cost))/v_new_stock
      else v_purchase_unit_cost end;
    v_line_total:=v_purchase_units*v_unit_price;

    update public.products set current_stock=v_new_stock,purchase_cost=v_unit_price,cost=v_new_average_cost where id=v_product.id;
    insert into public.stock_movements(club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by)
    values(target_club,v_product.id,p_event,'purchase',v_quantity,v_purchase_unit_cost,
      concat_ws(' | ','Entrada via OCR',nullif(r->>'description','')),auth.uid());
    insert into public.bar_operations(
      club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,
      payment_method,notes,treasury_transaction_id,created_by
    ) values (
      target_club,v_product.id,p_event,'purchase',v_purchase_units,v_quantity,v_unit_price,v_line_total,
      p_payment_method,concat_ws(' | ','OCR',nullif(r->>'description','')),v_tx,auth.uid()
    );
  end loop;

  insert into public.financial_transaction_documents(
    club_id,transaction_id,document_type,origin,storage_path,original_file_name,mime_type,file_size,is_primary
  ) values (
    target_club,v_tx,'receipt','bar_ocr',j.storage_path,coalesce(j.original_file_name,'documento'),j.mime_type,j.file_size,true
  ) on conflict(transaction_id,storage_path) do nothing;
  perform public.refresh_financial_transaction_primary_v1(v_tx);

  update public.financial_ocr_jobs
  set status='confirmed',confirmed_at=now(),confirmed_by=auth.uid(),confirmed_transaction_id=v_tx,
      confirmed_lines=p_lines,transaction_id=v_tx
  where id=j.id;

  perform public.emit_domain_event(
    target_club,'BarOcrPurchaseConfirmed','inventory',v_product_id,
    jsonb_build_object(
      'title',v_desc,'description',v_line_count::text||' linhas · '||to_char(p_total,'FM999999990.00')||' €',
      'module_code','inventory','route','inventory','priority','normal','ocr_job_id',j.id,'transaction_id',v_tx
    )
  );

  return jsonb_build_object(
    'job_id',j.id,'transaction_id',v_tx,'account_id',v_account,'line_count',v_line_count,
    'lines_total',v_lines_total,'financial_total',p_total
  );
end;
$$;

revoke all on function public.confirm_bar_ocr_purchase_v1(uuid,uuid,jsonb,uuid,uuid,text,numeric,text) from public,anon;
grant execute on function public.confirm_bar_ocr_purchase_v1(uuid,uuid,jsonb,uuid,uuid,text,numeric,text) to authenticated;
