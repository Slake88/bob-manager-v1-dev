-- Prepared only. Do not execute in production from this Work thread.
-- Run as the intended migration owner in a later authorized read-only session.
-- This is evidence, not a rollout command. Missing relations/permissions abort safely.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';
SELECT current_database() AS database, current_user AS inspected_as,
       current_setting('server_version') AS server_version,
       current_setting('transaction_read_only') AS read_only;

-- identity_nullability: both counts must be zero. bootstrap requires text, not citext.
SELECT 'identity_data' AS check_name,
 (SELECT count(*) FROM public.clubs WHERE slug IS NULL) AS null_slugs,
 (SELECT count(*) FROM public.profiles WHERE email IS NULL) AS null_emails,
 (SELECT count(*) FROM auth.users WHERE email IS NULL) AS auth_null_emails,
 (SELECT count(*) FROM (SELECT slug FROM public.clubs WHERE slug IS NOT NULL GROUP BY slug HAVING count(*)>1) d) AS duplicate_slug_groups;
SELECT c.relname,a.attname,format_type(a.atttypid,a.atttypmod) AS type,
 a.attnotnull,pg_get_expr(d.adbin,d.adrelid) AS default_expression
FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
WHERE NOT a.attisdropped AND
 ((c.oid='public.clubs'::regclass AND a.attname='slug') OR
  (c.oid='public.profiles'::regclass AND a.attname='email'));

-- Required predecessor tables/columns. Compare to the candidate source, not 1000.
SELECT c.oid::regclass AS relation,a.attname,format_type(a.atttypid,a.atttypmod) AS type,a.attnotnull
FROM pg_class c JOIN pg_attribute a ON a.attrelid=c.oid
WHERE c.oid=ANY(ARRAY['public.club_memberships'::regclass,'public.member_status_history'::regclass,
 'public.member_timeline'::regclass,'public.members'::regclass,'auth.users'::regclass])
 AND a.attnum>0 AND NOT a.attisdropped ORDER BY 1, a.attnum;

-- Exact function guard values; absent bootstrap functions are allowed, absent access/timeline are not.
WITH expected(signature,allowed_body_md5,allow_absent) AS (VALUES
 ('public.has_club_access(uuid)',ARRAY['b36b6374042a632a65d79f86cf867841','d839b5b8aa6ba45da20d571e0163aa02'],false),
 ('public.handle_new_user()',ARRAY['d09d2d62677178915cf6911a86adb79a'],true),
 ('public.has_club_role(uuid,text[])',ARRAY['d20dbc0bc410cd7afe5b584d9311dfba'],true),
 ('public.member_status_timeline_trigger_v1()',ARRAY['1361d8eefedcad67a06b719926ff1c0d','36d5a88b9579cc8b7f40567b4ef244bf'],false)
)
SELECT e.signature,p.oid,p.oid IS NOT NULL AS present,e.allow_absent,
 md5(replace(p.prosrc,E'\r\n',E'\n')) AS body_md5,
 CASE WHEN p.oid IS NULL THEN e.allow_absent ELSE md5(replace(p.prosrc,E'\r\n',E'\n'))=ANY(e.allowed_body_md5) END AS body_guard_pass,
 pg_get_function_arguments(p.oid) AS arguments,pg_get_function_result(p.oid) AS result,
 l.lanname,pg_get_userbyid(p.proowner) AS owner,p.prosecdef,p.provolatile,p.proisstrict,p.proparallel,p.proretset,p.proconfig,
 p.proacl::text AS acl,pg_get_functiondef(p.oid) AS definition,
 (SELECT jsonb_object_agg(r.rolname,has_function_privilege(r.oid,p.oid,'execute')) FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role')) AS effective_execute
FROM expected e LEFT JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
LEFT JOIN pg_language l ON l.oid=p.prolang;
-- Check every header above against the corresponding guard in the candidate SQL.
-- Existing bootstrap ACLs are preserved, not repaired; unexpected grants need separate review.

SELECT t.oid,t.tgname,t.tgfoid::regprocedure AS function,t.tgtype,t.tgenabled,t.tgnargs,
 pg_get_expr(t.tgqual,t.tgrelid) AS qualification,pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t WHERE t.tgrelid='auth.users'::regclass AND NOT t.tgisinternal;
-- on_auth_user_created, if present: expected handle_new_user(), tgtype=5, O, no qualification, 0 args.
-- Review other Auth INSERT triggers as well: naming alone does not prove compatibility.

-- slug_uniqueness: compare exact definitions to source; unknown namesakes must abort.
SELECT c.conname,c.contype,c.convalidated,c.condeferrable,pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c WHERE c.conrelid='public.clubs'::regclass;
SELECT c.oid::regclass AS object,c.relkind,pg_get_indexdef(i.indexrelid) AS definition,i.indisvalid,i.indisready
FROM pg_class c LEFT JOIN pg_index i ON i.indexrelid=c.oid
WHERE c.oid IN (to_regclass('public.clubs_slug_key'),to_regclass('public.clubs_slug_unique_idx'));

-- active_bootstrap location FKs: every orphan count must be zero; no automatic cleanup.
SELECT 'stock_movements.from_location_id' AS target,count(*) AS orphans FROM public.stock_movements s
 WHERE s.from_location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_locations l WHERE l.id=s.from_location_id)
UNION ALL SELECT 'stock_movements.to_location_id',count(*) FROM public.stock_movements s
 WHERE s.to_location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_locations l WHERE l.id=s.to_location_id)
UNION ALL SELECT 'stock_lots.location_id',count(*) FROM public.stock_lots s
 WHERE s.location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_locations l WHERE l.id=s.location_id)
UNION ALL SELECT 'stock_reservations.location_id',count(*) FROM public.stock_reservations s
 WHERE s.location_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.inventory_locations l WHERE l.id=s.location_id);
SELECT c.conrelid::regclass AS relation,c.conname,c.contype,c.confrelid::regclass AS referenced_relation,
 c.conkey,c.confkey,c.confdeltype,c.confupdtype,c.convalidated,c.condeferrable,pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c WHERE c.conrelid IN ('public.stock_movements'::regclass,'public.stock_lots'::regclass,'public.stock_reservations'::regclass);

-- Dependency and ACL evidence; no business RPC is called.
SELECT to_regprocedure('public.member_timeline_append_v1(uuid,uuid,text,text,text,date,text,text,uuid)') AS timeline_append;
SELECT pg_get_userbyid(defaclrole) AS owner,defaclnamespace::regnamespace AS schema,defaclacl::text AS default_acl
FROM pg_default_acl WHERE defaclobjtype='f';
SELECT pid,mode,granted,relation::regclass FROM pg_locks
WHERE relation IN ('public.clubs'::regclass,'public.profiles'::regclass,'auth.users'::regclass,
 'public.stock_movements'::regclass,'public.stock_lots'::regclass,'public.stock_reservations'::regclass);
-- Lock state is momentary; candidate lock/statement timeouts can still abort later.
ROLLBACK;
