BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
WITH targets AS (
 SELECT p.* FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname = ANY(ARRAY['audit_capture_row_v1','emit_domain_event','has_club_access','inventory_count_finalize_v1','inventory_variant_balance_sync_v1','member_status_timeline_trigger_v1','retry_financial_ocr_job_v1','save_financial_ocr_review_v1','alerts_v1','dashboard_summary_v1','member_milestones','handle_new_user','protect_profile_privileges','has_club_role','is_administrator','is_finance_manager'])
)
SELECT jsonb_build_object(
 'captured_at',current_timestamp,'database',current_database(),'server_version',current_setting('server_version'),
 'functions',(SELECT jsonb_agg(jsonb_build_object(
 'name',p.proname,'signature',p.oid::regprocedure::text,'arguments',pg_get_function_arguments(p.oid),
 'identity_arguments',pg_get_function_identity_arguments(p.oid),'result',pg_get_function_result(p.oid),
 'definition',pg_get_functiondef(p.oid),'body_md5',md5(p.prosrc),
 'owner',pg_get_userbyid(p.proowner),'language',(SELECT lanname FROM pg_language WHERE oid=p.prolang),
 'security_definer',p.prosecdef,'volatility',p.provolatile,'strict',p.proisstrict,'parallel',p.proparallel,
 'config',p.proconfig,'acl',p.proacl::text,
 'acl_expanded',(SELECT jsonb_agg(jsonb_build_object('grantor',pg_get_userbyid(a.grantor),'grantee',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,'privilege',a.privilege_type,'grantable',a.is_grantable)) FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a),
 'effective_execute',(SELECT jsonb_object_agg(r.rolname,has_function_privilege(r.oid,p.oid,'EXECUTE')) FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role')),
 'triggers',(SELECT jsonb_agg(jsonb_build_object('relation',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid,true))) FROM pg_trigger t WHERE t.tgfoid=p.oid AND NOT t.tgisinternal),
 'incoming_dependencies',(SELECT jsonb_agg(jsonb_build_object('object',pg_describe_object(d.classid,d.objid,d.objsubid),'type',d.deptype)) FROM pg_depend d WHERE d.refclassid='pg_proc'::regclass AND d.refobjid=p.oid),
 'outgoing_dependencies',(SELECT jsonb_agg(jsonb_build_object('object',pg_describe_object(d.refclassid,d.refobjid,d.refobjsubid),'type',d.deptype)) FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid)
 ) ORDER BY p.proname,p.oid) FROM targets p),
 'function_text_references',(SELECT jsonb_agg(jsonb_build_object('target',t.proname,'caller',p.oid::regprocedure::text)) FROM targets t JOIN pg_proc p ON p.oid<>t.oid AND p.prosrc ~ ('\m'||t.proname||'\M') JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','bob_fees_private')),
 'policy_text_references',(SELECT jsonb_agg(jsonb_build_object('target',t.proname,'schema',pol.schemaname,'table',pol.tablename,'policy',pol.policyname,'roles',pol.roles,'command',pol.cmd,'using',pol.qual,'check',pol.with_check)) FROM targets t JOIN pg_policies pol ON coalesce(pol.qual,'')||' '||coalesce(pol.with_check,'') ~ ('\m'||t.proname||'\M')),
 'view_text_references',(SELECT jsonb_agg(jsonb_build_object('target',t.proname,'schema',v.schemaname,'view',v.viewname,'definition',v.definition)) FROM targets t JOIN pg_views v ON v.definition ~ ('\m'||t.proname||'\M') WHERE v.schemaname NOT IN ('pg_catalog','information_schema')),
 'columns',(SELECT jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'column',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid),'identity',a.attidentity,'generated',a.attgenerated,'collation',a.attcollation::regcollation::text)) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid LEFT JOIN pg_attrdef ad ON ad.adrelid=c.oid AND ad.adnum=a.attnum WHERE n.nspname='public' AND ((c.relname='clubs' AND a.attname='slug') OR(c.relname='profiles' AND a.attname='email')) AND NOT a.attisdropped),
 'table_constraints',(SELECT jsonb_agg(jsonb_build_object('relation',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid,true),'validated',c.convalidated)) FROM pg_constraint c WHERE c.conrelid IN ('public.clubs'::regclass,'public.profiles'::regclass) OR c.confrelid IN ('public.clubs'::regclass,'public.profiles'::regclass)),
 'table_indexes',(SELECT jsonb_agg(to_jsonb(i)) FROM pg_indexes i WHERE i.schemaname='public' AND i.tablename IN ('clubs','profiles')),
 'table_triggers',(SELECT jsonb_agg(jsonb_build_object('relation',t.tgrelid::regclass::text,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid,true))) FROM pg_trigger t WHERE t.tgrelid IN ('public.clubs'::regclass,'public.profiles'::regclass,'auth.users'::regclass) AND NOT t.tgisinternal),
 'default_function_acls',(SELECT jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),'schema',n.nspname,'acl',d.defaclacl::text)) FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace WHERE d.defaclobjtype='f'),
 'data_preflight',jsonb_build_object(
 'clubs',(SELECT jsonb_build_object('rows',count(*),'null_slug',count(*) FILTER(WHERE slug IS NULL),'blank_slug',count(*) FILTER(WHERE btrim(slug)='')) FROM public.clubs),
 'profiles',(SELECT jsonb_build_object('rows',count(*),'null_email',count(*) FILTER(WHERE email IS NULL),'blank_email',count(*) FILTER(WHERE btrim(email::text)='')) FROM public.profiles)),
 'migrations',(SELECT jsonb_agg(jsonb_build_object('version',version,'name',name) ORDER BY version) FROM supabase_migrations.schema_migrations)
) AS snapshot;
ROLLBACK;
