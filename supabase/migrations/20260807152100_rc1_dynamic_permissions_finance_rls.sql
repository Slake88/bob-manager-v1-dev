-- Tesouraria
DROP POLICY IF EXISTS treasury_accounts_select ON public.treasury_accounts;
CREATE POLICY treasury_accounts_select ON public.treasury_accounts FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'viewTreasury'));
DROP POLICY IF EXISTS treasury_accounts_insert ON public.treasury_accounts;
CREATE POLICY treasury_accounts_insert ON public.treasury_accounts FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageFinancialAccounts'));
DROP POLICY IF EXISTS treasury_accounts_update ON public.treasury_accounts;
CREATE POLICY treasury_accounts_update ON public.treasury_accounts FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageFinancialAccounts'))
WITH CHECK (public.has_club_permission(club_id,'manageFinancialAccounts'));
DROP POLICY IF EXISTS treasury_accounts_delete ON public.treasury_accounts;
CREATE POLICY treasury_accounts_delete ON public.treasury_accounts FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageFinancialAccounts'));

DROP POLICY IF EXISTS treasury_transactions_select ON public.treasury_transactions;
CREATE POLICY treasury_transactions_select ON public.treasury_transactions FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'viewTreasury'));
DROP POLICY IF EXISTS treasury_transactions_insert ON public.treasury_transactions;
CREATE POLICY treasury_transactions_insert ON public.treasury_transactions FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'createTreasuryMovement') and created_by=auth.uid());

DROP POLICY IF EXISTS cost_centers_select ON public.cost_centers;
CREATE POLICY cost_centers_select ON public.cost_centers FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'viewTreasury'));
DROP POLICY IF EXISTS cost_centers_insert ON public.cost_centers;
CREATE POLICY cost_centers_insert ON public.cost_centers FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageFinancialAccounts'));
DROP POLICY IF EXISTS cost_centers_update ON public.cost_centers;
CREATE POLICY cost_centers_update ON public.cost_centers FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageFinancialAccounts'))
WITH CHECK (public.has_club_permission(club_id,'manageFinancialAccounts'));
DROP POLICY IF EXISTS cost_centers_delete ON public.cost_centers;
CREATE POLICY cost_centers_delete ON public.cost_centers FOR DELETE TO authenticated
USING (public.has_club_permission(club_id,'manageFinancialAccounts'));

DROP POLICY IF EXISTS treasury_categories_read ON public.treasury_categories;
CREATE POLICY treasury_categories_read ON public.treasury_categories FOR SELECT TO authenticated
USING (public.has_club_permission(club_id,'viewTreasury'));
DROP POLICY IF EXISTS treasury_categories_manage ON public.treasury_categories;
CREATE POLICY treasury_categories_manage ON public.treasury_categories FOR ALL TO authenticated
USING (public.has_club_permission(club_id,'manageFinancialAccounts'))
WITH CHECK (public.has_club_permission(club_id,'manageFinancialAccounts'));

-- Quotas
DROP POLICY IF EXISTS fee_obligations_select ON public.fee_obligations;
CREATE POLICY fee_obligations_select ON public.fee_obligations FOR SELECT TO authenticated
USING (
  public.has_club_permission(club_id,'viewFees')
  OR EXISTS(select 1 from public.members m where m.id=member_id and m.profile_id=auth.uid())
);
DROP POLICY IF EXISTS fee_obligations_insert ON public.fee_obligations;
CREATE POLICY fee_obligations_insert ON public.fee_obligations FOR INSERT TO authenticated
WITH CHECK (public.has_club_permission(club_id,'manageFees'));
DROP POLICY IF EXISTS fee_obligations_update ON public.fee_obligations;
CREATE POLICY fee_obligations_update ON public.fee_obligations FOR UPDATE TO authenticated
USING (public.has_club_permission(club_id,'manageFees'))
WITH CHECK (public.has_club_permission(club_id,'manageFees'));
DROP POLICY IF EXISTS fee_payments_select ON public.fee_payments;
CREATE POLICY fee_payments_select ON public.fee_payments FOR SELECT TO authenticated
USING (
  public.has_club_permission(club_id,'viewFees')
  OR EXISTS(
    select 1 from public.fee_obligations o
    join public.members m on m.id=o.member_id
    where o.id=obligation_id and m.profile_id=auth.uid()
  )
);

-- Configurações funcionais usadas por Quotas e Euromilhões
DROP POLICY IF EXISTS club_settings_read ON public.club_settings;
CREATE POLICY club_settings_read ON public.club_settings FOR SELECT TO authenticated
USING (public.has_club_access(club_id));
DROP POLICY IF EXISTS club_settings_manage ON public.club_settings;
CREATE POLICY club_settings_manage ON public.club_settings FOR ALL TO authenticated
USING (
  public.has_club_permission(club_id,'manageSettings')
  or public.has_club_permission(club_id,'manageFees')
  or public.has_club_permission(club_id,'manageLottery')
)
WITH CHECK (
  public.has_club_permission(club_id,'manageSettings')
  or public.has_club_permission(club_id,'manageFees')
  or public.has_club_permission(club_id,'manageLottery')
);
