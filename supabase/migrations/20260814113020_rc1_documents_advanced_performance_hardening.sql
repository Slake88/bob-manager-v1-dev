create index if not exists annual_books_cover_document_idx on public.annual_books(cover_document_id) where cover_document_id is not null;
create index if not exists document_ocr_version_idx on public.document_ocr(version_id) where version_id is not null;
create index if not exists document_access_log_version_idx on public.document_access_log(version_id) where version_id is not null;
