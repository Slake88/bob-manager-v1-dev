-- Commit 9: documentos/comprovativos financeiros + galeria por movimento.

create table if not exists public.financial_transaction_documents (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  transaction_id uuid not null references public.treasury_transactions(id) on delete cascade,
  source_attachment_id uuid references public.financial_request_attachments(id) on delete set null,
  document_type text not null check (document_type in ('receipt','payment_proof','invoice_other')),
  origin text not null default 'direct' check (origin in ('direct','request','bar_ocr','import')),
  storage_path text not null,
  original_file_name text not null,
  mime_type text,
  file_size bigint not null default 0 check (file_size >= 0 and file_size <= 20971520),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  unique(transaction_id,storage_path)
);

create index if not exists financial_transaction_documents_tx_idx
  on public.financial_transaction_documents(transaction_id,created_at,id);
create unique index if not exists financial_transaction_documents_source_uidx
  on public.financial_transaction_documents(transaction_id,source_attachment_id)
  where source_attachment_id is not null;
create unique index if not exists financial_transaction_documents_primary_uidx
  on public.financial_transaction_documents(transaction_id)
  where is_primary=true;

drop trigger if exists financial_transaction_documents_audit_stamp on public.financial_transaction_documents;
create trigger financial_transaction_documents_audit_stamp
before insert or update on public.financial_transaction_documents
for each row execute function public.audit_stamp_row_v1();

drop trigger if exists financial_transaction_documents_audit_capture on public.financial_transaction_documents;
create trigger financial_transaction_documents_audit_capture
after insert or update or delete on public.financial_transaction_documents
for each row execute function public.audit_capture_row_v1();

create or replace function public.refresh_financial_transaction_primary_v1(p_transaction uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid; v_path text;
begin
  select d.id,d.storage_path into v_id,v_path
  from public.financial_transaction_documents d
  where d.transaction_id=p_transaction and d.is_primary=true
  order by d.created_at,d.id
  limit 1;

  if v_id is null then
    select d.id,d.storage_path into v_id,v_path
    from public.financial_transaction_documents d
    where d.transaction_id=p_transaction
    order by d.created_at,d.id
    limit 1;
    if v_id is not null then
      update public.financial_transaction_documents
      set is_primary=true
      where id=v_id;
    end if;
  end if;

  update public.treasury_transactions t
  set document_path=v_path
  where t.id=p_transaction
    and t.document_path is distinct from v_path;
end;
$$;

create or replace function public.add_financial_transaction_document_v1(
  target_club uuid,
  p_transaction uuid,
  p_document_type text,
  p_storage_path text,
  p_original_file_name text,
  p_mime_type text,
  p_file_size bigint
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not (
    public.has_club_permission(target_club,'createTreasuryMovement')
    or public.has_club_permission(target_club,'approveExpenseRequests')
  ) then raise exception 'Sem autorização para gerir documentos financeiros.'; end if;

  if not exists(
    select 1 from public.treasury_transactions t
    where t.id=p_transaction and t.club_id=target_club
  ) then raise exception 'Movimento financeiro não encontrado.'; end if;

  if p_document_type not in ('receipt','payment_proof','invoice_other') then
    raise exception 'Categoria de documento inválida.';
  end if;
  if p_file_size is null or p_file_size<=0 or p_file_size>20971520 then
    raise exception 'O ficheiro deve ter entre 1 byte e 20 MB.';
  end if;
  if p_storage_path not like target_club::text||'/transactions/'||p_transaction::text||'/%' then
    raise exception 'Caminho de armazenamento inválido.';
  end if;

  insert into public.financial_transaction_documents(
    club_id,transaction_id,document_type,origin,storage_path,
    original_file_name,mime_type,file_size,is_primary
  ) values (
    target_club,p_transaction,p_document_type,'direct',p_storage_path,
    coalesce(nullif(btrim(p_original_file_name),''),'ficheiro'),
    nullif(btrim(coalesce(p_mime_type,'')),''),p_file_size,false
  ) returning id into v_id;

  perform public.refresh_financial_transaction_primary_v1(p_transaction);
  return v_id;
end;
$$;

create or replace function public.set_primary_financial_transaction_document_v1(
  target_club uuid,
  p_transaction uuid,
  p_document uuid
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if auth.uid() is null or not (
    public.has_club_permission(target_club,'createTreasuryMovement')
    or public.has_club_permission(target_club,'approveExpenseRequests')
  ) then raise exception 'Sem autorização para gerir documentos financeiros.'; end if;

  if not exists(
    select 1 from public.financial_transaction_documents d
    where d.id=p_document and d.transaction_id=p_transaction and d.club_id=target_club
  ) then raise exception 'Documento não encontrado.'; end if;

  update public.financial_transaction_documents
  set is_primary=false
  where club_id=target_club and transaction_id=p_transaction and is_primary=true;

  update public.financial_transaction_documents
  set is_primary=true
  where id=p_document and club_id=target_club and transaction_id=p_transaction;

  perform public.refresh_financial_transaction_primary_v1(p_transaction);
end;
$$;

create or replace function public.delete_financial_transaction_document_v1(
  target_club uuid,
  p_transaction uuid,
  p_document uuid
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare d public.financial_transaction_documents%rowtype; v_path text;
begin
  if auth.uid() is null or not (
    public.has_club_permission(target_club,'createTreasuryMovement')
    or public.has_club_permission(target_club,'approveExpenseRequests')
  ) then raise exception 'Sem autorização para gerir documentos financeiros.'; end if;

  select * into d
  from public.financial_transaction_documents
  where id=p_document and transaction_id=p_transaction and club_id=target_club
  for update;
  if not found then raise exception 'Documento não encontrado.'; end if;
  if d.source_attachment_id is not null then
    raise exception 'Este documento pertence ao processo financeiro original e não pode ser eliminado aqui.';
  end if;

  v_path:=d.storage_path;
  delete from public.financial_transaction_documents where id=d.id;
  perform public.refresh_financial_transaction_primary_v1(p_transaction);
  return v_path;
end;
$$;

create or replace function public.sync_financial_request_documents_v1()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.treasury_transaction_id is null then return new; end if;
  if tg_op='UPDATE' and new.treasury_transaction_id is not distinct from old.treasury_transaction_id then
    return new;
  end if;

  insert into public.financial_transaction_documents(
    club_id,transaction_id,source_attachment_id,document_type,origin,
    storage_path,original_file_name,mime_type,file_size,is_primary,
    created_at,created_by,updated_at,updated_by
  )
  select
    a.club_id,new.treasury_transaction_id,a.id,
    case
      when a.kind='receipt' then 'receipt'
      when a.kind in ('member_payment_proof','club_payment_proof') then 'payment_proof'
      else 'invoice_other'
    end,
    'request',a.storage_path,a.original_file_name,a.mime_type,a.file_size,false,
    a.created_at,a.created_by,a.updated_at,a.updated_by
  from public.financial_request_attachments a
  where a.request_id=new.id
  on conflict do nothing;

  perform public.refresh_financial_transaction_primary_v1(new.treasury_transaction_id);
  return new;
end;
$$;

drop trigger if exists financial_request_transaction_documents_sync on public.financial_requests;
create trigger financial_request_transaction_documents_sync
after update of treasury_transaction_id on public.financial_requests
for each row execute function public.sync_financial_request_documents_v1();

-- Backfill dos pedidos/cobranças já liquidados: apenas liga metadados, sem duplicar ficheiros no Storage.
insert into public.financial_transaction_documents(
  club_id,transaction_id,source_attachment_id,document_type,origin,
  storage_path,original_file_name,mime_type,file_size,is_primary,
  created_at,created_by,updated_at,updated_by
)
select
  a.club_id,r.treasury_transaction_id,a.id,
  case
    when a.kind='receipt' then 'receipt'
    when a.kind in ('member_payment_proof','club_payment_proof') then 'payment_proof'
    else 'invoice_other'
  end,
  'request',a.storage_path,a.original_file_name,a.mime_type,a.file_size,false,
  a.created_at,a.created_by,a.updated_at,a.updated_by
from public.financial_requests r
join public.financial_request_attachments a on a.request_id=r.id
where r.treasury_transaction_id is not null
on conflict do nothing;

do $$
declare r record;
begin
  for r in select distinct transaction_id from public.financial_transaction_documents loop
    perform public.refresh_financial_transaction_primary_v1(r.transaction_id);
  end loop;
end;
$$;

alter table public.financial_transaction_documents enable row level security;

drop policy if exists financial_transaction_documents_read on public.financial_transaction_documents;
create policy financial_transaction_documents_read on public.financial_transaction_documents
for select to authenticated
using (
  public.has_club_permission(club_id,'viewTreasury')
  or public.has_club_permission(club_id,'approveExpenseRequests')
);

grant select on table public.financial_transaction_documents to authenticated;
revoke insert,update,delete on table public.financial_transaction_documents from anon,authenticated;

-- O mesmo bucket privado serve pedidos e movimentos financeiros.
create or replace function public.financial_storage_access_v2(p_name text,p_manage boolean default false)
returns boolean
language plpgsql
stable
security definer
set search_path=public,storage
as $$
declare folders text[]; v_request uuid; v_transaction uuid; v_club uuid;
begin
  if auth.uid() is null then return false; end if;
  folders:=storage.foldername(p_name);
  if coalesce(array_length(folders,1),0)<2 then return false; end if;

  if folders[2]='transactions' then
    if coalesce(array_length(folders,1),0)<3 then return false; end if;
    begin
      v_transaction:=folders[3]::uuid;
    exception when invalid_text_representation then
      return false;
    end;

    select t.club_id into v_club
    from public.treasury_transactions t where t.id=v_transaction;
    if not found or folders[1] is distinct from v_club::text then return false; end if;

    if p_manage then
      return public.has_club_permission(v_club,'createTreasuryMovement')
          or public.has_club_permission(v_club,'approveExpenseRequests');
    end if;
    return public.has_club_permission(v_club,'viewTreasury')
        or public.has_club_permission(v_club,'approveExpenseRequests');
  end if;

  begin
    v_request:=folders[2]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  select r.club_id into v_club
  from public.financial_requests r where r.id=v_request;
  if not found or folders[1] is distinct from v_club::text then return false; end if;
  return public.financial_request_access_v1(v_request);
end;
$$;

drop policy if exists financial_documents_select on storage.objects;
create policy financial_documents_select on storage.objects
for select to authenticated
using (
  bucket_id='financial-documents'
  and public.financial_storage_access_v2(name,false)
);

drop policy if exists financial_documents_insert on storage.objects;
create policy financial_documents_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='financial-documents'
  and public.financial_storage_access_v2(name,true)
);

drop policy if exists financial_documents_delete on storage.objects;
create policy financial_documents_delete on storage.objects
for delete to authenticated
using (
  bucket_id='financial-documents'
  and public.financial_storage_access_v2(name,true)
);

revoke all on function public.refresh_financial_transaction_primary_v1(uuid) from public,anon,authenticated;
revoke all on function public.sync_financial_request_documents_v1() from public,anon,authenticated;

revoke all on function public.financial_storage_access_v2(text,boolean) from public,anon;
grant execute on function public.financial_storage_access_v2(text,boolean) to authenticated;

revoke all on function public.add_financial_transaction_document_v1(uuid,uuid,text,text,text,text,bigint) from public,anon;
grant execute on function public.add_financial_transaction_document_v1(uuid,uuid,text,text,text,text,bigint) to authenticated;
revoke all on function public.set_primary_financial_transaction_document_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.set_primary_financial_transaction_document_v1(uuid,uuid,uuid) to authenticated;
revoke all on function public.delete_financial_transaction_document_v1(uuid,uuid,uuid) from public,anon;
grant execute on function public.delete_financial_transaction_document_v1(uuid,uuid,uuid) to authenticated;
