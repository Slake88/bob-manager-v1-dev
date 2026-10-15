-- Commit 11 — restringe jobs OCR a perfis que podem efetivamente executar/rever o fluxo.

drop policy if exists financial_ocr_jobs_select on public.financial_ocr_jobs;
create policy financial_ocr_jobs_select on public.financial_ocr_jobs
for select to authenticated using (
  case
    when source_kind='bar_import' then
      public.has_club_permission(club_id,'manageBar')
    else
      public.has_club_permission(club_id,'createTreasuryMovement')
      or public.has_club_permission(club_id,'approveExpenseRequests')
  end
);

-- Perfis apenas de leitura continuam a consultar o documento financeiro original,
-- mas não conseguem iniciar/consultar jobs que possam consumir o serviço OCR.
