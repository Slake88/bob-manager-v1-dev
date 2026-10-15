-- Mirror both captured production uniqueness objects, including the redundant partial index.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.clubs in access exclusive mode;
do $preflight$ declare k pg_constraint%rowtype; i text; begin
 if exists(select 1 from public.clubs group by slug having count(*)>1 and slug is not null) then
  raise exception 'Duplicate club slugs; no automatic cleanup' using errcode='23505';
 end if;
 select * into k from pg_constraint where conrelid='public.clubs'::regclass and conname='clubs_slug_key';
 if found then
  if k.contype<>'u' or not k.convalidated or k.condeferrable
    or pg_get_constraintdef(k.oid)<>'UNIQUE (slug)' then
   raise exception 'Unreviewed clubs_slug_key contract' using errcode='55000';
  end if;
 else
  if to_regclass('public.clubs_slug_key') is not null then
   raise exception 'Unreviewed index occupies clubs_slug_key' using errcode='55000';
  end if;
  alter table public.clubs add constraint clubs_slug_key unique(slug);
 end if;
 if to_regclass('public.clubs_slug_unique_idx') is not null then
  select pg_get_indexdef(indexrelid) into i from pg_index
   where indexrelid=to_regclass('public.clubs_slug_unique_idx') and indisvalid and indisready;
  if i is distinct from 'CREATE UNIQUE INDEX clubs_slug_unique_idx ON public.clubs USING btree (slug) WHERE (slug IS NOT NULL)' then
   raise exception 'Unreviewed clubs_slug_unique_idx contract' using errcode='55000';
  end if;
 else
  create unique index clubs_slug_unique_idx on public.clubs using btree(slug) where slug is not null;
 end if;
end $preflight$;
commit;
