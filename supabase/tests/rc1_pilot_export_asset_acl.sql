-- Run after the RC1 consolidated security candidate and the pilot scope migration.
-- All checks below are catalog-only or use denied calls that write no rows.
BEGIN;

DO $catalog_assertions$
DECLARE
  v_fn oid;
  v_source text;
  v_expected text[] := ARRAY[
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
  ];
  v_path text;
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.begin_club_export_v1(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.begin_club_export_v1(uuid,text[],boolean,boolean,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Pilot begin RPC grants are incorrect';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.club_export_dataset_v1(uuid,uuid,text,integer,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.club_export_dataset_v1(uuid,uuid,text,integer,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Pilot dataset RPC grants are incorrect';
  END IF;

  IF has_function_privilege('authenticated', 'public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.begin_club_export_v1_pilot_internal(uuid,text[],boolean,boolean,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.club_export_dataset_v1_pilot_internal(uuid,uuid,text,integer,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'An internal export helper remains executable by an API role';
  END IF;

  SELECT p.oid, p.prosrc INTO v_fn, v_source
  FROM pg_proc p
  WHERE p.oid = 'public.club_export_dataset_v1(uuid,uuid,text,integer,integer)'::regprocedure;
  FOREACH v_path IN ARRAY v_expected LOOP
    IF position(v_path IN v_source) = 0 THEN
      RAISE EXCEPTION 'Pilot server allowlist is missing %', v_path;
    END IF;
  END LOOP;
  IF position('membros/membros.csv' IN v_source) > 0
     OR position('inventario/produtos.csv' IN v_source) > 0
     OR position('tesouraria/movimentos.csv' IN v_source) > 0 THEN
    RAISE EXCEPTION 'An unapproved dataset appears in the public pilot façade';
  END IF;

  IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon can execute pilot dataset RPC';
  END IF;

  IF public.club_export_file_access_v1('financial-documents', 'pilot-probe') IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Export file access is not disabled';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'asset_maintenance_v1'
      AND (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
        OR has_function_privilege('service_role', p.oid, 'EXECUTE')
      )
  ) THEN
    RAISE EXCEPTION 'asset_maintenance_v1 is still executable by an API role';
  END IF;
END
$catalog_assertions$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '22000000-0000-0000-0000-000000000099', true);
SELECT set_config('request.jwt.claims', '{"sub":"22000000-0000-0000-0000-000000000099","role":"authenticated"}', true);

DO $api_negative_calls$
DECLARE
  v_state text;
BEGIN
  BEGIN
    PERFORM public.begin_club_export_v1(
      '22000000-0000-0000-0000-000000000001', ARRAY['members'], false, false, 'pilot-test'
    );
    RAISE EXCEPTION 'Expected unsupported section denial';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state <> '42501' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.begin_club_export_v1(
      '22000000-0000-0000-0000-000000000001', ARRAY['fees'], false, true, 'pilot-test'
    );
    RAISE EXCEPTION 'Expected file export denial';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state <> '42501' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.begin_club_export_v1(
      '22000000-0000-0000-0000-000000000001', ARRAY['fees'], true, false, 'pilot-test'
    );
    RAISE EXCEPTION 'Expected sensitive export denial';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state <> '42501' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.club_export_dataset_v1(
      '22000000-0000-0000-0000-000000000001',
      '22000000-0000-0000-0000-000000000099',
      'membros/membros.csv', 0, 10
    );
    RAISE EXCEPTION 'Expected unapproved dataset denial';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    IF v_state <> '42501' THEN RAISE; END IF;
  END;
END
$api_negative_calls$;

RESET ROLE;
ROLLBACK;
