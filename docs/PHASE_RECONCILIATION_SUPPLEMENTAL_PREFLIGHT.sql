BEGIN TRANSACTION READ ONLY;
SELECT jsonb_build_object(
 'membership_active',(SELECT jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE a.attrelid='public.club_memberships'::regclass AND a.attname='active'),
 'membership_null_active',(SELECT count(*) FROM public.club_memberships WHERE active IS NULL),
 'profile_role',(SELECT jsonb_build_object('type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) FROM pg_attribute a WHERE a.attrelid='public.profiles'::regclass AND a.attname='role'),
 'legacy_text_callers',(SELECT jsonb_agg(jsonb_build_object('schema',n.nspname,'signature',p.oid::regprocedure::text,'name',p.proname)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.prosrc ~ '\m(is_administrator|is_finance_manager|protect_profile_privileges|handle_new_user)\M' AND p.proname NOT IN ('is_administrator','is_finance_manager','protect_profile_privileges','handle_new_user') AND n.nspname NOT IN ('pg_catalog','information_schema')),
 'legacy_views',(SELECT jsonb_agg(to_jsonb(v)) FROM pg_views v WHERE v.definition ~ '\m(is_administrator|is_finance_manager|protect_profile_privileges)\M')
) AS supplemental;
ROLLBACK;
