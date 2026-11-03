BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
SELECT jsonb_build_object(
 'captured_at',current_timestamp,
 'auth_email_preflight',(SELECT jsonb_build_object('rows',count(*),'null_email',count(*) FILTER(WHERE email IS NULL),'blank_email',count(*) FILTER(WHERE btrim(email)='')) FROM auth.users),
 'slug_duplicates',(SELECT count(*) FROM (SELECT slug FROM public.clubs GROUP BY slug HAVING count(*)>1) d),
 'email_casefold_duplicates',(SELECT count(*) FROM (SELECT lower(email::text) FROM public.profiles GROUP BY lower(email::text) HAVING count(*)>1) d),
 'column_dependents',(SELECT jsonb_agg(jsonb_build_object('column',c.oid::regclass::text||'.'||a.attname,'object',pg_describe_object(d.classid,d.objid,d.objsubid),'dependency',d.deptype)) FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid JOIN pg_depend d ON d.refclassid='pg_class'::regclass AND d.refobjid=c.oid AND d.refobjsubid=a.attnum WHERE (c.oid='public.clubs'::regclass AND a.attname='slug') OR(c.oid='public.profiles'::regclass AND a.attname='email')),
 'target_definitions_in_applied_history',(SELECT jsonb_agg(jsonb_build_object('version',m.version,'name',m.name,'statement_md5',md5(s.statement))) FROM supabase_migrations.schema_migrations m CROSS JOIN LATERAL unnest(m.statements) s(statement) WHERE s.statement ~* 'create[[:space:]]+(or[[:space:]]+replace[[:space:]]+)?function[[:space:]]+(public[.])?(audit_capture_row_v1|emit_domain_event|has_club_access|inventory_count_finalize_v1|inventory_variant_balance_sync_v1|member_status_timeline_trigger_v1|retry_financial_ocr_job_v1|save_financial_ocr_review_v1|alerts_v1|dashboard_summary_v1|member_milestones|handle_new_user|protect_profile_privileges|has_club_role|is_administrator|is_finance_manager)[[:space:]]*[(]')
) AS followup;
ROLLBACK;
