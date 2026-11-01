-- BOB Manager RC1-FINAL consolidated security candidate.
-- Version: RC1-FINAL-CANDIDATE-20261024; derived from the reviewed R18.2 body.
-- Combines the R3-R10 verified proposal with the R12 treasury-export authorization gate.
-- Candidate only: not integrated into source migrations and not clean-install certified.
-- One transaction; run only on a disposable, clean PostgreSQL 17 replay after review.
BEGIN;
-- BOB Manager RC1 consolidated security migration proposal R11
-- PROPOSAL ONLY: never applied to V4 or any database in this task.
-- Sources: validated integrated R1 (R3-R8), R4 anon ACL, R10 finance RLS.
-- Apply as one transaction with session_user=current_user=postgres on a disposable clean replay.
-- This proposal revokes only reviewed elevated ACLs; it does not execute TRUNCATE.
-- Review consumer compatibility for legacy financial_* DML before repository integration.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $r11_pre$
BEGIN
  IF session_user<>'postgres' OR current_user<>'postgres' THEN RAISE EXCEPTION 'R11 requires the verified postgres migration identity'; END IF;
  IF EXISTS(SELECT 1 FROM pg_extension WHERE extname IN ('pg_cron','pg_net')) OR to_regprocedure('public.asset_maintenance_v1()') IS NOT NULL THEN RAISE EXCEPTION 'R11 refuses protected extension/object state'; END IF;
END $r11_pre$;
-- ===== R3-R8 integrated proposal =====
-- PROPOSTA NAO APLICADA. Apenas copia descartavel aprovada.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';

-- 00_precondicoes.sql
DO $audit$
BEGIN
  IF pg_get_functiondef('public.validate_treasury_transaction_v1()'::regprocedure) NOT IN (
    'CREATE OR REPLACE FUNCTION public.validate_treasury_transaction_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''public''
AS $function$
declare
  source_account public.treasury_accounts%rowtype;
  destination_account public.treasury_accounts%rowtype;
  source_balance numeric;
begin
  if new.amount is null or new.amount <= 0 then
    raise exception ''O valor do movimento deve ser superior a zero.'';
  end if;

  select * into source_account
  from public.treasury_accounts
  where id = new.account_id
    and club_id = new.club_id
    and active = true;

  if not found then
    raise exception ''A conta de origem não existe, está inativa ou pertence a outro clube.'';
  end if;

  if new.kind = ''transfer'' then
    if new.destination_account_id is null then
      raise exception ''A transferência exige uma conta de destino.'';
    end if;
    if new.destination_account_id = new.account_id then
      raise exception ''As contas de origem e destino têm de ser diferentes.'';
    end if;

    select * into destination_account
    from public.treasury_accounts
    where id = new.destination_account_id
      and club_id = new.club_id
      and active = true;

    if not found then
      raise exception ''A conta de destino não existe, está inativa ou pertence a outro clube.'';
    end if;
  elsif new.destination_account_id is not null then
    raise exception ''A conta de destino só pode ser usada numa transferência.'';
  end if;

  if new.kind in (''expense'', ''transfer'') and not coalesce(source_account.allows_negative, false) then
    source_balance := public.treasury_account_balance_v1(new.account_id);
    if coalesce(source_balance, 0) < new.amount then
      raise exception ''Saldo insuficiente na conta %.'', source_account.name;
    end if;
  end if;

  return new;
end;
$function$
', 'CREATE OR REPLACE FUNCTION public.validate_treasury_transaction_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''pg_catalog'', ''public'', ''pg_temp''
AS $function$
declare
  source_account public.treasury_accounts%rowtype;
  destination_account public.treasury_accounts%rowtype;
  source_balance numeric;
begin
  -- Snapshot refresh after a blocking lock is part of this READ COMMITTED design.
  -- Reject older snapshots, rather than silently claiming RR/Serializable support.
  if current_setting(''transaction_isolation'') <> ''read committed'' then
    raise exception ''Treasury writes require READ COMMITTED in this proposal.'' using errcode=''0A000'';
  end if;
  -- Both sides: also serialize concurrent incoming transfers and account updates.
  -- The next SELECT in this VOLATILE trigger gets a fresh READ COMMITTED snapshot.
  perform a.id from public.treasury_accounts a
    where a.club_id=new.club_id
      and (a.id=new.account_id or a.id=new.destination_account_id)
    order by a.id for update;

  if new.category_id is not null then
    perform 1 from public.treasury_categories r where r.id=new.category_id and r.club_id=new.club_id for share;
    if not found then raise exception ''Category belongs to another club or is missing.'' using errcode=''22023''; end if;
  end if;
  if new.cost_center_id is not null then
    perform 1 from public.cost_centers r where r.id=new.cost_center_id and r.club_id=new.club_id for share;
    if not found then raise exception ''Cost center belongs to another club or is missing.'' using errcode=''22023''; end if;
  end if;
  if new.event_id is not null then
    perform 1 from public.events r where r.id=new.event_id and r.club_id=new.club_id for share;
    if not found then raise exception ''Event belongs to another club or is missing.'' using errcode=''22023''; end if;
  end if;
  if new.reversal_of is not null then
    perform 1 from public.treasury_transactions r where r.id=new.reversal_of and r.club_id=new.club_id for share;
    if not found then raise exception ''Reversal reference belongs to another club or is missing.'' using errcode=''22023''; end if;
  end if;

  if new.amount is null or new.amount <= 0 then
    raise exception ''O valor do movimento deve ser superior a zero.'';
  end if;

  select * into source_account
  from public.treasury_accounts
  where id = new.account_id
    and club_id = new.club_id
    and active = true;

  if not found then
    raise exception ''A conta de origem não existe, está inativa ou pertence a outro clube.'';
  end if;

  if new.kind = ''transfer'' then
    if new.destination_account_id is null then
      raise exception ''A transferência exige uma conta de destino.'';
    end if;
    if new.destination_account_id = new.account_id then
      raise exception ''As contas de origem e destino têm de ser diferentes.'';
    end if;

    select * into destination_account
    from public.treasury_accounts
    where id = new.destination_account_id
      and club_id = new.club_id
      and active = true;

    if not found then
      raise exception ''A conta de destino não existe, está inativa ou pertence a outro clube.'';
    end if;
  elsif new.destination_account_id is not null then
    raise exception ''A conta de destino só pode ser usada numa transferência.'';
  end if;

  if new.kind in (''expense'', ''transfer'') and not coalesce(source_account.allows_negative, false) then
    source_balance := public.treasury_account_balance_v1(new.account_id);
    if coalesce(source_balance, 0) < new.amount then
      raise exception ''Saldo insuficiente na conta %.'', source_account.name;
    end if;
  end if;

  return new;
end;
$function$
'
  ) AND md5((SELECT prosrc FROM pg_proc WHERE oid='public.validate_treasury_transaction_v1()'::regprocedure))<>'bdb799d58f64a659de375224f158ddc2' THEN RAISE EXCEPTION 'Unreviewed treasury trigger drift'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.treasury_transactions'::regclass
      AND tgname='treasury_transactions_balance_guard' AND tgenabled='O'
      AND tgfoid='public.validate_treasury_transaction_v1()'::regprocedure) THEN
    RAISE EXCEPTION 'Expected balance trigger missing/disabled';
  END IF;
END
$audit$;

-- 01_rls_tesouraria.sql
-- Restrictive AND guard survives other permissive INSERT policies.
-- Keep original createTreasuryMovement/created_by semantics for direct writes.
-- SD RPCs keep their existing, module-specific authorization paths.
DO $audit$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.treasury_transactions'::regclass
      AND polname='rc1_direct_transfer_authorization') THEN
    EXECUTE 'CREATE POLICY rc1_direct_transfer_authorization ON public.treasury_transactions
      AS RESTRICTIVE FOR INSERT TO authenticated
      WITH CHECK (kind <> ''transfer''::public.transaction_kind
        OR public.has_club_permission(club_id,''transferBetweenAccounts''))';
  ELSE
    IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.treasury_transactions'::regclass
        AND polname='rc1_direct_transfer_authorization' AND NOT polpermissive AND polcmd='a') THEN
      RAISE EXCEPTION 'Unexpected policy with reserved audit name';
    END IF;
    EXECUTE 'ALTER POLICY rc1_direct_transfer_authorization ON public.treasury_transactions
      TO authenticated WITH CHECK (kind <> ''transfer''::public.transaction_kind
        OR public.has_club_permission(club_id,''transferBetweenAccounts''))';
  END IF;
END
$audit$;

-- 02_saldo_serializado.sql
CREATE OR REPLACE FUNCTION public.validate_treasury_transaction_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  source_account public.treasury_accounts%rowtype;
  destination_account public.treasury_accounts%rowtype;
  source_balance numeric;
begin
  -- Snapshot refresh after a blocking lock is part of this READ COMMITTED design.
  -- Reject older snapshots, rather than silently claiming RR/Serializable support.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Treasury writes require READ COMMITTED in this proposal.' using errcode='0A000';
  end if;
  -- Both sides: also serialize concurrent incoming transfers and account updates.
  -- The next SELECT in this VOLATILE trigger gets a fresh READ COMMITTED snapshot.
  perform a.id from public.treasury_accounts a
    where a.club_id=new.club_id
      and (a.id=new.account_id or a.id=new.destination_account_id)
    order by a.id for update;

  if new.category_id is not null then
    perform 1 from public.treasury_categories r where r.id=new.category_id and r.club_id=new.club_id for share;
    if not found then raise exception 'Category belongs to another club or is missing.' using errcode='22023'; end if;
  end if;
  if new.cost_center_id is not null then
    perform 1 from public.cost_centers r where r.id=new.cost_center_id and r.club_id=new.club_id for share;
    if not found then raise exception 'Cost center belongs to another club or is missing.' using errcode='22023'; end if;
  end if;
  if new.event_id is not null then
    perform 1 from public.events r where r.id=new.event_id and r.club_id=new.club_id for share;
    if not found then raise exception 'Event belongs to another club or is missing.' using errcode='22023'; end if;
  end if;
  if new.reversal_of is not null then
    perform 1 from public.treasury_transactions r where r.id=new.reversal_of and r.club_id=new.club_id for share;
    if not found then raise exception 'Reversal reference belongs to another club or is missing.' using errcode='22023'; end if;
  end if;

  if new.amount is null or new.amount <= 0 then
    raise exception 'O valor do movimento deve ser superior a zero.';
  end if;

  select * into source_account
  from public.treasury_accounts
  where id = new.account_id
    and club_id = new.club_id
    and active = true;

  if not found then
    raise exception 'A conta de origem não existe, está inativa ou pertence a outro clube.';
  end if;

  if new.kind = 'transfer' then
    if new.destination_account_id is null then
      raise exception 'A transferência exige uma conta de destino.';
    end if;
    if new.destination_account_id = new.account_id then
      raise exception 'As contas de origem e destino têm de ser diferentes.';
    end if;

    select * into destination_account
    from public.treasury_accounts
    where id = new.destination_account_id
      and club_id = new.club_id
      and active = true;

    if not found then
      raise exception 'A conta de destino não existe, está inativa ou pertence a outro clube.';
    end if;
  elsif new.destination_account_id is not null then
    raise exception 'A conta de destino só pode ser usada numa transferência.';
  end if;

  if new.kind in ('expense', 'transfer') and not coalesce(source_account.allows_negative, false) then
    source_balance := public.treasury_account_balance_v1(new.account_id);
    if coalesce(source_balance, 0) < new.amount then
      raise exception 'Saldo insuficiente na conta %.', source_account.name;
    end if;
  end if;

  return new;
end;
$function$;


-- 03_privilegios_e_protecoes.sql
-- No CRUD/sequence USAGE/function EXECUTE blanket revocation.
-- MAINTAIN is a PG17 table privilege, also unnecessary to browser roles.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public
  FROM anon, authenticated;
-- Also remove inherited PUBLIC grants if present.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON ALL TABLES IN SCHEMA public FROM PUBLIC;
-- Observed object creators only; this changes default ACL, not role attributes.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLES FROM anon, authenticated, PUBLIC;
-- R18: supabase_admin default ACL managed by Supabase.
-- R18: No unauthorized ALTER; effective grants require independent audit.

ALTER TABLE public.schema_migrations_bob ENABLE ROW LEVEL SECURITY;
REVOKE ALL PRIVILEGES ON TABLE public.schema_migrations_bob FROM PUBLIC, anon, authenticated;
-- Internal migration owner still has access. No client SELECT policy is needed.

DO $audit$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint
      WHERE conrelid='public.product_variants'::regclass AND conname='product_variants_stock_check'
        AND contype='c'
        AND regexp_replace(pg_get_constraintdef(oid), ' NOT VALID$', '') =
          'CHECK (((current_stock >= (0)::numeric) AND (reserved_stock >= (0)::numeric) AND (reserved_stock <= current_stock)))') THEN
    RAISE EXCEPTION 'Stock constraint missing or differs from reviewed definition';
  END IF;
END
$audit$;
ALTER TABLE public.product_variants VALIDATE CONSTRAINT product_variants_stock_check;
ALTER VIEW public.v_financial_balances SET (security_invoker=true);
ALTER VIEW public.v_member_fee_balances SET (security_invoker=true);
ALTER VIEW public.v_stock_balances SET (security_invoker=true);
REVOKE ALL PRIVILEGES ON public.v_financial_balances, public.v_member_fee_balances,
  public.v_stock_balances FROM anon, PUBLIC;


-- ===== R4 anon treasury ACL =====
-- PROPOSTA ONLY: apply in the approved disposable V4 after Docker identity preflight.
-- Narrow ACL hardening. Does not change authenticated grants, RLS, owners, roles or defaults.
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
DO $pre$
BEGIN
  IF current_database() <> 'postgres' THEN RAISE EXCEPTION 'Unexpected database'; END IF;
  IF to_regclass('public.treasury_transactions') IS NULL THEN RAISE EXCEPTION 'Target table missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.treasury_transactions'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS is not enabled; refusing ACL change';
  END IF;
  IF session_user <> 'postgres' OR current_user <> 'postgres' THEN
    RAISE EXCEPTION 'Expected explicitly approved local V4 bootstrap session';
  END IF;
END $pre$;
REVOKE ALL PRIVILEGES ON TABLE public.treasury_transactions FROM anon;
DO $post$
DECLARE p text;
BEGIN
  FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
    IF has_table_privilege('anon','public.treasury_transactions',p) THEN
      RAISE EXCEPTION 'anon still has effective % privilege',p;
    END IF;
  END LOOP;
  -- Preserve normal authenticated CRUD grants; RLS continues to authorize each row/operation.
  FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE'] LOOP
    IF NOT has_table_privilege('authenticated','public.treasury_transactions',p) THEN
      RAISE EXCEPTION 'authenticated lost expected % privilege',p;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE oid='public.treasury_transactions'::regclass AND relrowsecurity) THEN
    RAISE EXCEPTION 'RLS unexpectedly disabled';
  END IF;
END $post$;


-- ===== R10 legacy finance SELECT authorization =====
\set ON_ERROR_STOP on
\echo 'R10: narrowing the legacy financial_* tables; no data DML is performed here'
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $r10_guard$
DECLARE
  v_old text;
  v_new text;
  v_restrictive text;
  v_cmd "char";
  v_permissive boolean;
  v_auth_oid oid := (SELECT oid FROM pg_roles WHERE rolname='authenticated');
  v_table regclass;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['public.financial_accounts'::regclass,'public.financial_transactions'::regclass] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table) THEN
      RAISE EXCEPTION 'R10 abort: RLS is not enabled on %', v_table;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_table AND polname NOT IN (
      CASE WHEN v_table='public.financial_accounts'::regclass THEN 'financial_accounts_tenant' ELSE 'financial_transactions_tenant' END,
      CASE WHEN v_table='public.financial_accounts'::regclass THEN 'financial_accounts_view_treasury' ELSE 'financial_transactions_view_treasury' END
    )) THEN
      RAISE EXCEPTION 'R10 abort: unexpected additional policy on %',v_table;
    END IF;
  END LOOP;

  SELECT pg_get_expr(polqual,polrelid) INTO v_old
  FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_tenant' AND polcmd='*' AND polpermissive;
  SELECT pg_get_expr(polqual,polrelid) INTO v_new
  FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_tenant' AND polcmd='r' AND polpermissive AND polroles=ARRAY[v_auth_oid];
  IF v_old IS NOT NULL AND v_old <> 'has_club_access(club_id)' THEN RAISE EXCEPTION 'R10 abort: unexpected legacy financial_accounts policy: %',v_old; END IF;
  IF v_old IS NULL AND v_new IS DISTINCT FROM 'has_club_access(club_id)' THEN RAISE EXCEPTION 'R10 abort: expected legacy or already-patched financial_accounts tenant policy'; END IF;

  SELECT pg_get_expr(polqual,polrelid) INTO v_old
  FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_tenant' AND polcmd='*' AND polpermissive;
  SELECT pg_get_expr(polqual,polrelid) INTO v_new
  FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_tenant' AND polcmd='r' AND polpermissive AND polroles=ARRAY[v_auth_oid];
  IF v_old IS NOT NULL AND v_old <> 'has_club_access(club_id)' THEN RAISE EXCEPTION 'R10 abort: unexpected legacy financial_transactions policy: %',v_old; END IF;
  IF v_old IS NULL AND v_new IS DISTINCT FROM 'has_club_access(club_id)' THEN RAISE EXCEPTION 'R10 abort: expected legacy or already-patched financial_transactions tenant policy'; END IF;

  SELECT pg_get_expr(polqual,polrelid),polcmd,polpermissive INTO v_restrictive,v_cmd,v_permissive
  FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_view_treasury';
  IF v_restrictive IS NOT NULL AND (v_restrictive <> 'has_club_permission(club_id, ''viewTreasury''::text)' OR v_cmd <> 'r' OR v_permissive OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_view_treasury' AND polroles=ARRAY[v_auth_oid])) THEN
    RAISE EXCEPTION 'R10 abort: unexpected financial_accounts_view_treasury definition';
  END IF;
  SELECT pg_get_expr(polqual,polrelid),polcmd,polpermissive INTO v_restrictive,v_cmd,v_permissive
  FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_view_treasury';
  IF v_restrictive IS NOT NULL AND (v_restrictive <> 'has_club_permission(club_id, ''viewTreasury''::text)' OR v_cmd <> 'r' OR v_permissive OR NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_view_treasury' AND polroles=ARRAY[v_auth_oid])) THEN
    RAISE EXCEPTION 'R10 abort: unexpected financial_transactions_view_treasury definition';
  END IF;
END;
$r10_guard$;

DO $r10_policy_patch$
DECLARE
  v_old text;
BEGIN
  SELECT pg_get_expr(polqual,polrelid) INTO v_old
  FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_tenant' AND polcmd='*' AND polpermissive;
  IF v_old IS NOT NULL THEN
    DROP POLICY financial_accounts_tenant ON public.financial_accounts;
    CREATE POLICY financial_accounts_tenant ON public.financial_accounts
      FOR SELECT TO authenticated USING (public.has_club_access(club_id));
  END IF;
  SELECT pg_get_expr(polqual,polrelid) INTO v_old
  FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_tenant' AND polcmd='*' AND polpermissive;
  IF v_old IS NOT NULL THEN
    DROP POLICY financial_transactions_tenant ON public.financial_transactions;
    CREATE POLICY financial_transactions_tenant ON public.financial_transactions
      FOR SELECT TO authenticated USING (public.has_club_access(club_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_view_treasury') THEN
    CREATE POLICY financial_accounts_view_treasury ON public.financial_accounts
      AS RESTRICTIVE FOR SELECT TO authenticated USING (public.has_club_permission(club_id,'viewTreasury'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_view_treasury') THEN
    CREATE POLICY financial_transactions_view_treasury ON public.financial_transactions
      AS RESTRICTIVE FOR SELECT TO authenticated USING (public.has_club_permission(club_id,'viewTreasury'));
  END IF;
END;
$r10_policy_patch$;

-- Current database-backed flows use treasury_* tables or guarded RPCs.
-- Legacy financial_* direct paths occur in demo/compatibility code;
-- confirm any external consumer before integrating this DML restriction.
REVOKE ALL PRIVILEGES ON TABLE public.financial_accounts, public.financial_transactions FROM anon;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.financial_accounts, public.financial_transactions FROM authenticated;

DO $r10_postconditions$
DECLARE
  v_table regclass;
  v_expected_tenant text;
  v_expected_permission text := 'has_club_permission(club_id, ''viewTreasury''::text)';
BEGIN
  FOREACH v_table IN ARRAY ARRAY['public.financial_accounts'::regclass,'public.financial_transactions'::regclass] LOOP
    v_expected_tenant := CASE WHEN v_table='public.financial_accounts'::regclass THEN 'financial_accounts_tenant' ELSE 'financial_transactions_tenant' END;
    IF (SELECT count(*) FROM pg_policy WHERE polrelid=v_table) <> 2 THEN RAISE EXCEPTION 'R10 postcondition failed: unexpected policy count on %',v_table; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_table AND polname=v_expected_tenant AND polcmd='r' AND polpermissive AND pg_get_expr(polqual,polrelid)='has_club_access(club_id)') THEN RAISE EXCEPTION 'R10 postcondition failed: tenant SELECT policy on %',v_table; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_table AND polname=CASE WHEN v_table='public.financial_accounts'::regclass THEN 'financial_accounts_view_treasury' ELSE 'financial_transactions_view_treasury' END AND polcmd='r' AND NOT polpermissive AND polroles=ARRAY[(SELECT oid FROM pg_roles WHERE rolname='authenticated')] AND pg_get_expr(polqual,polrelid)=v_expected_permission) THEN RAISE EXCEPTION 'R10 postcondition failed: restrictive viewTreasury SELECT policy on %',v_table; END IF;
    IF NOT has_table_privilege('authenticated',v_table,'SELECT') THEN RAISE EXCEPTION 'R10 postcondition failed: authenticated lost SELECT on %',v_table; END IF;
    IF has_table_privilege('authenticated',v_table,'INSERT') OR has_table_privilege('authenticated',v_table,'UPDATE') OR has_table_privilege('authenticated',v_table,'DELETE') THEN RAISE EXCEPTION 'R10 postcondition failed: authenticated retains direct DML on %',v_table; END IF;
    IF has_table_privilege('anon',v_table,'SELECT') OR has_table_privilege('anon',v_table,'INSERT') OR has_table_privilege('anon',v_table,'UPDATE') OR has_table_privilege('anon',v_table,'DELETE') THEN RAISE EXCEPTION 'R10 postcondition failed: anon retains a direct privilege on %',v_table; END IF;
    IF has_table_privilege('authenticated',v_table,'TRUNCATE') OR has_table_privilege('authenticated',v_table,'REFERENCES') OR has_table_privilege('authenticated',v_table,'TRIGGER') OR has_table_privilege('authenticated',v_table,'MAINTAIN') THEN RAISE EXCEPTION 'R10 postcondition failed: authenticated has an unexpected elevated privilege on %',v_table; END IF;
  END LOOP;
END;
$r10_postconditions$;

-- RC1-FINAL R11 postconditions: enforce the observed installation creator contract.
-- Application DDL runs as postgres. Supabase-managed public extension objects may be
-- created by supabase_admin; its managed defaults are reported, never changed here.
DO $r11_post$
DECLARE p text; t regclass;
BEGIN
  IF session_user<>'postgres' OR current_user<>'postgres' OR current_database()<>'postgres' THEN
    RAISE EXCEPTION 'RC1-FINAL requires the verified postgres migration identity/database';
  END IF;
  IF EXISTS(SELECT 1 FROM pg_extension WHERE extname IN ('pg_cron','pg_net'))
     OR to_regprocedure('public.asset_maintenance_v1()') IS NOT NULL THEN
    RAISE EXCEPTION 'RC1-FINAL refuses protected extension/object state';
  END IF;

  -- The replay catalog recorded zero global defaults. Check only the actual public creators,
  -- postgres and supabase_admin; unrelated managed-role globals are outside this app contract.
  IF EXISTS(SELECT 1 FROM pg_default_acl WHERE defaclnamespace=0
      AND defaclrole IN (
        'postgres'::regrole,'supabase_admin'::regrole
      )) THEN
    RAISE EXCEPTION 'RC1-FINAL found an out-of-contract global default ACL; review the actual creator before release';
  END IF;

  -- In the exposed application schema, only the migration owner and the documented
  -- Supabase-managed owner may have per-schema defaults. Check every object kind.
  IF EXISTS(
    SELECT 1 FROM pg_default_acl d
    WHERE d.defaclnamespace='public'::regnamespace
      AND d.defaclrole NOT IN ('postgres'::regrole,'supabase_admin'::regrole)
  ) THEN
    RAISE EXCEPTION 'RC1-FINAL found an unreviewed public default-ACL creator';
  END IF;
  -- pg_database_owner is an implicit pseudo-role for the current database owner,
  -- not an independent application creator. In the validated bootstrap postgres
  -- owns this database and no role is explicitly granted pg_database_owner.
  IF pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database())) <> 'postgres'
     OR EXISTS(SELECT 1 FROM pg_auth_members am JOIN pg_roles g ON g.oid=am.roleid WHERE g.rolname='pg_database_owner') THEN
    RAISE EXCEPTION 'RC1-FINAL pg_database_owner contract changed';
  END IF;
  IF EXISTS(
    SELECT 1 FROM pg_roles r
    WHERE r.rolname NOT IN ('postgres','supabase_admin','pg_database_owner')
      AND has_schema_privilege(r.oid,'public','CREATE')
  ) OR has_schema_privilege('anon','public','CREATE')
    OR has_schema_privilege('authenticated','public','CREATE') THEN
    RAISE EXCEPTION 'RC1-FINAL public object-creator contract changed';
  END IF;

  -- Browser-visible elevated ACLs on existing public relations are never covered by
  -- the supabase_admin defaults exception.
  IF EXISTS(
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN (VALUES ('anon'::name),('authenticated'::name)) client(role_name)
    WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f')
      AND (has_table_privilege(client.role_name,c.oid,'TRUNCATE')
        OR has_table_privilege(client.role_name,c.oid,'REFERENCES')
        OR has_table_privilege(client.role_name,c.oid,'TRIGGER')
        OR has_table_privilege(client.role_name,c.oid,'MAINTAIN'))
  ) THEN RAISE EXCEPTION 'Client role retains dangerous effective privileges on a public relation'; END IF;

  -- R14 recorded broad Supabase-managed defaults in public. Emit each ACL as evidence;
  -- do not mutate the managed role. Existing effective access is checked below.
  FOR p IN
    SELECT format('object_kind=%s acl=%s',d.defaclobjtype,d.defaclacl)
    FROM pg_default_acl d
    WHERE d.defaclrole='supabase_admin'::regrole
      AND d.defaclnamespace='public'::regnamespace
    ORDER BY d.defaclobjtype
  LOOP
    RAISE WARNING 'RC1_FINAL_KNOWN_SUPABASE_ADMIN_DEFAULT %',p;
  END LOOP;

  IF EXISTS(
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN (VALUES ('anon'::name),('authenticated'::name)) client(role_name)
    CROSS JOIN (VALUES ('SELECT'),('INSERT'),('UPDATE'),('DELETE'),('TRUNCATE'),('REFERENCES'),('TRIGGER'),('MAINTAIN')) priv(privilege)
    WHERE n.nspname='public' AND c.relkind IN ('r','p','v','m','f')
      AND c.relowner='supabase_admin'::regrole
      AND has_table_privilege(client.role_name,c.oid,priv.privilege)
  ) THEN RAISE EXCEPTION 'supabase_admin-owned public relation has effective browser-role privileges'; END IF;
  IF EXISTS(
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN (VALUES ('anon'::name),('authenticated'::name)) client(role_name)
    CROSS JOIN (VALUES ('USAGE'),('SELECT'),('UPDATE')) priv(privilege)
    WHERE n.nspname='public' AND c.relkind='S'
      AND c.relowner='supabase_admin'::regrole
      AND has_sequence_privilege(client.role_name,c.oid,priv.privilege)
  ) THEN RAISE EXCEPTION 'supabase_admin-owned public sequence has effective browser-role privileges'; END IF;
  IF EXISTS(
    SELECT 1 FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
    WHERE n.nspname='public' AND f.proowner='supabase_admin'::regrole AND f.prosecdef
      AND (has_function_privilege('anon',f.oid,'EXECUTE')
        OR has_function_privilege('authenticated',f.oid,'EXECUTE'))
  ) THEN RAISE EXCEPTION 'supabase_admin-owned public SECURITY DEFINER is executable by a browser role'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.schema_migrations_bob'::regclass) THEN RAISE EXCEPTION 'schema_migrations_bob RLS is not enabled'; END IF;
  FOREACH p IN ARRAY ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER','MAINTAIN'] LOOP
    IF has_table_privilege('anon','public.schema_migrations_bob',p) OR has_table_privilege('authenticated','public.schema_migrations_bob',p) THEN RAISE EXCEPTION 'Client role retains % on migration history',p; END IF;
    IF has_table_privilege('anon','public.treasury_transactions',p) THEN RAISE EXCEPTION 'anon retains % on treasury_transactions',p; END IF;
    IF has_table_privilege('authenticated','public.financial_accounts',p) AND p<>'SELECT' THEN RAISE EXCEPTION 'authenticated retains % on legacy financial_accounts',p; END IF;
    IF has_table_privilege('authenticated','public.financial_transactions',p) AND p<>'SELECT' THEN RAISE EXCEPTION 'authenticated retains % on legacy financial_transactions',p; END IF;
    IF has_table_privilege('anon','public.financial_accounts',p) OR has_table_privilege('anon','public.financial_transactions',p) THEN RAISE EXCEPTION 'anon retains % on legacy finance tables',p; END IF;
  END LOOP;
  IF NOT has_table_privilege('authenticated','public.treasury_transactions','SELECT')
     OR NOT has_table_privilege('authenticated','public.treasury_transactions','INSERT')
     OR NOT has_table_privilege('authenticated','public.treasury_transactions','UPDATE')
     OR NOT has_table_privilege('authenticated','public.treasury_transactions','DELETE') THEN RAISE EXCEPTION 'authenticated CRUD contract changed on treasury_transactions'; END IF;
  IF NOT has_table_privilege('authenticated','public.financial_accounts','SELECT') OR NOT has_table_privilege('authenticated','public.financial_transactions','SELECT') THEN RAISE EXCEPTION 'authenticated lost legacy finance SELECT'; END IF;
  IF NOT (SELECT convalidated FROM pg_constraint WHERE conrelid='public.product_variants'::regclass AND conname='product_variants_stock_check') THEN RAISE EXCEPTION 'Stock check is not validated'; END IF;
  FOREACH t IN ARRAY ARRAY['public.v_financial_balances'::regclass,'public.v_member_fee_balances'::regclass,'public.v_stock_balances'::regclass] LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=t AND 'security_invoker=true'=ANY(coalesce(reloptions,'{}'))) THEN RAISE EXCEPTION 'View % is not security_invoker',t; END IF;
    IF has_table_privilege('anon',t,'SELECT') OR NOT has_table_privilege('authenticated',t,'SELECT') THEN RAISE EXCEPTION 'Unexpected view ACL for %',t; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass)<>2 OR (SELECT count(*) FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass)<>2 THEN RAISE EXCEPTION 'Unexpected legacy finance policy composition'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.financial_accounts'::regclass AND polname='financial_accounts_view_treasury' AND NOT polpermissive AND polcmd='r') OR NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='public.financial_transactions'::regclass AND polname='financial_transactions_view_treasury' AND NOT polpermissive AND polcmd='r') THEN RAISE EXCEPTION 'Restrictive viewTreasury policies missing'; END IF;
  IF to_regprocedure('public.asset_maintenance_v1()') IS NOT NULL OR EXISTS(SELECT 1 FROM pg_extension WHERE extname IN ('pg_cron','pg_net')) THEN RAISE EXCEPTION 'Protected object/extension state changed unexpectedly'; END IF;
END $r11_post$;

-- R12 export authorization patch; precondition accepts only original or exact validated final function bodies.
-- R12.4 idempotent clone-tested export patch candidate; V4 remains unchanged.
-- Confirmed by R11: president with an explicit viewTreasury deny exported an account row with opening_balance.
-- Fail-closed source guards bind this patch to the exact V4 definitions reviewed in R11.
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$
BEGIN
  IF session_user<>'postgres' OR current_user<>'postgres' THEN RAISE EXCEPTION 'R11 export patch requires the verified postgres migration identity'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid='public.begin_club_export_v1(uuid,text[],boolean,boolean,text)'::regprocedure)) NOT IN ('a647c9fa341150056b75aa6b3f53cca2','95598577549f54987493101cf0ca80c3') THEN RAISE EXCEPTION 'begin_club_export_v1 drifted from reviewed R11 source'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid='public.club_export_dataset_v1(uuid,uuid,text,integer,integer)'::regprocedure)) NOT IN ('911ebdcd7b44f652a1253d9ae28cbd07','11c1ec04f9abfbabc9bb164f2fa95664') THEN RAISE EXCEPTION 'club_export_dataset_v1 drifted from reviewed R11 source'; END IF;
  IF NOT has_function_privilege('authenticated','public.begin_club_export_v1(uuid,text[],boolean,boolean,text)','EXECUTE') OR has_function_privilege('anon','public.begin_club_export_v1(uuid,text[],boolean,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'Unexpected begin export EXECUTE ACL'; END IF;
  IF NOT has_function_privilege('authenticated','public.club_export_dataset_v1(uuid,uuid,text,integer,integer)','EXECUTE') OR has_function_privilege('anon','public.club_export_dataset_v1(uuid,uuid,text,integer,integer)','EXECUTE') THEN RAISE EXCEPTION 'Unexpected dataset export EXECUTE ACL'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.begin_club_export_v1(target_club uuid, p_modules text[], p_include_sensitive boolean DEFAULT false, p_include_files boolean DEFAULT false, p_manifest_version text DEFAULT 'bob-export-v1'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_export uuid;
  v_modules text[];
  v_version text := coalesce(nullif(btrim(p_manifest_version), ''), 'bob-export-v1');
  v_allowed constant text[] := array[
    'members','treasury','financial','fees','lottery','events','inventory',
    'documents','communication','agenda','weekly_officer','configuration','audit'
  ]::text[];
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  select array_agg(module_key order by module_key)
    into v_modules
  from (
    select distinct btrim(value) as module_key
    from unnest(coalesce(p_modules, array[]::text[])) as value
    where value is not null and btrim(value) <> ''
  ) normalized;

  if coalesce(cardinality(v_modules), 0) = 0 then
    raise exception 'Seleciona pelo menos uma área para exportar.';
  end if;

  if exists (
    select 1
    from unnest(v_modules) as module_key
    where not (module_key = any(v_allowed))
  ) then
    raise exception 'A exportação contém uma área inválida.';
  end if;

  if 'treasury' = any(v_modules) and not public.has_club_permission(target_club, 'viewTreasury') then
    raise exception 'Sem autorização para exportar dados da Tesouraria.' using errcode='42501';
  end if;
  if length(v_version) > 32 or v_version !~ '^[A-Za-z0-9._-]+$' then
    raise exception 'Versão do manifesto inválida.';
  end if;

  if coalesce(p_include_sensitive, false) and not (
    public.has_club_permission(target_club, 'viewEmergencyData')
    and public.has_club_permission(target_club, 'viewSensitiveDocuments')
  ) then
    raise exception 'Sem permissão para incluir dados altamente sensíveis.';
  end if;

  insert into public.exports (
    club_id, requested_by, status, modules, include_sensitive, include_files,
    manifest_version
  ) values (
    target_club, auth.uid(), 'running', v_modules,
    coalesce(p_include_sensitive, false), coalesce(p_include_files, false),
    v_version
  )
  returning id into v_export;

  insert into public.audit_log (
    club_id, actor_id, action, entity_type, entity_id, after_data, data, created_at
  ) values (
    target_club,
    auth.uid(),
    'club_export_started',
    'club_export',
    v_export::text,
    jsonb_build_object(
      'status', 'running',
      'modules', to_jsonb(v_modules),
      'include_sensitive', coalesce(p_include_sensitive, false),
      'include_files', coalesce(p_include_files, false),
      'manifest_version', v_version
    ),
    jsonb_build_object('export_id', v_export),
    now()
  );

  return v_export;
end;
$function$;

CREATE OR REPLACE FUNCTION public.club_export_dataset_v1(target_club uuid, p_export uuid, p_dataset text, p_offset integer DEFAULT 0, p_limit integer DEFAULT 1000)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_export public.exports%rowtype;
  v_section text;
  v_sensitive boolean := false;
  v_sql text;
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_limit integer := least(greatest(coalesce(p_limit, 1000), 1), 1000);
begin
  if auth.uid() is null then
    raise exception 'Autenticação necessária.';
  end if;

  if not public.has_club_role(
    target_club,
    array['president','vice_president','admin','administrator','super_admin']::text[]
  ) then
    raise exception 'Sem permissão para exportação integral.';
  end if;

  select *
    into v_export
  from public.exports
  where id = p_export
    and club_id = target_club
    and requested_by = auth.uid()
    and status = 'running';

  if not found then
    raise exception 'Exportação ativa não encontrada.';
  end if;

  case p_dataset
    when 'membros/membros.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_number,t.full_name,t.nickname,t.email,t.phone,t.birth_date,t.joined_at,t.status,t.prospect_joined_at,t.full_colors_at,t.primary_role,t.additional_roles,t.photo_path from public.members t where t.club_id = $1 order by t.member_number, t.id offset $2 limit $3) row_data';
    when 'membros/dados_sensiveis.csv' then
      v_section := 'members';
      v_sensitive := true;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_number,t.full_name,t.tax_number,t.address,t.postal_code,t.locality,t.emergency_contact,t.notes from public.members t where t.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'membros/motas.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.brand,t.model,t.year,t.registration,t.nickname,t.primary_motorcycle,t.active,t.acquired_on,t.retired_on,t.notes from public.member_motorcycles t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'membros/cargos.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.position_id,t.is_primary,t.starts_at,t.ends_at from public.member_positions t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'membros/estados_historico.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.old_status,t.new_status,t.changed_at,t.changed_by,t.notes from public.member_status_history t where t.club_id = $1 order by t.changed_at, t.id offset $2 limit $3) row_data';
    when 'membros/timeline.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.event_type,t.title,t.description,t.event_date,t.visibility,t.source_type,t.source_id from public.member_timeline t where t.club_id = $1 order by t.event_date, t.id offset $2 limit $3) row_data';
    when 'membros/patches.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.product_id,t.variant_id,t.patch_name,t.variant_name,t.status,t.requested_at,t.approved_at,t.delivered_at,t.delivery_location_name,t.notes from public.member_patch_awards t where t.club_id = $1 order by t.requested_at, t.id offset $2 limit $3) row_data';
    when 'membros/manutencao.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.motorcycle_id,t.service_date,t.service_type,t.description,t.odometer_km,t.workshop,t.cost,t.next_service_date,t.next_service_km,t.notes from public.maintenance_records t where t.club_id = $1 order by t.service_date, t.id offset $2 limit $3) row_data';
    when 'membros/manutencao_anexos.csv' then
      v_section := 'members';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.maintenance_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size from public.maintenance_attachments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'tesouraria/contas.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.account_type,t.iban,t.opening_balance,t.opening_date,t.active,t.allows_negative from public.treasury_accounts t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/categorias.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.direction,t.active from public.treasury_categories t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/centros_custo.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.code,t.active from public.cost_centers t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'tesouraria/movimentos.csv' then
      v_section := 'treasury';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.kind,t.account_id,t.destination_account_id,t.category_id,t.cost_center_id,t.event_id,t.transaction_date,t.description,t.amount,t.payment_method,t.notes,t.source_type,t.source_id,t.reversal_of,t.created_at from public.treasury_transactions t where t.club_id = $1 order by t.transaction_date, t.id offset $2 limit $3) row_data';
    when 'financeiro/pedidos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.request_type,t.category,t.batch_id,t.amount,t.description,t.due_date,t.status,t.review_note,t.payment_method,t.treasury_account_id,t.treasury_transaction_id,t.submitted_at,t.paid_at,t.source_type,t.source_id,t.created_at from public.financial_requests t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'financeiro/pedidos_anexos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.request_id,t.kind,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at from public.financial_request_attachments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'financeiro/documentos_movimentos.csv' then
      v_section := 'financial';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.transaction_id,t.document_type,t.origin,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.is_primary,t.created_at from public.financial_transaction_documents t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'quotas/planos.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.amount,t.frequency,t.due_day,t.active from public.fee_plans t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'quotas/obrigacoes.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.fee_plan_id,t.reference_year,t.reference_month,t.due_date,t.amount,t.paid_amount,t.status,t.notes,t.obligation_type from public.fee_obligations t where t.club_id = $1 order by t.due_date, t.id offset $2 limit $3) row_data';
    when 'quotas/pagamentos.csv' then
      v_section := 'fees';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.obligation_id,t.transaction_id,t.amount,t.paid_at,t.received_by,t.notes from public.fee_payments t where t.club_id = $1 order by t.paid_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/participantes.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.status,t.numbers,t.stars,t.created_at from public.euromillions_players t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/sorteios.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.week,t.start_date,t.end_date,t.unit_cost,t.total_bet,t.prize,t.bulletin_path,t.status,t.created_at from public.euromillions_draws t where t.club_id = $1 order by t.start_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/chaves.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_id,t.numbers,t.stars from public.euromillions_keys t join public.euromillions_draws p on p.id = t.draw_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'euromilhoes/participacoes.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_id,t.member_id,t.amount,t.paid,t.paid_at,t.billing_frequency,t.numbers,t.stars,t.paid_amount,t.balance,t.active,t.payment_method,t.transaction_id from public.euromillions_participations t join public.euromillions_draws p on p.id = t.draw_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'euromilhoes/resultados.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.draw_date,t.numbers,t.stars,t.official_draw_number,t.prize_table,t.source,t.imported_at,t.created_at from public.euromillions_results t where t.club_id = $1 order by t.draw_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/cobrancas.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.player_id,t.week_start,t.draw_date,t.amount,t.paid_amount,t.paid_at,t.payment_method,t.transaction_id from public.euromillions_draw_charges t where t.club_id = $1 order by t.draw_date, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/multas.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.result_id,t.player_id,t.missed_numbers,t.missed_stars,t.fine_amount,t.paid_amount,t.paid_at,t.payment_method,t.transaction_id,t.created_at from public.euromillions_fines t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'euromilhoes/premios.csv' then
      v_section := 'lottery';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.result_id,t.player_id,t.category,t.matched_numbers,t.matched_stars,t.prize_amount,t.received_amount,t.received_at,t.payment_method,t.transaction_id,t.created_at from public.euromillions_prizes t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'eventos/eventos.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.location,t.starts_at,t.ends_at,t.status,t.capacity,t.budget,t.event_mode_enabled,t.created_at,t.updated_at from public.events t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'eventos/inscricoes.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.member_id,t.guest_name,t.status,t.checked_in_at,t.notes,t.created_at from public.event_registrations t join public.events p on p.id = t.event_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'eventos/voluntarios.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.member_id,t.function_name,t.status,t.created_at from public.event_volunteers t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'eventos/parceiros.csv' then
      v_section := 'events';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.partner_type,t.name,t.contact_name,t.phone,t.email,t.agreed_value,t.paid_value,t.notes from public.event_partners t join public.events p on p.id = t.event_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/produtos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.sku,t.category,t.unit,t.cost,t.sale_price,t.minimum_stock,t.current_stock,t.reserved_stock,t.inventory_area,t.description,t.supplier,t.institutional_delivery,t.purchase_unit,t.consumption_unit,t.units_per_purchase,t.purchase_cost,t.active,t.photo_path from public.products t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/variantes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.name,t.sku,t.attributes,t.active,t.current_stock,t.reserved_stock,t.minimum_stock,t.cost,t.sale_price,t.photo_path from public.product_variants t join public.products p on p.id = t.product_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/imagens_produtos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.storage_path,t.is_primary,t.created_at from public.product_images t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/categorias.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.area,t.name,t.active,t.created_at from public.inventory_categories t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/precos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.audience,t.price,t.created_at from public.inventory_prices t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/visibilidade.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.audience,t.allowed,t.created_at from public.inventory_visibility t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/localizacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.location_type,t.event_id,t.parent_id,t.active from public.inventory_locations t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/stock_localizacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.location_id,t.quantity,t.reserved_quantity,t.created_at,t.updated_at from public.inventory_stock_balances t where t.club_id = $1 order by t.updated_at, t.id offset $2 limit $3) row_data';
    when 'inventario/movimentos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.variant_id,t.event_id,t.kind,t.quantity,t.unit_cost,t.notes,t.from_location_id,t.to_location_id,t.transfer_group_id,t.created_at from public.stock_movements t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.external_name,t.external_contact,t.status,t.total_amount,t.paid_amount,t.notes,t.created_at,t.updated_at from public.shop_orders t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.order_id,t.product_id,t.variant_id,t.quantity,t.unit_price from public.shop_order_items t join public.shop_orders p on p.id = t.order_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/encomendas_pagamentos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.order_id,t.amount,t.payment_method,t.treasury_transaction_id,t.created_at from public.shop_order_payments t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_number,t.name,t.category,t.description,t.acquisition_date,t.acquisition_value,t.supplier,t.condition,t.location_id,t.responsible_member_id,t.warranty_until,t.last_maintenance_at,t.next_maintenance_at,t.active,t.notes,t.current_value,t.brand,t.model,t.serial_number,t.qr_code,t.requires_inspection,t.inspection_interval_months,t.last_inspection_at,t.next_inspection_at,t.photo_path from public.inventory_assets t where t.club_id = $1 order by t.asset_number, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_imagens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.storage_path,t.image_type,t.is_primary,t.created_at from public.asset_images t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_eventos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.event_type,t.title,t.description,t.metadata,t.created_at from public.asset_events t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_emprestimos.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.borrower_type,t.member_id,t.event_id,t.external_name,t.loaned_at,t.expected_return_at,t.returned_at,t.returned_condition,t.notes,t.return_notes,t.created_at from public.asset_loans t where t.club_id = $1 order by t.loaned_at, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_manutencao.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.asset_id,t.maintenance_date,t.maintenance_type,t.description,t.cost,t.supplier,t.next_due_date,t.account_id,t.payment_method,t.treasury_transaction_id,t.created_at from public.asset_maintenance t where t.club_id = $1 order by t.maintenance_date, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_kits.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.description,t.active,t.created_at from public.asset_kits t where t.club_id = $1 order by t.name, t.id offset $2 limit $3) row_data';
    when 'inventario/patrimonio_kits_itens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.kit_id,t.asset_id,t.quantity from public.asset_kit_items t join public.asset_kits p on p.id = t.kit_id where p.club_id = $1 offset $2 limit $3) row_data';
    when 'inventario/contagens.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.location_id,t.event_id,t.status,t.notes,t.started_by,t.started_at,t.completed_by,t.completed_at from public.inventory_count_sessions t where t.club_id = $1 order by t.started_at, t.id offset $2 limit $3) row_data';
    when 'inventario/contagens_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.session_id,t.product_id,t.variant_id,t.theoretical_qty,t.counted_qty,t.difference,t.unit_cost,t.notes,t.photo_path,t.recounted,t.counted_by,t.counted_at from public.inventory_count_items t join public.inventory_count_sessions p on p.id = t.session_id where p.club_id = $1 order by t.id offset $2 limit $3) row_data';
    when 'inventario/bar_operacoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.product_id,t.event_id,t.operation_type,t.purchase_units,t.consumption_quantity,t.unit_price,t.total_amount,t.payment_method,t.notes,t.treasury_transaction_id,t.created_at from public.bar_operations t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/bar_sessoes.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.event_id,t.source,t.status,t.notes,t.created_at,t.confirmed_at from public.bar_consumption_sessions t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'inventario/bar_sessoes_linhas.csv' then
      v_section := 'inventory';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.session_id,t.product_id,t.quantity,t.operation_type,t.unit_price,t.notes,t.created_at from public.bar_consumption_session_items t join public.bar_consumption_sessions p on p.id = t.session_id where p.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'documentos/documentos.csv' then
      v_section := 'documents';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.category,t.description,t.document_date,t.version,t.status,t.expires_at,t.sensitive,t.tags,t.linked_entity_type,t.linked_entity_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at,t.updated_at from public.documents t where t.club_id = $1 and t.sensitive = false order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'documentos/documentos_sensiveis.csv' then
      v_section := 'documents';
      v_sensitive := true;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.category,t.description,t.document_date,t.version,t.status,t.expires_at,t.sensitive,t.tags,t.linked_entity_type,t.linked_entity_id,t.storage_path,t.original_file_name,t.mime_type,t.file_size,t.created_at,t.updated_at from public.documents t where t.club_id = $1 and t.sensitive = true order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'comunicacao/comunicados.csv' then
      v_section := 'communication';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.title,t.body,t.priority,t.audience,t.published_at,t.expires_at,t.requires_acknowledgement,t.created_at,t.updated_at from public.announcements t where t.club_id = $1 order by t.published_at, t.id offset $2 limit $3) row_data';
    when 'comunicacao/confirmacoes_leitura.csv' then
      v_section := 'communication';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.announcement_id,t.profile_id,t.acknowledged_at,t.created_at from public.announcement_acknowledgements t where t.club_id = $1 order by t.acknowledged_at, t.id offset $2 limit $3) row_data';
    when 'agenda/itens.csv' then
      v_section := 'agenda';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.item_type,t.title,t.description,t.starts_at,t.ends_at,t.all_day,t.location,t.audience,t.priority,t.status,t.created_at,t.updated_at from public.agenda_items t where t.club_id = $1 order by t.starts_at, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/jantares.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.dinner_date,t.dinner_kind,t.status,t.assigned_member_id,t.external_name,t.dish,t.notes,t.assignment_source,t.generated,t.created_at,t.updated_at from public.weekly_dinners t where t.club_id = $1 order by t.dinner_date, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/rotacao.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.rotation_order,t.enabled,t.availability_status,t.force_included,t.joined_rotation_at,t.notes,t.created_at,t.updated_at from public.weekly_officer_rotation t where t.club_id = $1 order by t.rotation_order, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/ausencias.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.member_id,t.absence_kind,t.starts_on,t.ends_on,t.notes,t.created_at,t.updated_at from public.weekly_officer_absences t where t.club_id = $1 order by t.starts_on, t.id offset $2 limit $3) row_data';
    when 'oficial_semana/trocas.csv' then
      v_section := 'weekly_officer';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.dinner_id,t.requester_member_id,t.requested_member_id,t.status,t.requester_note,t.response_note,t.manager_note,t.responded_at,t.responded_by,t.applied_at,t.applied_by,t.created_at,t.updated_at from public.weekly_officer_swap_requests t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'configuracao/clube.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.name,t.legal_name,t.slug,t.primary_color,t.currency,t.timezone,t.active,t.created_at,t.updated_at from public.clubs t where t.id = $1 order by t.id offset $2 limit $3) row_data';
    when 'configuracao/cargos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.code,t.name,t.sort_order,t.active,t.created_at,t.updated_at from public.club_positions t where t.club_id = $1 order by t.sort_order, t.id offset $2 limit $3) row_data';
    when 'configuracao/permissoes_cargos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.role_key,t.permission_key,t.allowed,t.updated_at,t.created_at from public.club_role_permissions t where t.club_id = $1 offset $2 limit $3) row_data';
    when 'configuracao/parametros.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.key,t.value,t.created_at,t.updated_at from public.club_settings t where t.club_id = $1 order by t.key, t.id offset $2 limit $3) row_data';
    when 'configuracao/acessos.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.profile_id,t.access_role,t.active,t.created_at,t.updated_at from public.club_memberships t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'configuracao/excecoes_permissoes.csv' then
      v_section := 'configuration';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.profile_id,t.permission_key,t.allowed,t.updated_at,t.created_at from public.user_permission_overrides t where t.club_id = $1 offset $2 limit $3) row_data';
    when 'auditoria/audit_log.csv' then
      v_section := 'audit';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.actor_id,t.entity_type,t.entity_id,t.action,t.created_at from public.audit_log t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    when 'auditoria/atividade.csv' then
      v_section := 'audit';
      v_sensitive := false;
      v_sql := 'select to_jsonb(row_data) from (select t.id,t.actor_id,t.activity_type,t.title,t.description,t.entity_type,t.entity_id,t.created_at from public.activity_feed t where t.club_id = $1 order by t.created_at, t.id offset $2 limit $3) row_data';
    else
      raise exception 'Dataset de exportação inválido.';
  end case;

  if not (v_section = any(v_export.modules)) then
    raise exception 'Dataset fora das áreas selecionadas.';
  end if;

  if v_section = 'treasury' and not public.has_club_permission(target_club, 'viewTreasury') then
    raise exception 'Sem autorização para exportar dados da Tesouraria.' using errcode='42501';
  end if;
  if v_sensitive and not v_export.include_sensitive then
    raise exception 'Dados sensíveis não autorizados nesta exportação.';
  end if;

  if v_sensitive and not (
    public.has_club_permission(target_club, 'viewEmergencyData')
    and public.has_club_permission(target_club, 'viewSensitiveDocuments')
  ) then
    raise exception 'Sem permissão para dados altamente sensíveis.';
  end if;

  return query execute v_sql using target_club, v_offset, v_limit;
end;
$function$;

DO $post$
BEGIN
  IF position('has_club_permission(target_club, ''viewTreasury'')' in (SELECT prosrc FROM pg_proc WHERE oid='public.begin_club_export_v1(uuid,text[],boolean,boolean,text)'::regprocedure))=0 THEN RAISE EXCEPTION 'Treasury module gate missing from begin export'; END IF;
  IF position('has_club_permission(target_club, ''viewTreasury'')' in (SELECT prosrc FROM pg_proc WHERE oid='public.club_export_dataset_v1(uuid,uuid,text,integer,integer)'::regprocedure))=0 THEN RAISE EXCEPTION 'Treasury dataset gate missing from dataset RPC'; END IF;
  IF NOT has_function_privilege('authenticated','public.begin_club_export_v1(uuid,text[],boolean,boolean,text)','EXECUTE') OR has_function_privilege('anon','public.begin_club_export_v1(uuid,text[],boolean,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'begin export EXECUTE ACL changed'; END IF;
  IF NOT has_function_privilege('authenticated','public.club_export_dataset_v1(uuid,uuid,text,integer,integer)','EXECUTE') OR has_function_privilege('anon','public.club_export_dataset_v1(uuid,uuid,text,integer,integer)','EXECUTE') THEN RAISE EXCEPTION 'dataset export EXECUTE ACL changed'; END IF;
END $post$;

-- R14: defaults restritos a novos objetos public criados pelo role de replay postgres.
-- As migrations historicas foram executadas como postgres; grants explicitos e service_role permanecem.
-- Supabase-managed schemas e defaults de supabase_admin ficam fora deste bloco.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL PRIVILEGES ON SEQUENCES FROM anon, authenticated;
DO $r14_post$
DECLARE rel_acl aclitem[];
  seq_acl aclitem[];
BEGIN
  SELECT defaclacl INTO rel_acl FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
  WHERE d.defaclrole='postgres'::regrole AND n.nspname='public' AND d.defaclobjtype='r';
  SELECT defaclacl INTO seq_acl FROM pg_default_acl d JOIN pg_namespace n ON n.oid=d.defaclnamespace
  WHERE d.defaclrole='postgres'::regrole AND n.nspname='public' AND d.defaclobjtype='S';
  IF rel_acl IS NULL OR seq_acl IS NULL THEN RAISE EXCEPTION 'R14 default ACL expected rows missing'; END IF;
  IF EXISTS (SELECT 1 FROM aclexplode(rel_acl) a WHERE a.grantee IN ('anon'::regrole,'authenticated'::regrole)) THEN RAISE EXCEPTION 'R14 anon/auth table defaults remain'; END IF;
  IF EXISTS (SELECT 1 FROM aclexplode(seq_acl) a WHERE a.grantee IN ('anon'::regrole,'authenticated'::regrole)) THEN RAISE EXCEPTION 'R14 anon/auth sequence defaults remain'; END IF;
  IF NOT EXISTS (SELECT 1 FROM aclexplode(rel_acl) a WHERE a.grantee='service_role'::regrole AND a.privilege_type='INSERT')
     OR NOT EXISTS (SELECT 1 FROM aclexplode(seq_acl) a WHERE a.grantee='service_role'::regrole AND a.privilege_type='USAGE') THEN RAISE EXCEPTION 'R14 service_role defaults changed'; END IF;
END
$r14_post$;
-- R16: only authenticated needs direct EXECUTE on the agenda helper used by its RLS policy.
DO $r16_agenda_precondition$
DECLARE p record;
BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres' OR current_database()<>'postgres' THEN RAISE EXCEPTION 'R16 expected PostgreSQL migration identity'; END IF;
 SELECT proowner::regrole::text AS owner,prosecdef AS security_definer,proconfig,prosrc,proacl INTO p FROM pg_proc WHERE oid='public.can_view_direction_agenda_v1(uuid)'::regprocedure;
 IF p.owner<>'postgres' OR NOT p.security_definer OR NOT ('search_path=public'=ANY(p.proconfig))
    OR p.prosrc NOT LIKE '%public.has_club_permission(target_club,%viewDirectionAgenda%'
    OR has_function_privilege('anon','public.can_view_direction_agenda_v1(uuid)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.can_view_direction_agenda_v1(uuid)','EXECUTE')
    OR EXISTS(SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'R16 agenda helper baseline differs; refusing migration'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_policy pol WHERE pol.polrelid='public.agenda_items'::regclass AND pol.polname='agenda_items_select' AND pol.polcmd='r' AND pol.polpermissive AND (SELECT oid FROM pg_roles WHERE rolname='authenticated')=ANY(pol.polroles) AND pg_get_expr(pol.polqual,pol.polrelid) LIKE '%can_view_direction_agenda_v1%') THEN RAISE EXCEPTION 'R16 agenda RLS policy baseline differs'; END IF;
END
$r16_agenda_precondition$;
GRANT EXECUTE ON FUNCTION public.can_view_direction_agenda_v1(uuid) TO authenticated;
-- R16 security catalog guard body. Embed at the end of each migration transaction.
-- Read-only assertions. Explicit baseline covers every public SECURITY DEFINER function (235 signatures).
DO $r16_catalog_guard$
DECLARE e record;
  f oid;
  actual_owner text;
  actual_definer boolean;
  actual_config text;
  actual_acl text;
  actual_anon boolean;
  actual_auth boolean;
  actual_service boolean;
  actual_public boolean;
  expected_signatures text[] := ARRAY[]::text[];
  expected_count integer := 0;
  rel_acl aclitem[];
  seq_acl aclitem[];
  fn_acl aclitem[];
  n integer;
  bad record;
BEGIN
  FOR e IN
    SELECT * FROM (VALUES('acknowledge_event_task_v1(uuid,boolean)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('activity_announcement_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_document_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_euromillions_result_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_event_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_fee_payment_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_member_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_permission_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_stock_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_treasury_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('activity_user_permission_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('add_fee_credit_adjustment_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('add_financial_attachment_v1(uuid,uuid,text,text,text,text,bigint)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('add_financial_transaction_document_v1(uuid,uuid,text,text,text,text,bigint)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('agenda_calendar_v1(uuid,date,date)','postgres',true,'search_path=pg_catalog, public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('agenda_current_member_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('agenda_notify_profiles_v1(uuid,text,text,text,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('apply_fee_adjustment_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('apply_fee_credit_v1(uuid,uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('apply_fee_exemption_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('apply_import_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('approve_cash_session_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('approve_event_proposal_v1(uuid,text)','postgres',true,'search_path=""','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('approve_member_patch_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('archive_member_motorcycle_v1(uuid,uuid,uuid,date)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('archive_notification_v1(uuid,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('asset_loan_v1(uuid,uuid,text,uuid,uuid,text,timestamp with time zone,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('asset_return_v1(uuid,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('assign_bar_sale_dinner_v1(uuid,uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('attach_bar_ocr_source_v1(uuid,uuid,text,text,text,bigint)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('audit_capture_row_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('audit_event(uuid,text,text,text,jsonb,jsonb,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('bar_operation_v1(uuid,uuid,text,numeric,uuid,numeric,numeric,text,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('bar_operation_v2(uuid,uuid,text,numeric,uuid,numeric,numeric,text,text,boolean,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('bar_sale_history_v1(uuid,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('bar_weekly_dinner_choices_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('begin_club_export_v1(uuid,text[],boolean,boolean,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('begin_import_v1(uuid,text,text,text,jsonb)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('budget_performance_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('can_edit_member_milestone_dates_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('can_manage_agenda_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('can_manage_weekly_officer_v1(uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('can_view_direction_agenda_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cancel_agenda_item_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cancel_member_patch_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cancel_reported_fee_payment_v1(uuid,uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cancel_treasury_obligation_v1(uuid,text,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cancel_weekly_officer_swap_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('claim_push_delivery_v1(uuid,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('classify_weekly_dinner_sale_item_v1(uuid,uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('cleanup_event_volunteer_assignments_v1()','postgres',true,'search_path=""','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('close_bank_reconciliation_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('close_cash_session_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('club_export_dataset_v1(uuid,uuid,text,integer,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('club_export_file_access_v1(text,text)','postgres',true,'search_path=public, storage','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('complete_bar_sale_v1(uuid,uuid,jsonb,text,uuid,text,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('complete_bar_sale_v2(uuid,uuid,jsonb,text,uuid,text,text,uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('complete_bar_sale_v3(uuid,uuid,jsonb,text,uuid,text,text,uuid,uuid,text,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('complete_club_export_v1(uuid,uuid,integer,integer,integer,bigint)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('complete_push_delivery_v1(uuid,text,text,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('confirm_bar_ocr_purchase_v1(uuid,uuid,jsonb,uuid,uuid,text,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_bar_ocr_job_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_bar_sale_v1(uuid,text,text,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_bar_sale_v2(uuid,text,text,uuid,text,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_bar_sale_v3(uuid,text,text,uuid,text,uuid,text,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_member_charges_v1(uuid,uuid[],text,numeric,text,date)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_member_with_position(uuid,integer,text,text,text,text,date,uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_reimbursement_draft_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_reported_fee_payment_v1(uuid,numeric,date,text,text,text,text,text,bigint)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_shop_order_v1(uuid,uuid,uuid,numeric,numeric,uuid,text,text,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_transaction_v1(uuid,text,uuid,uuid,text,numeric)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('create_treasury_transaction(uuid,transaction_kind,uuid,uuid,uuid,uuid,uuid,date,text,numeric,text,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('current_financial_member_v1(uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('current_weekly_officer_member_v1(uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('dashboard_summary(uuid)','postgres',true,'search_path=pg_catalog, public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('dashboard_summary_rc1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('deactivate_push_device_server_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('deactivate_push_device_v1(uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('delete_fee_obligation_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('delete_financial_transaction_document_v1(uuid,uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('delete_weekly_officer_absence_v1(uuid,uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('deliver_member_patch_v1(uuid,uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('dispatch_push_delivery_webhook_v1()','postgres',true,'search_path=public, net','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('emit_domain_event(uuid,text,text,uuid,jsonb)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('enforce_event_capacity_floor_v1()','postgres',true,'search_path=""','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('enforce_event_capacity_seat_v1()','postgres',true,'search_path=""','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('enqueue_notification_push_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('ensure_euromillions_open_draw_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('ensure_weekly_officer_schedule_v1(uuid,integer)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('fail_club_export_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('fee_credit_balance_v1(uuid,uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('fee_settings_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('financial_activity_v1(uuid,uuid,text,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('financial_manager_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('financial_request_access_v1(uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('financial_storage_access_v2(text,boolean)','postgres',true,'search_path=public, storage','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('global_search_v1(uuid,text,integer)','postgres',true,'search_path=pg_catalog, public, extensions','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('handle_new_user()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('has_club_access(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('has_club_permission(uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('has_club_role(uuid,text[])','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('import_validate_row_v1(uuid,text,jsonb)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_advanced_maintenance_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_advanced_summary_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_balance_apply_internal_v1(uuid,uuid,uuid,uuid,numeric,numeric)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_breakage_record_v1(uuid,uuid,uuid,uuid,numeric,text,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_count_finalize_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_count_set_qty_v1(uuid,uuid,numeric,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_count_start_v1(uuid,text,uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_default_location_v1(uuid,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_expire_reservations_internal_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_lot_receive_v1(uuid,uuid,uuid,uuid,text,numeric,date,date,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_lots_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_operation_v1(uuid,uuid,text,numeric,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_product_balance_sync_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_refresh_lot_status_internal_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_reservation_close_v1(uuid,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_reservation_create_v1(uuid,uuid,uuid,uuid,numeric,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_reservations_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_stock_by_location_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_stock_movement_location_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_sync_aggregate_stock_v1(uuid,uuid,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('inventory_transfer_v1(uuid,uuid,uuid,uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('inventory_variant_balance_sync_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('link_weekly_dinner_expense_v1(uuid,uuid,uuid,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('list_audit_log_page_v1(uuid,timestamp with time zone,timestamp with time zone,text[],boolean,text,text,text,text,timestamp with time zone,bigint,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('list_audit_log_v2(uuid,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('log_asset_event_v1(uuid,uuid,text,text,text,jsonb)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('mark_all_notifications_read_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('mark_notification_read_v1(uuid,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('mark_weekly_officer_swap_applied_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('member_maintenance_timeline_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('member_motorcycle_timeline_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('member_patch_catalog_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('member_patch_timeline_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('member_position_timeline_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('member_status_timeline_trigger_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('member_timeline_append_v1(uuid,uuid,text,text,text,date,text,text,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('next_asset_codes_v1(uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('notify_financial_managers_v1(uuid,uuid,text,text,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('notify_financial_profile_v1(uuid,uuid,uuid,text,text,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('open_cash_session_v1(uuid,uuid,numeric)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('pay_fee_obligation(uuid,uuid,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('pay_fee_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('pay_reimbursement_v1(uuid,uuid,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('poll_guard_update_internal_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('poll_member_eligible_internal_v1(uuid,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('poll_option_guard_internal_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('poll_participation_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('poll_vote_count_internal_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('poll_vote_validate_internal_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('prepare_euromillions_month_v1(uuid,integer,integer)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres',false,true,false,false),
('prepare_member_fees_year_v1(uuid,integer)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres',false,true,false,false),
('preview_fee_payment_v1(uuid,uuid,numeric)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('process_euromillions_official_result_v1(uuid,date,text,integer[],integer[],jsonb,text)','postgres',true,'search_path=pg_catalog, public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('process_euromillions_result_v1(uuid,date,integer[],integer[])','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres',false,true,false,false),
('profile_has_club_permission(uuid,uuid,text)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('protect_member_milestone_dates_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('rebuild_weekly_officer_future_internal_v1(uuid,date)','postgres',true,'search_path=pg_catalog, public, pg_temp','postgres:EXECUTE:false:postgres',false,false,false,false),
('rebuild_weekly_officer_schedule_internal_v1(uuid,date,date)','postgres',true,'search_path=pg_catalog, public, pg_temp','postgres:EXECUTE:false:postgres',false,false,false,false),
('rebuild_weekly_officer_schedule_v1(uuid,integer)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres',false,true,false,false),
('record_shop_order_payment_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('refresh_fee_obligation_status_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('refresh_financial_transaction_primary_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('register_euromillions_draw_payment_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_euromillions_fine_payment_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_euromillions_manual_prize_v1(uuid,uuid,uuid,numeric,text,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_euromillions_month_fine_payment_v1(uuid,uuid,integer,integer,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres',false,true,false,false),
('register_euromillions_payment_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_euromillions_prize_receipt_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_fee_payment_batch_v1(uuid,uuid,numeric,text,date,text,jsonb,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_fee_payment_v1(uuid,uuid,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('register_push_device_v1(uuid,text,text,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reject_event_proposal_v1(uuid,text)','postgres',true,'search_path=""','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reorder_weekly_officer_v1(uuid,uuid[])','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('request_member_patch_v1(uuid,uuid,uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('request_weekly_officer_swap_v1(uuid,uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reserve_shop_variant_v1(uuid,uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('respond_weekly_officer_swap_v1(uuid,uuid,boolean,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('retry_financial_ocr_job_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_bar_sale_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_euromillions_draw_payment_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_euromillions_fine_payment_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_euromillions_month_payment_v1(uuid,uuid,integer,integer,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_euromillions_prize_receipt_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_fee_adjustment_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_fee_exemption_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_fee_payment_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('reverse_treasury_transaction_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('review_charge_payment_v1(uuid,uuid,text,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('review_reimbursement_v1(uuid,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('review_reported_fee_payment_v1(uuid,uuid,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('rollback_import_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_agenda_item_v1(uuid,uuid,text,text,text,timestamp with time zone,timestamp with time zone,boolean,text,text,text,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_bar_product_v3(uuid,uuid,text,text,text,text,text,text,text,numeric,numeric,numeric,jsonb)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_cost_center_v1(uuid,uuid,text,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_fee_obligation_v1(uuid,uuid,uuid,integer,integer,date,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_financial_ocr_review_v1(uuid,uuid,text,text,text,date,text,numeric,numeric,numeric,text,numeric,jsonb,jsonb)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_member_motorcycle_v1(uuid,uuid,uuid,text,text,integer,text,text,date,text,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_member_v1(uuid,uuid,integer,text,text,text,text,text,date,date,date,date,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_weekly_dinner_finance_v1(uuid,uuid,text,numeric,numeric,numeric,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_weekly_dinner_v1(uuid,uuid,date,uuid,text,text,text,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('save_weekly_officer_absence_v1(uuid,uuid,uuid,text,date,date,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_budget_status_v1(uuid,uuid,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_event_shift_member_status_v1(uuid,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_notification_preference_v1(uuid,text,boolean,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_primary_financial_transaction_document_v1(uuid,uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_weekly_dinner_closed_v1(uuid,uuid,boolean,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_weekly_dinner_financial_closed_v1(uuid,uuid,boolean)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('set_weekly_officer_member_v1(uuid,uuid,boolean,text,boolean,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('settle_treasury_obligation_v1(uuid,text,uuid,uuid,numeric,text,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('stage_import_rows_v1(uuid,uuid,jsonb)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('start_financial_document_ocr_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('submit_charge_proof_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('submit_event_proposal_v1(uuid,text,text,text,timestamp with time zone,timestamp with time zone,text)','postgres',true,'search_path=""','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('submit_reimbursement_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('sync_dinner_fee_setting_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('sync_financial_request_documents_v1()','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('treasury_account_balance_v1(uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('treasury_account_balances_v1(uuid)','postgres',true,'search_path=pg_catalog, public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_fee_settings_v1(uuid,integer,numeric,numeric)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_import_row_v1(uuid,uuid,uuid,jsonb)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_member_complete(uuid,uuid,integer,text,text,text,text,member_status,date,date,date,date,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_own_member_profile_v1(uuid,text,text,text,text,text,text,text,text,text,text,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_own_member_profile_v2(uuid,text,text,text,text,text,text,text,text,text,text,text,text)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('update_reimbursement_draft_v1(uuid,uuid,numeric,text)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('validate_treasury_transaction_v1()','postgres',true,'search_path=pg_catalog, public, pg_temp','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('weekly_dinner_finance_choices_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('weekly_dinner_finance_v1(uuid,uuid)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('weekly_dinner_financial_history_v1(uuid,integer)','postgres',true,'search_path=public','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false),
('weekly_officer_member_append_trigger_v1()','postgres',true,'search_path=pg_catalog, public, pg_temp','postgres:EXECUTE:false:postgres',false,false,false,false),
('weekly_officer_member_available_v1(uuid,uuid,date)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('weekly_officer_notify_member_v1(uuid,uuid,text,text,text,uuid)','postgres',true,'search_path=public','postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,false,true,false),
('withdraw_event_proposal_v1(uuid)','postgres',true,'search_path=pg_catalog, public, pg_temp','authenticated:EXECUTE:false:postgres,postgres:EXECUTE:false:postgres,service_role:EXECUTE:false:postgres',false,true,true,false)    ) AS expected(signature,owner,security_definer,proconfig,acl_normalized,anon_exec,auth_exec,service_exec,public_exec)
  LOOP
    expected_signatures:=array_append(expected_signatures,e.signature);
    f:=to_regprocedure('public.'||e.signature);
    IF f IS NULL THEN RAISE EXCEPTION 'R16_GUARD_FAIL missing protected function %',e.signature; END IF;
    SELECT p.proowner::regrole::text,p.prosecdef,COALESCE(array_to_string(p.proconfig,','),''),
      COALESCE((SELECT string_agg(CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE gr.rolname END||':'||a.privilege_type||':'||a.is_grantable||':'||grt.rolname,',' ORDER BY CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE gr.rolname END,a.privilege_type,a.is_grantable,grt.rolname)
        FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a LEFT JOIN pg_roles gr ON gr.oid=a.grantee JOIN pg_roles grt ON grt.oid=a.grantor),''),
      has_function_privilege('anon',p.oid,'EXECUTE'),has_function_privilege('authenticated',p.oid,'EXECUTE'),has_function_privilege('service_role',p.oid,'EXECUTE'),
      EXISTS(SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
    INTO actual_owner,actual_definer,actual_config,actual_acl,actual_anon,actual_auth,actual_service,actual_public FROM pg_proc p WHERE p.oid=f;
    IF actual_owner IS DISTINCT FROM e.owner OR actual_definer IS DISTINCT FROM e.security_definer OR actual_config IS DISTINCT FROM e.proconfig OR actual_acl IS DISTINCT FROM e.acl_normalized OR actual_anon IS DISTINCT FROM e.anon_exec OR actual_auth IS DISTINCT FROM e.auth_exec OR actual_service IS DISTINCT FROM e.service_exec OR actual_public IS DISTINCT FROM e.public_exec THEN
      RAISE EXCEPTION 'R16_GUARD_FAIL owner/search_path/ACL drift on % (owner %, config %, anon %, auth %, service %, public %)',e.signature,actual_owner,actual_config,actual_anon,actual_auth,actual_service,actual_public;
    END IF;
    expected_count:=expected_count+1;
  END LOOP;
  IF expected_count<>235 THEN RAISE EXCEPTION 'R16_GUARD_FAIL baseline size changed: %',expected_count; END IF;

  SELECT p.proname||'('||COALESCE((SELECT string_agg(format_type(x.typ,NULL),',' ORDER BY x.ord) FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY x(typ,ord)),'')||')' AS signature INTO bad
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND NOT (p.proname||'('||COALESCE((SELECT string_agg(format_type(x.typ,NULL),',' ORDER BY x.ord) FROM unnest(p.proargtypes::oid[]) WITH ORDINALITY x(typ,ord)),'')||')'=ANY(expected_signatures)) LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'R16_GUARD_FAIL new/unreviewed SECURITY DEFINER function %; pin its owner/path/ACL after review',bad.signature; END IF;
  SELECT p.oid::regprocedure AS signature INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND (has_function_privilege('anon',p.oid,'EXECUTE') OR EXISTS(SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')) LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'R16_GUARD_FAIL SECURITY DEFINER callable by anon/PUBLIC: %',bad.signature; END IF;

  SELECT p.oid::regprocedure AS signature,pol.polname AS policy_name,c.relname AS relation_name INTO bad
  FROM pg_proc p JOIN pg_depend d ON d.refclassid='pg_proc'::regclass AND d.refobjid=p.oid AND d.classid='pg_policy'::regclass
  JOIN pg_policy pol ON pol.oid=d.objid JOIN pg_class c ON c.oid=pol.polrelid
  WHERE ((0=ANY(pol.polroles) OR (SELECT oid FROM pg_roles WHERE rolname='authenticated')=ANY(pol.polroles)) AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))
     OR ((0=ANY(pol.polroles) OR (SELECT oid FROM pg_roles WHERE rolname='anon')=ANY(pol.polroles)) AND NOT has_function_privilege('anon',p.oid,'EXECUTE')) LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'R16_GUARD_FAIL RLS policy % on % calls % without EXECUTE for an applicable role',bad.policy_name,bad.relation_name,bad.signature; END IF;

  SELECT defaclacl INTO rel_acl FROM pg_default_acl WHERE defaclrole='postgres'::regrole AND defaclnamespace='public'::regnamespace AND defaclobjtype='r';
  SELECT defaclacl INTO seq_acl FROM pg_default_acl WHERE defaclrole='postgres'::regrole AND defaclnamespace='public'::regnamespace AND defaclobjtype='S';
  IF rel_acl IS NULL OR seq_acl IS NULL THEN RAISE EXCEPTION 'R16_GUARD_FAIL R14 relation/sequence default ACL missing'; END IF;
  IF EXISTS(SELECT 1 FROM aclexplode(rel_acl) a WHERE a.grantee NOT IN ('postgres'::regrole,'service_role'::regrole) OR a.is_grantable) OR (SELECT count(*) FROM aclexplode(rel_acl))<>16 THEN RAISE EXCEPTION 'R16_GUARD_FAIL unsafe or changed postgres/public table defaults'; END IF;
  IF EXISTS(SELECT 1 FROM aclexplode(seq_acl) a WHERE a.grantee NOT IN ('postgres'::regrole,'service_role'::regrole) OR a.is_grantable) OR (SELECT count(*) FROM aclexplode(seq_acl))<>6 THEN RAISE EXCEPTION 'R16_GUARD_FAIL unsafe or changed postgres/public sequence defaults'; END IF;
  IF NOT EXISTS(SELECT 1 FROM aclexplode(rel_acl) a WHERE a.grantee='service_role'::regrole AND a.privilege_type='INSERT') OR NOT EXISTS(SELECT 1 FROM aclexplode(seq_acl) a WHERE a.grantee='service_role'::regrole AND a.privilege_type='USAGE') THEN RAISE EXCEPTION 'R16_GUARD_FAIL service_role default grants changed'; END IF;
  IF EXISTS(SELECT 1 FROM pg_default_acl WHERE defaclrole='postgres'::regrole AND defaclnamespace=0) THEN RAISE EXCEPTION 'R16_GUARD_FAIL unexpected global defaults for postgres'; END IF;

  SELECT defaclacl INTO fn_acl FROM pg_default_acl WHERE defaclrole='postgres'::regrole AND defaclnamespace='public'::regnamespace AND defaclobjtype='f';
  IF fn_acl IS NULL OR (SELECT count(*) FROM aclexplode(fn_acl))<>4 OR EXISTS(SELECT 1 FROM aclexplode(fn_acl) a WHERE a.grantee NOT IN ('postgres'::regrole,'anon'::regrole,'authenticated'::regrole,'service_role'::regrole) OR a.privilege_type<>'EXECUTE' OR a.is_grantable) OR NOT EXISTS(SELECT 1 FROM aclexplode(acldefault('f','postgres'::regrole)) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'R16_GUARD_FAIL postgres/public function-default exception changed; re-review before proceeding'; END IF;
  RAISE NOTICE 'R16_GUARD_KNOWN_EXCEPTION postgres/public function defaults still confer PUBLIC/anon/authenticated EXECUTE; actual SECURITY DEFINER ACLs above must stay pinned and new functions fail this guard';
  RAISE NOTICE 'R16_GUARD_PASS protected functions %, RLS helper grants, R14 relation/sequence defaults',expected_count;
END
$r16_catalog_guard$;

COMMIT;




