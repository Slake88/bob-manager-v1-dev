-- Commit 11 — OCR financeiro e Bar: fundação auditada.
-- O OCR apenas propõe dados. Confirmações financeiras continuam explícitas.

create table if not exists public.financial_ocr_jobs (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  source_kind text not null check (source_kind in ('transaction_document','bar_import')),
  document_id uuid references public.financial_transaction_documents(id) on delete set null,
  transaction_id uuid references public.treasury_transactions(id) on delete set null,
  storage_path text,
  original_file_name text,
  mime_type text,
  file_size bigint not null default 0 check (file_size >= 0 and file_size <= 20971520),
  status text not null default 'draft'
    check (status in ('draft','pending','processing','ready','reviewed','unconfigured','failed','confirmed','cancelled')),
  provider text not null default 'openai',
  model text,
  provider_response_id text,
  supplier_name text,
  supplier_tax_id text,
  document_number text,
  document_date date,
  currency text,
  subtotal numeric,
  tax_total numeric,
  total numeric,
  payment_method text,
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  raw_text text,
  line_items jsonb not null default '[]'::jsonb check (jsonb_typeof(line_items)='array'),
  warnings jsonb not null default '[]'::jsonb check (jsonb_typeof(warnings)='array'),
  usage jsonb not null default '{}'::jsonb check (jsonb_typeof(usage)='object'),
  error_message text,
  started_at timestamptz,
  completed_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  confirmed_at timestamptz,
  confirmed_by uuid references public.profiles(id) on delete set null,
  confirmed_transaction_id uuid references public.treasury_transactions(id) on delete set null,
  confirmed_lines jsonb not null default '[]'::jsonb check (jsonb_typeof(confirmed_lines)='array'),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null default auth.uid()
);

create index if not exists idx_financial_ocr_jobs_club_created
  on public.financial_ocr_jobs(club_id,created_at desc);
create index if not exists idx_financial_ocr_jobs_document
  on public.financial_ocr_jobs(document_id,created_at desc) where document_id is not null;
create index if not exists idx_financial_ocr_jobs_status
  on public.financial_ocr_jobs(club_id,status,updated_at desc);

drop trigger if exists trg_financial_ocr_audit_stamp_v1 on public.financial_ocr_jobs;
create trigger trg_financial_ocr_audit_stamp_v1
before insert or update on public.financial_ocr_jobs
for each row execute function public.audit_stamp_row_v1();

drop trigger if exists trg_financial_ocr_audit_capture_v1 on public.financial_ocr_jobs;
create trigger trg_financial_ocr_audit_capture_v1
after insert or update or delete on public.financial_ocr_jobs
for each row execute function public.audit_capture_row_v1();

alter table public.financial_ocr_jobs enable row level security;
drop policy if exists financial_ocr_jobs_select on public.financial_ocr_jobs;
create policy financial_ocr_jobs_select on public.financial_ocr_jobs
for select to authenticated using (
  case when source_kind='bar_import' then
    public.has_club_permission(club_id,'manageBar')
    or public.has_club_permission(club_id,'viewInventory')
    or public.has_club_permission(club_id,'viewTreasury')
    or public.has_club_permission(club_id,'approveExpenseRequests')
  else
    public.has_club_permission(club_id,'viewTreasury')
    or public.has_club_permission(club_id,'approveExpenseRequests')
  end
);
grant select on table public.financial_ocr_jobs to authenticated;
revoke insert,update,delete on table public.financial_ocr_jobs from anon,authenticated;

create or replace function public.create_bar_ocr_job_v1(target_club uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then
    raise exception 'Sem autorização para usar OCR no Bar.';
  end if;
  insert into public.financial_ocr_jobs(club_id,source_kind,status,provider)
  values(target_club,'bar_import','draft','openai') returning id into v_id;
  return v_id;
end; $$;

create or replace function public.attach_bar_ocr_source_v1(
  target_club uuid,p_job uuid,p_storage_path text,p_original_file_name text,p_mime_type text,p_file_size bigint
) returns void language plpgsql security definer set search_path=public as $$
declare j public.financial_ocr_jobs%rowtype;
begin
  if auth.uid() is null or not public.has_club_permission(target_club,'manageBar') then raise exception 'Sem autorização para usar OCR no Bar.'; end if;
  select * into j from public.financial_ocr_jobs where id=p_job and club_id=target_club and source_kind='bar_import' for update;
  if not found then raise exception 'Pedido OCR não encontrado.'; end if;
  if j.status not in ('draft','failed','unconfigured') then raise exception 'O pedido OCR já não aceita outro ficheiro.'; end if;
  if p_file_size is null or p_file_size<=0 or p_file_size>20971520 then raise exception 'O ficheiro deve ter entre 1 byte e 20 MB.'; end if;
  if lower(coalesce(p_mime_type,'')) not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Formato OCR não suportado. Usa JPG, PNG, WEBP ou PDF.'; end if;
  if p_storage_path not like target_club::text||'/ocr/'||p_job::text||'/%' then raise exception 'Caminho OCR inválido.'; end if;
  update public.financial_ocr_jobs
  set storage_path=p_storage_path,original_file_name=coalesce(nullif(btrim(p_original_file_name),''),'documento'),
      mime_type=lower(p_mime_type),file_size=p_file_size,status='pending',error_message=null,started_at=null,completed_at=null
  where id=p_job;
end; $$;

create or replace function public.start_financial_document_ocr_v1(target_club uuid,p_document uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare d public.financial_transaction_documents%rowtype; j public.financial_ocr_jobs%rowtype; v_id uuid;
begin
  if auth.uid() is null or not (
    public.has_club_permission(target_club,'createTreasuryMovement')
    or public.has_club_permission(target_club,'approveExpenseRequests')
  ) then raise exception 'Sem autorização para executar OCR financeiro.'; end if;
  select * into d from public.financial_transaction_documents where id=p_document and club_id=target_club;
  if not found then raise exception 'Documento financeiro não encontrado.'; end if;
  if lower(coalesce(d.mime_type,'')) not in ('image/jpeg','image/png','image/webp','application/pdf') then raise exception 'Formato OCR não suportado. Usa JPG, PNG, WEBP ou PDF.'; end if;
  select * into j from public.financial_ocr_jobs
  where club_id=target_club and document_id=p_document and status in ('pending','processing','ready','reviewed','unconfigured')
  order by created_at desc limit 1;
  if found then
    if j.status='unconfigured' then
      update public.financial_ocr_jobs set status='pending',error_message=null,started_at=null,completed_at=null where id=j.id;
    end if;
    return j.id;
  end if;
  insert into public.financial_ocr_jobs(
    club_id,source_kind,document_id,transaction_id,storage_path,original_file_name,mime_type,file_size,status,provider
  ) values (
    target_club,'transaction_document',d.id,d.transaction_id,d.storage_path,d.original_file_name,d.mime_type,d.file_size,'pending','openai'
  ) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.retry_financial_ocr_job_v1(target_club uuid,p_job uuid)
returns void language plpgsql security definer set search_path=public as $$
declare j public.financial_ocr_jobs%rowtype; v_allowed boolean;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select * into j from public.financial_ocr_jobs where id=p_job and club_id=target_club for update;
  if not found then raise exception 'Pedido OCR não encontrado.'; end if;
  v_allowed:=case when j.source_kind='bar_import'
    then public.has_club_permission(target_club,'manageBar')
    else public.has_club_permission(target_club,'createTreasuryMovement') or public.has_club_permission(target_club,'approveExpenseRequests') end;
  if not v_allowed then raise exception 'Sem autorização para repetir este OCR.'; end if;
  if j.storage_path is null then raise exception 'Pedido OCR sem ficheiro.'; end if;
  if j.status in ('processing','confirmed','cancelled') then raise exception 'O pedido OCR não pode ser repetido neste estado.'; end if;
  update public.financial_ocr_jobs set status='pending',error_message=null,started_at=null,completed_at=null where id=p_job;
end; $$;

create or replace function public.save_financial_ocr_review_v1(
  target_club uuid,p_job uuid,p_supplier_name text,p_supplier_tax_id text,p_document_number text,p_document_date date,
  p_currency text,p_subtotal numeric,p_tax_total numeric,p_total numeric,p_payment_method text,p_confidence numeric,
  p_line_items jsonb,p_warnings jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare j public.financial_ocr_jobs%rowtype; v_allowed boolean;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select * into j from public.financial_ocr_jobs where id=p_job and club_id=target_club for update;
  if not found then raise exception 'Pedido OCR não encontrado.'; end if;
  v_allowed:=case when j.source_kind='bar_import'
    then public.has_club_permission(target_club,'manageBar')
    else public.has_club_permission(target_club,'createTreasuryMovement') or public.has_club_permission(target_club,'approveExpenseRequests') end;
  if not v_allowed then raise exception 'Sem autorização para rever este OCR.'; end if;
  if j.status not in ('ready','reviewed') then raise exception 'O OCR ainda não está pronto para revisão.'; end if;
  if p_line_items is null or jsonb_typeof(p_line_items)<>'array' then raise exception 'Linhas OCR inválidas.'; end if;
  if p_warnings is null or jsonb_typeof(p_warnings)<>'array' then raise exception 'Avisos OCR inválidos.'; end if;
  update public.financial_ocr_jobs set
    supplier_name=nullif(btrim(coalesce(p_supplier_name,'')),''),supplier_tax_id=nullif(btrim(coalesce(p_supplier_tax_id,'')),''),
    document_number=nullif(btrim(coalesce(p_document_number,'')),''),document_date=p_document_date,
    currency=upper(nullif(btrim(coalesce(p_currency,'')),'')),subtotal=p_subtotal,tax_total=p_tax_total,total=p_total,
    payment_method=nullif(btrim(coalesce(p_payment_method,'')),''),
    confidence=case when p_confidence is null then confidence else greatest(0,least(1,p_confidence)) end,
    line_items=p_line_items,warnings=p_warnings,status='reviewed',reviewed_at=now(),reviewed_by=auth.uid()
  where id=p_job;
end; $$;

-- Evidência originada por OCR fica protegida tal como os comprovativos herdados.
create or replace function public.delete_financial_transaction_document_v1(target_club uuid,p_transaction uuid,p_document uuid)
returns text language plpgsql security definer set search_path=public as $$
declare d public.financial_transaction_documents%rowtype; v_path text;
begin
  if auth.uid() is null or not (
    public.has_club_permission(target_club,'createTreasuryMovement')
    or public.has_club_permission(target_club,'approveExpenseRequests')
  ) then raise exception 'Sem autorização para gerir documentos financeiros.'; end if;
  select * into d from public.financial_transaction_documents
  where id=p_document and transaction_id=p_transaction and club_id=target_club for update;
  if not found then raise exception 'Documento não encontrado.'; end if;
  if d.source_attachment_id is not null or d.origin in ('request','bar_ocr') then
    raise exception 'Este documento pertence ao processo financeiro original e não pode ser eliminado aqui.';
  end if;
  v_path:=d.storage_path;
  delete from public.financial_transaction_documents where id=d.id;
  perform public.refresh_financial_transaction_primary_v1(p_transaction);
  return v_path;
end; $$;

-- O bucket financial-documents passa a aceitar caminhos privados /ocr/<job>/...
create or replace function public.financial_storage_access_v2(p_name text,p_manage boolean default false)
returns boolean language plpgsql stable security definer set search_path=public,storage as $$
declare folders text[]; v_request uuid; v_transaction uuid; v_job uuid; v_club uuid;
begin
  if auth.uid() is null then return false; end if;
  folders:=storage.foldername(p_name);
  if coalesce(array_length(folders,1),0)<2 then return false; end if;
  if folders[2]='transactions' then
    if coalesce(array_length(folders,1),0)<3 then return false; end if;
    begin v_transaction:=folders[3]::uuid; exception when invalid_text_representation then return false; end;
    select t.club_id into v_club from public.treasury_transactions t where t.id=v_transaction;
    if not found or folders[1] is distinct from v_club::text then return false; end if;
    if p_manage then return public.has_club_permission(v_club,'createTreasuryMovement') or public.has_club_permission(v_club,'approveExpenseRequests'); end if;
    return public.has_club_permission(v_club,'viewTreasury') or public.has_club_permission(v_club,'approveExpenseRequests');
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
      or public.has_club_permission(v_club,'viewInventory')
      or public.has_club_permission(v_club,'viewTreasury')
      or public.has_club_permission(v_club,'approveExpenseRequests');
  end if;
  begin v_request:=folders[2]::uuid; exception when invalid_text_representation then return false; end;
  select r.club_id into v_club from public.financial_requests r where r.id=v_request;
  if not found or folders[1] is distinct from v_club::text then return false; end if;
  return public.financial_request_access_v1(v_request);
end; $$;

revoke all on function public.create_bar_ocr_job_v1(uuid) from public,anon;
grant execute on function public.create_bar_ocr_job_v1(uuid) to authenticated;
revoke all on function public.attach_bar_ocr_source_v1(uuid,uuid,text,text,text,bigint) from public,anon;
grant execute on function public.attach_bar_ocr_source_v1(uuid,uuid,text,text,text,bigint) to authenticated;
revoke all on function public.start_financial_document_ocr_v1(uuid,uuid) from public,anon;
grant execute on function public.start_financial_document_ocr_v1(uuid,uuid) to authenticated;
revoke all on function public.retry_financial_ocr_job_v1(uuid,uuid) from public,anon;
grant execute on function public.retry_financial_ocr_job_v1(uuid,uuid) to authenticated;
revoke all on function public.save_financial_ocr_review_v1(uuid,uuid,text,text,text,date,text,numeric,numeric,numeric,text,numeric,jsonb,jsonb) from public,anon;
grant execute on function public.save_financial_ocr_review_v1(uuid,uuid,text,text,text,date,text,numeric,numeric,numeric,text,numeric,jsonb,jsonb) to authenticated;
revoke all on function public.delete_financial_transaction_document_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.delete_financial_transaction_document_v1(uuid,uuid,uuid) to authenticated;
revoke all on function public.financial_storage_access_v2(text,boolean) from public,anon;
grant execute on function public.financial_storage_access_v2(text,boolean) to authenticated;
