# Commit 5 — Auditoria Global

Fundação de auditoria transversal do BOB Manager.

- Todas as tabelas de domínio com `club_id` recebem `created_at`, `created_by`, `updated_at`, `updated_by`.
- Os valores são carimbados no servidor por triggers, não pela interface.
- `audit_log` fica append-only para clientes autenticados.
- O histórico grava INSERT/UPDATE/DELETE e o utilizador autenticado.
- Dados pessoais sensíveis selecionados são removidos das cópias de auditoria.
- A base guarda `timestamptz`; apresentação oficial usa `Europe/Lisbon`.
- Registos históricos sem metadados não são falsamente preenchidos com a data da migração.

A migration foi aplicada ao projeto Supabase Blue On Black em 2026-08-11 com a versão remota `20260811160313`.
