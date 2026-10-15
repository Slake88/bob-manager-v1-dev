begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Capture the confirmed production NOT NULL rules, without inventing values.
-- profiles.email type reconciliation (citext vs text) is deliberately separate.
lock table public.clubs, public.profiles in access exclusive mode;
do $preflight$
begin
  if not exists (
    select 1 from pg_attribute a join pg_type t on t.oid=a.atttypid
    where a.attrelid='public.clubs'::regclass and a.attname='slug'
      and not a.attisdropped and t.typname='text'
  ) or not exists (
    select 1 from pg_attribute a join pg_type t on t.oid=a.atttypid
    where a.attrelid='public.profiles'::regclass and a.attname='email'
      and not a.attisdropped and t.typname in ('text','citext')
  ) then
    raise exception 'Unexpected identity column contract.' using errcode='42804';
  end if;
  if exists (select 1 from public.clubs where slug is null)
    or exists (select 1 from public.profiles where email is null) then
    raise exception 'Identity reconciliation requires zero NULL values; no backfill is authorized.'
      using errcode='23502';
  end if;
end
$preflight$;

alter table public.clubs alter column slug set not null;
alter table public.profiles alter column email set not null;
commit;
