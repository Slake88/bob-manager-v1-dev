-- Run with psql against a disposable local RC1 test copy:
-- psql -v ON_ERROR_STOP=1 -v user_a=<uuid> -v user_b=<uuid> -f this_file.sql
-- Both UUIDs must be distinct existing synthetic auth.users IDs.
\set QUIET 1
\if :{?user_a}
\else
  \echo 'FAIL: supply two existing synthetic Auth user IDs as user_a and user_b'
  \quit 2
\endif
\if :{?user_b}
\else
  \echo 'FAIL: supply two existing synthetic Auth user IDs as user_a and user_b'
  \quit 2
\endif
BEGIN;
SELECT set_config('test.user_a', :'user_a', true);
SELECT set_config('test.user_b', :'user_b', true);
DO $$
BEGIN
  IF current_setting('test.user_a') = current_setting('test.user_b') THEN
    RAISE EXCEPTION 'FAIL: test users must be distinct';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = current_setting('test.user_a')::uuid)
     OR NOT EXISTS (SELECT 1 FROM auth.users WHERE id = current_setting('test.user_b')::uuid) THEN
    RAISE EXCEPTION 'FAIL: both test IDs must exist in local Auth';
  END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'user_a', true);
INSERT INTO public.user_module_preferences(user_id, module_order)
VALUES (:'user_a'::uuid, '["bar","dashboard"]'::jsonb)
ON CONFLICT (user_id) DO UPDATE SET module_order = EXCLUDED.module_order;
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM public.user_module_preferences
  WHERE user_id = auth.uid() AND module_order->>0 = 'bar';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL own-row read/insert for A'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub', :'user_b', true);
DO $$
DECLARE n integer; affected integer;
BEGIN
  SELECT count(*) INTO n FROM public.user_module_preferences
  WHERE user_id <> auth.uid();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL cross-user read'; END IF;
  UPDATE public.user_module_preferences SET module_order = '["treasury"]'::jsonb
  WHERE user_id <> auth.uid();
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'FAIL cross-user update'; END IF;
  DELETE FROM public.user_module_preferences WHERE user_id <> auth.uid();
  GET DIAGNOSTICS affected = ROW_COUNT;
  IF affected <> 0 THEN RAISE EXCEPTION 'FAIL cross-user delete'; END IF;
  BEGIN
    INSERT INTO public.user_module_preferences(user_id, module_order)
    VALUES (current_setting('test.user_a')::uuid, '["treasury"]'::jsonb);
    RAISE EXCEPTION 'FAIL cross-user insert was accepted';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;
SELECT set_config('request.jwt.claim.sub', :'user_b', true);
INSERT INTO public.user_module_preferences(user_id, module_order)
VALUES (:'user_b'::uuid, '["treasury","bar"]'::jsonb)
ON CONFLICT (user_id) DO UPDATE SET module_order = EXCLUDED.module_order;
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM public.user_module_preferences
  WHERE user_id = auth.uid() AND module_order->>0 = 'treasury';
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL own-row read/insert for B'; END IF;
END $$;
RESET ROLE;
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.user_module_preferences;
    RAISE EXCEPTION 'FAIL: anon unexpectedly has table access';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;
ROLLBACK;
\echo 'PASS: RLS own-row isolation; all synthetic rows rolled back'
