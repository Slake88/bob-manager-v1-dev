alter table public.bar_sale_items
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

alter table public.bar_sale_attachments
  add column if not exists updated_by uuid references public.profiles(id) on delete set null;

update public.bar_sale_items i
set created_by = coalesce(i.created_by, s.created_by),
    updated_by = coalesce(i.updated_by, s.completed_by, s.updated_by, s.created_by),
    updated_at = coalesce(i.updated_at, i.created_at, s.completed_at, s.updated_at, s.created_at, now())
from public.bar_sales s
where s.id = i.sale_id
  and (i.created_by is null or i.updated_by is null);

update public.bar_sale_attachments a
set updated_by = coalesce(a.updated_by, a.created_by)
where a.updated_by is null;

drop trigger if exists trg_audit_stamp_v1 on public.bar_sales;
drop trigger if exists trg_audit_capture_v1 on public.bar_sales;
create trigger trg_audit_stamp_v1
before insert or update on public.bar_sales
for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_v1
after insert or update or delete on public.bar_sales
for each row execute function public.audit_capture_row_v1();

drop trigger if exists trg_audit_stamp_v1 on public.bar_sale_items;
drop trigger if exists trg_audit_capture_v1 on public.bar_sale_items;
create trigger trg_audit_stamp_v1
before insert or update on public.bar_sale_items
for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_v1
after insert or update or delete on public.bar_sale_items
for each row execute function public.audit_capture_row_v1();

drop trigger if exists trg_audit_stamp_v1 on public.bar_sale_attachments;
drop trigger if exists trg_audit_capture_v1 on public.bar_sale_attachments;
create trigger trg_audit_stamp_v1
before insert or update on public.bar_sale_attachments
for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_v1
after insert or update or delete on public.bar_sale_attachments
for each row execute function public.audit_capture_row_v1();

drop trigger if exists trg_audit_stamp_v1 on public.bar_sale_presets;
drop trigger if exists trg_audit_capture_v1 on public.bar_sale_presets;
create trigger trg_audit_stamp_v1
before insert or update on public.bar_sale_presets
for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_v1
after insert or update or delete on public.bar_sale_presets
for each row execute function public.audit_capture_row_v1();

drop trigger if exists trg_audit_stamp_v1 on public.bar_product_sale_options;
drop trigger if exists trg_audit_capture_v1 on public.bar_product_sale_options;
create trigger trg_audit_stamp_v1
before insert or update on public.bar_product_sale_options
for each row execute function public.audit_stamp_row_v1();
create trigger trg_audit_capture_v1
after insert or update or delete on public.bar_product_sale_options
for each row execute function public.audit_capture_row_v1();
