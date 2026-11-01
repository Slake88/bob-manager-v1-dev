-- RC1 internal pilot: allow only the 14 R13-tested data exports.
-- File downloads and sensitive-export modes are intentionally disabled.
-- This migration is intended to run after the consolidated RC1-FINAL security candidate.

DO $preflight$
DECLARE
  v_begin_md5 text;
  v_dataset_md5 text;
BEGIN
  IF session_user <> 'postgres' OR current_user <> 'postgres' THEN
    RAISE EXCEPTION 'RC1 pilot export migration requires the verified postgres migration identity';
  END IF;

  IF to_regprocedure('public.begin_club_export_v1(uuid,text[],boolean,boolean,text)') IS NULL
     OR to_regprocedure('public.club_export_dataset_v1(uuid,uuid,text,integer,integer)') IS NULL
     OR to_regprocedure('public.club_export_file_access_v1(text,text)') IS NULL THEN
    RAISE EXCEPTION 'Reviewed R12 export functions are missing; refusing partial pilot setup';
  END IF;

  SELECT md5(p.prosrc) INTO v_begin_md5
  FROM pg_proc p WHERE p.oid = 'public.begin_club_export_v1(uuid,text[],boolean,boolean,text)'::regprocedure;
  SELECT md5(p.prosrc) INTO v_dataset_md5
  FROM pg_proc p WHERE p.oid = 'public.club_export_dataset_v1(uuid,uuid,text,integer,integer)'::regprocedure;

  IF v_begin_md5 <> '95598577549f54987493101cf0ca80c3'
     OR v_dataset_md5 <> '11c1ec04f9abfbabc9bb164f2fa95664' THEN
    RAISE EXCEPTION 'R12 export function definitions differ from the reviewed RC1-FINAL source';
  END IF;

  IF to_regprocedure('public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)') IS NOT NULL
     OR to_regprocedure('public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)') IS NOT NULL THEN
    RAISE EXCEPTION 'Pilot internal export function already exists; refusing ambiguous rename';
  END IF;
END
$preflight$;

ALTER FUNCTION public.begin_club_export_v1(uuid,text[],boolean,boolean,text)
  RENAME TO begin_club_export_v1_pilot_internal;
ALTER FUNCTION public.club_export_dataset_v1(uuid,uuid,text,integer,integer)
  RENAME TO club_export_dataset_v1_pilot_internal;

-- Internal helpers are callable only by their owner through the public pilot façade.
REVOKE ALL ON FUNCTION public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.begin_club_export_v1(
  target_club uuid,
  p_modules text[],
  p_include_sensitive boolean DEFAULT false,
  p_include_files boolean DEFAULT false,
  p_manifest_version text DEFAULT 'bob-export-v1'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $pilot$
DECLARE
  v_modules text[];
  v_allowed CONSTANT text[] := ARRAY['financial','fees','lottery']::text[];
BEGIN
  SELECT COALESCE(
    array_agg(DISTINCT btrim(requested.module_key) ORDER BY btrim(requested.module_key)),
    ARRAY[]::text[]
  )
  INTO v_modules
  FROM unnest(COALESCE(p_modules, ARRAY[]::text[])) AS requested(module_key)
  WHERE NULLIF(btrim(requested.module_key), '') IS NOT NULL;

  IF cardinality(v_modules) = 0 THEN
    RAISE EXCEPTION 'Seleciona uma das áreas de exportação disponíveis no piloto.' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM unnest(v_modules) AS requested(module_key)
    WHERE NOT (requested.module_key = ANY(v_allowed))
  ) THEN
    RAISE EXCEPTION 'A área de exportação não está disponível no piloto.' USING ERRCODE = '42501';
  END IF;

  IF COALESCE(p_include_sensitive, false) OR COALESCE(p_include_files, false) THEN
    RAISE EXCEPTION 'Exportação de dados sensíveis ou ficheiros está desativada no piloto.' USING ERRCODE = '42501';
  END IF;

  RETURN public.begin_club_export_v1_pilot_internal(
    target_club, v_modules, false, false, p_manifest_version
  );
END
$pilot$;

CREATE FUNCTION public.club_export_dataset_v1(
  target_club uuid,
  p_export uuid,
  p_dataset text,
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 1000
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $pilot$
DECLARE
  v_allowed CONSTANT text[] := ARRAY[
    'financeiro/pedidos.csv',
    'financeiro/pedidos_anexos.csv',
    'financeiro/documentos_movimentos.csv',
    'quotas/planos.csv',
    'quotas/obrigacoes.csv',
    'quotas/pagamentos.csv',
    'euromilhoes/participantes.csv',
    'euromilhoes/sorteios.csv',
    'euromilhoes/chaves.csv',
    'euromilhoes/participacoes.csv',
    'euromilhoes/resultados.csv',
    'euromilhoes/cobrancas.csv',
    'euromilhoes/multas.csv',
    'euromilhoes/premios.csv'
  ]::text[];
BEGIN
  IF p_dataset IS NULL OR NOT (p_dataset = ANY(v_allowed)) THEN
    RAISE EXCEPTION 'Dataset de exportação não disponível no piloto.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.club_export_dataset_v1_pilot_internal(
    target_club, p_export, p_dataset, p_offset, p_limit
  );
END
$pilot$;

REVOKE ALL ON FUNCTION public.begin_club_export_v1(uuid,text[],boolean,boolean,text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.begin_club_export_v1(uuid,text[],boolean,boolean,text)
  TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.club_export_dataset_v1(uuid,uuid,text,integer,integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.club_export_dataset_v1(uuid,uuid,text,integer,integer)
  TO authenticated, service_role;

-- The storage policy can continue invoking this helper, but it authorizes no
-- export files in the pilot because file export has not been behaviorally tested.
CREATE OR REPLACE FUNCTION public.club_export_file_access_v1(p_bucket text, p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $pilot$
  SELECT false
$pilot$;
REVOKE ALL ON FUNCTION public.club_export_file_access_v1(text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.club_export_file_access_v1(text,text) TO authenticated, service_role;

-- Keep any historical asset_maintenance_v1 definition intact, but prevent all
-- API client and service roles from executing any overload. No invocation/drop.
DO $disable_asset_maintenance$
DECLARE
  v_function oid;
BEGIN
  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'asset_maintenance_v1'
  LOOP
    EXECUTE format(
      'REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      v_function::regprocedure
    );
  END LOOP;
END
$disable_asset_maintenance$;

DO $postflight$
DECLARE
  v_function oid;
BEGIN
  IF has_function_privilege('anon', 'public.begin_club_export_v1(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.club_export_dataset_v1(uuid,uuid,text,integer,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon retains an export EXECUTE privilege';
  END IF;

  IF has_function_privilege('authenticated', 'public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'A client/service API role can execute an internal export function';
  END IF;

  IF has_function_privilege('authenticated', 'public.club_export_file_access_v1(text,text)', 'EXECUTE')
     AND public.club_export_file_access_v1('financial-documents', 'pilot-probe') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Export file helper is not closed for the pilot';
  END IF;

  FOR v_function IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'asset_maintenance_v1'
  LOOP
    IF has_function_privilege('anon', v_function, 'EXECUTE')
       OR has_function_privilege('authenticated', v_function, 'EXECUTE')
       OR has_function_privilege('service_role', v_function, 'EXECUTE') THEN
      RAISE EXCEPTION 'asset_maintenance_v1 remains executable by an API role';
    END IF;
  END LOOP;
END
$postflight$;
