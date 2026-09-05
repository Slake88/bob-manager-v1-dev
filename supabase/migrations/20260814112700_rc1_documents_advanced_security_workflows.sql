do $$ begin
  if not exists (select 1 from pg_constraint where conname='documents_personal_owner_check') then
    alter table public.documents add constraint documents_personal_owner_check check (scope <> 'personal' or owner_profile_id is not null);
  end if;
  if not exists (select 1 from pg_constraint where conname='documents_gallery_event_check') then
    alter table public.documents add constraint documents_gallery_event_check check (scope <> 'event_gallery' or event_id is not null);
  end if;
end $$;

create or replace function public.can_edit_document_v1(p_document uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1 from public.documents d
    where d.id=p_document
      and (
        (d.scope='personal' and (d.owner_profile_id=(select auth.uid()) or public.has_club_permission(d.club_id,'manageDocuments')))
        or (d.scope='event_gallery' and (public.has_club_permission(d.club_id,'manageEventGallery') or public.has_club_permission(d.club_id,'manageDocuments')))
        or (d.scope not in ('personal','event_gallery') and public.has_club_permission(d.club_id,'manageDocuments'))
      )
  );
$$;
revoke all on function public.can_edit_document_v1(uuid) from public,anon;
grant execute on function public.can_edit_document_v1(uuid) to authenticated;

create or replace function public.personal_document_usage_bytes_v1(target_club uuid)
returns bigint
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(sum(v.file_size),0)::bigint
  from public.document_versions v
  join public.documents d on d.id=v.document_id
  where d.club_id=target_club
    and d.scope='personal'
    and d.owner_profile_id=(select auth.uid());
$$;
revoke all on function public.personal_document_usage_bytes_v1(uuid) from public,anon;
grant execute on function public.personal_document_usage_bytes_v1(uuid) to authenticated;

create or replace function public.enforce_personal_document_quota_v1()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_scope text;
  v_owner uuid;
  v_used bigint;
  v_limit constant bigint := 524288000;
begin
  select d.scope,d.owner_profile_id into v_scope,v_owner
  from public.documents d where d.id=new.document_id;
  if v_scope <> 'personal' then return new; end if;
  if v_owner is null then raise exception 'Documento pessoal sem proprietário.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_owner::text,0));
  select coalesce(sum(v.file_size),0)::bigint into v_used
  from public.document_versions v
  join public.documents d on d.id=v.document_id
  where d.scope='personal' and d.owner_profile_id=v_owner;
  if v_used + coalesce(new.file_size,0) > v_limit then
    raise exception 'Limite pessoal de 500 MB excedido.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_personal_document_quota on public.document_versions;
create trigger trg_personal_document_quota before insert on public.document_versions
for each row execute function public.enforce_personal_document_quota_v1();

drop policy if exists documents_select on public.documents;
drop policy if exists documents_insert on public.documents;
drop policy if exists documents_update on public.documents;
drop policy if exists documents_delete on public.documents;

create policy documents_select on public.documents for select to authenticated using (
  public.has_club_access(club_id) and (
    (scope='personal' and (owner_profile_id=(select auth.uid()) or public.has_club_permission(club_id,'manageDocuments')))
    or (scope='leadership' and public.has_club_permission(club_id,'viewSensitiveDocuments'))
    or (scope in ('club','event_gallery','annual_book') and public.has_club_permission(club_id,'viewDocuments') and (sensitive=false or public.has_club_permission(club_id,'viewSensitiveDocuments')))
  )
);

create policy documents_insert on public.documents for insert to authenticated with check (
  created_by=(select auth.uid()) and public.has_club_access(club_id) and (
    (scope='personal' and owner_profile_id=(select auth.uid()))
    or (scope='event_gallery' and (public.has_club_permission(club_id,'manageEventGallery') or public.has_club_permission(club_id,'manageDocuments')))
    or (scope not in ('personal','event_gallery') and public.has_club_permission(club_id,'manageDocuments'))
  )
);

create policy documents_update on public.documents for update to authenticated using (
  (scope='personal' and (owner_profile_id=(select auth.uid()) or public.has_club_permission(club_id,'manageDocuments')))
  or (scope='event_gallery' and (public.has_club_permission(club_id,'manageEventGallery') or public.has_club_permission(club_id,'manageDocuments')))
  or (scope not in ('personal','event_gallery') and public.has_club_permission(club_id,'manageDocuments'))
) with check (
  public.has_club_access(club_id) and (
    (scope='personal' and (owner_profile_id=(select auth.uid()) or public.has_club_permission(club_id,'manageDocuments')))
    or (scope='event_gallery' and (public.has_club_permission(club_id,'manageEventGallery') or public.has_club_permission(club_id,'manageDocuments')))
    or (scope not in ('personal','event_gallery') and public.has_club_permission(club_id,'manageDocuments'))
  )
);

create policy documents_delete on public.documents for delete to authenticated using (
  (scope='personal' and (owner_profile_id=(select auth.uid()) or public.has_club_permission(club_id,'manageDocuments')))
  or (scope='event_gallery' and (public.has_club_permission(club_id,'manageEventGallery') or public.has_club_permission(club_id,'manageDocuments')))
  or (scope not in ('personal','event_gallery') and public.has_club_permission(club_id,'manageDocuments'))
);

create policy document_versions_select on public.document_versions for select to authenticated using (
  exists(select 1 from public.documents d where d.id=document_id)
);
create policy document_versions_insert on public.document_versions for insert to authenticated with check (
  club_id=(select d.club_id from public.documents d where d.id=document_id) and public.can_edit_document_v1(document_id) and created_by=(select auth.uid())
);
create policy document_versions_update on public.document_versions for update to authenticated using (public.can_edit_document_v1(document_id)) with check (public.can_edit_document_v1(document_id));
create policy document_versions_delete on public.document_versions for delete to authenticated using (public.can_edit_document_v1(document_id));

create policy document_links_select on public.document_links for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy document_links_insert on public.document_links for insert to authenticated with check (public.can_edit_document_v1(document_id));
create policy document_links_update on public.document_links for update to authenticated using (public.can_edit_document_v1(document_id)) with check (public.can_edit_document_v1(document_id));
create policy document_links_delete on public.document_links for delete to authenticated using (public.can_edit_document_v1(document_id));

create policy document_approvals_select on public.document_approvals for select to authenticated using (
  exists(select 1 from public.documents d where d.id=document_id)
  or public.has_club_permission(club_id,'approveDocuments')
);
create policy document_approvals_insert on public.document_approvals for insert to authenticated with check (public.can_edit_document_v1(document_id) and requested_by=(select auth.uid()));
create policy document_approvals_update on public.document_approvals for update to authenticated using (
  public.has_club_permission(club_id,'approveDocuments') or requested_by=(select auth.uid())
) with check (public.has_club_access(club_id));
create policy document_approvals_delete on public.document_approvals for delete to authenticated using (status='pending' and requested_by=(select auth.uid()));

create policy document_ocr_select on public.document_ocr for select to authenticated using (exists(select 1 from public.documents d where d.id=document_id));
create policy document_ocr_insert on public.document_ocr for insert to authenticated with check (
  public.has_club_permission(club_id,'runDocumentOcr') and created_by=(select auth.uid()) and exists(select 1 from public.documents d where d.id=document_id)
);
create policy document_ocr_update on public.document_ocr for update to authenticated using (public.has_club_permission(club_id,'runDocumentOcr')) with check (public.has_club_permission(club_id,'runDocumentOcr'));
create policy document_ocr_delete on public.document_ocr for delete to authenticated using (public.has_club_permission(club_id,'runDocumentOcr'));

create policy document_access_log_select on public.document_access_log for select to authenticated using (
  public.has_club_permission(club_id,'manageDocuments') or profile_id=(select auth.uid())
);
create policy document_access_log_insert on public.document_access_log for insert to authenticated with check (
  profile_id=(select auth.uid()) and exists(select 1 from public.documents d where d.id=document_id)
);

create policy annual_books_select on public.annual_books for select to authenticated using (public.has_club_permission(club_id,'viewDocuments'));
create policy annual_books_insert on public.annual_books for insert to authenticated with check (public.has_club_permission(club_id,'manageAnnualBooks') and created_by=(select auth.uid()));
create policy annual_books_update on public.annual_books for update to authenticated using (public.has_club_permission(club_id,'manageAnnualBooks')) with check (public.has_club_permission(club_id,'manageAnnualBooks'));
create policy annual_books_delete on public.annual_books for delete to authenticated using (public.has_club_permission(club_id,'manageAnnualBooks'));

create policy annual_book_items_select on public.annual_book_items for select to authenticated using (exists(select 1 from public.annual_books b where b.id=annual_book_id));
create policy annual_book_items_insert on public.annual_book_items for insert to authenticated with check (public.has_club_permission(club_id,'manageAnnualBooks'));
create policy annual_book_items_update on public.annual_book_items for update to authenticated using (public.has_club_permission(club_id,'manageAnnualBooks')) with check (public.has_club_permission(club_id,'manageAnnualBooks'));
create policy annual_book_items_delete on public.annual_book_items for delete to authenticated using (public.has_club_permission(club_id,'manageAnnualBooks'));

create or replace function public.bootstrap_document_version_v1()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
declare v_id uuid;
begin
  if new.storage_path is null or new.storage_path='' then return new; end if;
  insert into public.document_versions(club_id,document_id,version_no,version_label,storage_path,original_file_name,mime_type,file_size,created_by)
  values(new.club_id,new.id,1,coalesce(nullif(new.version,''),'1.0'),new.storage_path,new.original_file_name,new.mime_type,coalesce(new.file_size,0),coalesce(new.created_by,(select auth.uid())))
  returning id into v_id;
  update public.documents set current_version_id=v_id,version=coalesce(nullif(new.version,''),'1.0') where id=new.id;
  return new;
end;
$$;
drop trigger if exists trg_bootstrap_document_version on public.documents;
create trigger trg_bootstrap_document_version after insert on public.documents
for each row execute function public.bootstrap_document_version_v1();

create or replace function public.register_document_version_v1(
  p_document uuid,p_storage_path text,p_original_file_name text,p_mime_type text,p_file_size bigint,p_change_notes text default null
) returns uuid
language plpgsql
security invoker
set search_path=public
as $$
declare v_doc public.documents%rowtype; v_no integer; v_id uuid; v_label text;
begin
  select * into v_doc from public.documents where id=p_document for update;
  if not found or not public.can_edit_document_v1(p_document) then raise exception 'Documento não acessível para edição.'; end if;
  if coalesce(p_storage_path,'')='' or coalesce(p_file_size,0)<0 then raise exception 'Versão inválida.'; end if;
  select coalesce(max(version_no),0)+1 into v_no from public.document_versions where document_id=p_document;
  v_label:=v_no::text||'.0';
  update public.document_versions set is_current=false where document_id=p_document and is_current=true;
  insert into public.document_versions(club_id,document_id,version_no,version_label,storage_path,original_file_name,mime_type,file_size,change_notes,is_current,created_by)
  values(v_doc.club_id,p_document,v_no,v_label,p_storage_path,p_original_file_name,p_mime_type,coalesce(p_file_size,0),p_change_notes,true,(select auth.uid()))
  returning id into v_id;
  update public.documents set current_version_id=v_id,storage_path=p_storage_path,original_file_name=p_original_file_name,mime_type=p_mime_type,file_size=coalesce(p_file_size,0),version=v_label,updated_at=now(),updated_by=(select auth.uid()) where id=p_document;
  return v_id;
end;
$$;
revoke all on function public.register_document_version_v1(uuid,text,text,text,bigint,text) from public,anon;
grant execute on function public.register_document_version_v1(uuid,text,text,text,bigint,text) to authenticated;

create or replace function public.request_document_approval_v1(p_document uuid,p_notes text default null)
returns uuid language plpgsql security invoker set search_path=public as $$
declare v_doc public.documents%rowtype; v_id uuid;
begin
  select * into v_doc from public.documents where id=p_document for update;
  if not found or not public.can_edit_document_v1(p_document) then raise exception 'Documento não acessível para aprovação.'; end if;
  select id into v_id from public.document_approvals where document_id=p_document and status='pending' limit 1;
  if v_id is not null then return v_id; end if;
  insert into public.document_approvals(club_id,document_id,status,requested_by,notes) values(v_doc.club_id,p_document,'pending',(select auth.uid()),p_notes) returning id into v_id;
  update public.documents set requires_approval=true,approval_status='pending',updated_at=now(),updated_by=(select auth.uid()) where id=p_document;
  return v_id;
end; $$;
revoke all on function public.request_document_approval_v1(uuid,text) from public,anon;
grant execute on function public.request_document_approval_v1(uuid,text) to authenticated;

create or replace function public.decide_document_approval_v1(p_approval uuid,p_approve boolean,p_notes text default null)
returns void language plpgsql security invoker set search_path=public as $$
declare v_row public.document_approvals%rowtype; v_status text;
begin
  select * into v_row from public.document_approvals where id=p_approval for update;
  if not found or v_row.status<>'pending' then raise exception 'Aprovação não está pendente.'; end if;
  if not public.has_club_permission(v_row.club_id,'approveDocuments') then raise exception 'Sem permissão para decidir aprovações.'; end if;
  v_status:=case when p_approve then 'approved' else 'rejected' end;
  update public.document_approvals set status=v_status,decided_by=(select auth.uid()),decided_at=now(),notes=coalesce(p_notes,notes),updated_at=now() where id=p_approval;
  update public.documents set approval_status=v_status,updated_at=now(),updated_by=(select auth.uid()) where id=v_row.document_id;
end; $$;
revoke all on function public.decide_document_approval_v1(uuid,boolean,text) from public,anon;
grant execute on function public.decide_document_approval_v1(uuid,boolean,text) to authenticated;

create or replace function public.start_document_ocr_v1(p_document uuid)
returns uuid language plpgsql security invoker set search_path=public as $$
declare v_doc public.documents%rowtype; v_id uuid;
begin
  select * into v_doc from public.documents where id=p_document;
  if not found then raise exception 'Documento não acessível.'; end if;
  if not public.has_club_permission(v_doc.club_id,'runDocumentOcr') then raise exception 'Sem permissão para executar OCR.'; end if;
  if v_doc.current_version_id is null then raise exception 'Documento sem versão para OCR.'; end if;
  insert into public.document_ocr(club_id,document_id,version_id,status,provider,model,created_by)
  values(v_doc.club_id,p_document,v_doc.current_version_id,'pending','google_cloud_vision','DOCUMENT_TEXT_DETECTION',(select auth.uid())) returning id into v_id;
  update public.documents set ocr_status='pending',updated_at=now(),updated_by=(select auth.uid()) where id=p_document;
  return v_id;
end; $$;
revoke all on function public.start_document_ocr_v1(uuid) from public,anon;
grant execute on function public.start_document_ocr_v1(uuid) to authenticated;

drop policy if exists club_documents_select on storage.objects;
drop policy if exists club_documents_insert on storage.objects;
drop policy if exists club_documents_update on storage.objects;
drop policy if exists club_documents_delete on storage.objects;

create policy club_documents_select on storage.objects for select to authenticated using (
  bucket_id='club-documents' and (
    exists(select 1 from public.documents d where d.storage_path=storage.objects.name)
    or exists(select 1 from public.document_versions v where v.storage_path=storage.objects.name)
  )
);

create policy club_documents_insert on storage.objects for insert to authenticated with check (
  bucket_id='club-documents' and (
    public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageDocuments')
    or (coalesce((storage.foldername(name))[2],'')='personal' and coalesce((storage.foldername(name))[3],'')=(select auth.uid())::text and public.has_club_access(((storage.foldername(name))[1])::uuid))
    or (coalesce((storage.foldername(name))[2],'')='gallery' and public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageEventGallery'))
  )
);

create policy club_documents_update on storage.objects for update to authenticated using (
  bucket_id='club-documents' and (
    public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageDocuments')
    or (coalesce((storage.foldername(name))[2],'')='personal' and coalesce((storage.foldername(name))[3],'')=(select auth.uid())::text and public.has_club_access(((storage.foldername(name))[1])::uuid))
    or (coalesce((storage.foldername(name))[2],'')='gallery' and public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageEventGallery'))
  )
) with check (
  bucket_id='club-documents' and (
    public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageDocuments')
    or (coalesce((storage.foldername(name))[2],'')='personal' and coalesce((storage.foldername(name))[3],'')=(select auth.uid())::text and public.has_club_access(((storage.foldername(name))[1])::uuid))
    or (coalesce((storage.foldername(name))[2],'')='gallery' and public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageEventGallery'))
  )
);

create policy club_documents_delete on storage.objects for delete to authenticated using (
  bucket_id='club-documents' and (
    public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageDocuments')
    or (coalesce((storage.foldername(name))[2],'')='personal' and coalesce((storage.foldername(name))[3],'')=(select auth.uid())::text and public.has_club_access(((storage.foldername(name))[1])::uuid))
    or (coalesce((storage.foldername(name))[2],'')='gallery' and public.has_club_permission(((storage.foldername(name))[1])::uuid,'manageEventGallery'))
  )
);
