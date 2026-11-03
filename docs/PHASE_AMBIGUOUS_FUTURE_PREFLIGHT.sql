-- Future authorized read-only preflight. NOT executed against production.
-- Catalog dependencies are incomplete for dynamic SQL, string PL/pgSQL and external clients.
begin transaction read only;
select p.oid::regprocedure as signature, p.prosecdef, p.proconfig, p.proacl,
       pg_get_functiondef(p.oid) as definition
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('alerts_v1','dashboard_summary_v1','member_milestones','protect_profile_privileges',
  'is_administrator','is_finance_manager','has_permission');
select p.oid::regprocedure as referenced_function,
       pg_describe_object(d.classid,d.objid,d.objsubid) as dependent, d.deptype
from pg_depend d join pg_proc p on d.refclassid='pg_proc'::regclass and d.refobjid=p.oid
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('alerts_v1','dashboard_summary_v1','member_milestones','protect_profile_privileges',
  'is_administrator','is_finance_manager','has_permission');
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
where schemaname='public' and tablename in ('club_memberships','clubs','document_links','document_versions','euromillions_draws');
select p.oid::regprocedure, pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.prokind in ('f','p')
and p.prosrc ~ '(alerts_v1|dashboard_summary_v1|member_milestones|protect_profile_privileges|is_administrator|is_finance_manager|has_permission)';
select table_name,column_name,data_type,udt_name,is_nullable,column_default
from information_schema.columns where table_schema='public'
and table_name in ('members','profiles','club_memberships','events','fee_obligations','reported_payments','product_variants','audit_log')
order by table_name,ordinal_position;
select extname,extversion from pg_extension order by extname;
-- Historical mapping only; body hashes require statements/exports when available.
select version,name from supabase_migrations.schema_migrations order by version;
rollback;
-- Separately, with owner authorization: API gateway/RPC logs and deployed client inventory;
-- pg_stat_statements only if installed/accessible; cron.job and Storage/Auth service health.
-- Before adding each UNIQUE/FK: scoped duplicate/orphan/null queries for the exact candidate,
-- avoiding unbounded whole-table scans until reviewed against volume and query plans.
