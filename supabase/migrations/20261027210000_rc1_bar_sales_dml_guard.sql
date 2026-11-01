-- BOB Manager RC1 — R5 focused Bar sales write boundary
-- Evidence source: R5 HTTP reproduction on isolated local R3, 2026-10-27.
-- Scope: public.bar_sales, public.bar_sale_items, public.bar_operations only.
-- Keeps the existing authenticated PATCH draft -> cancelled path; all other
-- application writes continue through the existing owner-controlled RPCs.
BEGIN;

-- Direct table DML is not used by the real-mode sale/item/operation paths.
-- `bar_sales` UPDATE remains for the existing cancelDraft() PATCH only.
REVOKE INSERT, DELETE ON TABLE public.bar_sales FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.bar_sale_items FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON TABLE public.bar_operations FROM authenticated;
-- anon had explicit SELECT/INSERT/UPDATE/DELETE table rights on bar_operations;
-- there is no anonymous Bar workflow or matching anonymous row policy.
REVOKE ALL PRIVILEGES ON TABLE public.bar_operations FROM anon;

-- RLS defense in depth: later permissive policies/grants cannot reopen these
-- direct write paths for client roles. PostgreSQL combines restrictive policies
-- with permissive policies using AND.
DROP POLICY IF EXISTS r5_bar_sales_insert_rpc_only ON public.bar_sales;
CREATE POLICY r5_bar_sales_insert_rpc_only
  ON public.bar_sales AS RESTRICTIVE FOR INSERT TO anon, authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS r5_bar_sales_update_cancel_draft_only ON public.bar_sales;
CREATE POLICY r5_bar_sales_update_cancel_draft_only
  ON public.bar_sales AS RESTRICTIVE FOR UPDATE TO anon, authenticated
  USING (status = 'draft')
  WITH CHECK (status = 'cancelled');

DROP POLICY IF EXISTS r5_bar_sales_delete_rpc_only ON public.bar_sales;
CREATE POLICY r5_bar_sales_delete_rpc_only
  ON public.bar_sales AS RESTRICTIVE FOR DELETE TO anon, authenticated
  USING (false);

DROP POLICY IF EXISTS r5_bar_sale_items_insert_rpc_only ON public.bar_sale_items;
CREATE POLICY r5_bar_sale_items_insert_rpc_only
  ON public.bar_sale_items AS RESTRICTIVE FOR INSERT TO anon, authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS r5_bar_sale_items_update_rpc_only ON public.bar_sale_items;
CREATE POLICY r5_bar_sale_items_update_rpc_only
  ON public.bar_sale_items AS RESTRICTIVE FOR UPDATE TO anon, authenticated
  USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS r5_bar_sale_items_delete_rpc_only ON public.bar_sale_items;
CREATE POLICY r5_bar_sale_items_delete_rpc_only
  ON public.bar_sale_items AS RESTRICTIVE FOR DELETE TO anon, authenticated
  USING (false);

DROP POLICY IF EXISTS r5_bar_operations_insert_rpc_only ON public.bar_operations;
CREATE POLICY r5_bar_operations_insert_rpc_only
  ON public.bar_operations AS RESTRICTIVE FOR INSERT TO anon, authenticated
  WITH CHECK (false);

DROP POLICY IF EXISTS r5_bar_operations_update_rpc_only ON public.bar_operations;
CREATE POLICY r5_bar_operations_update_rpc_only
  ON public.bar_operations AS RESTRICTIVE FOR UPDATE TO anon, authenticated
  USING (false) WITH CHECK (false);

DROP POLICY IF EXISTS r5_bar_operations_delete_rpc_only ON public.bar_operations;
CREATE POLICY r5_bar_operations_delete_rpc_only
  ON public.bar_operations AS RESTRICTIVE FOR DELETE TO anon, authenticated
  USING (false);

-- Preserve the current real client cancelDraft() operation, but make its only
-- permitted direct UPDATE exactly draft -> cancelled with no business-field
-- edits, club reassignment, or attribution forgery. SECDEF RPC writes execute
-- as their trusted owner and retain the established sale/reversal workflows.
CREATE OR REPLACE FUNCTION bob_dinner_private.guard_authenticated_bar_sale_draft_cancel()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog
AS $r5$
BEGIN
  IF current_user = 'anon' THEN
    RAISE EXCEPTION 'A sessão é necessária para alterar uma venda.'
      USING ERRCODE = '42501';
  END IF;

  IF current_user <> 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF OLD.status IS DISTINCT FROM 'draft'
     OR NEW.status IS DISTINCT FROM 'cancelled' THEN
    RAISE EXCEPTION 'A escrita direta só pode cancelar um rascunho.'
      USING ERRCODE = '42501';
  END IF;

  IF (pg_catalog.to_jsonb(NEW) - ARRAY['status','updated_by','updated_at'])
       IS DISTINCT FROM
     (pg_catalog.to_jsonb(OLD) - ARRAY['status','updated_by','updated_at']) THEN
    RAISE EXCEPTION 'O cancelamento direto não pode alterar os dados da venda.'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.club_id IS DISTINCT FROM OLD.club_id
     OR NEW.updated_by IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'O clube e o autor do rascunho não podem ser alterados.'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$r5$;

REVOKE ALL ON FUNCTION bob_dinner_private.guard_authenticated_bar_sale_draft_cancel()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_r5_bar_sales_draft_cancel_guard ON public.bar_sales;
CREATE TRIGGER trg_r5_bar_sales_draft_cancel_guard
  BEFORE UPDATE ON public.bar_sales
  FOR EACH ROW
  EXECUTE FUNCTION bob_dinner_private.guard_authenticated_bar_sale_draft_cancel();

COMMIT;
