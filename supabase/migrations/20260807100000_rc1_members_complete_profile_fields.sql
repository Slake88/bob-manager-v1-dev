alter table public.members add column if not exists primary_role text;
alter table public.members add column if not exists additional_roles text;
alter table public.members add column if not exists postal_code text;
alter table public.members add column if not exists locality text;
