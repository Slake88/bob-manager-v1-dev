# Fecho high-risk — 15/10/2026

373/373 resolvidos: 371 corrigidos e 2 equivalentes; **0 high-risk pendentes**. Branch rc1-rebuild, HEAD de53a2945d67653a8f41cb5939175ebaa9d0e6de. Sem commit/push/deploy ou acesso a produção.

## 18 triggers omitidos na reconstrução

| Tabela | Trigger | Timing/eventos | Função |
|---|---|---|---|
| document_access_log | trg_audit_capture_v1 | AFTER INSERT OR DELETE OR UPDATE | audit_capture_row_v1() |
| document_access_log | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| document_approvals | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| document_links | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| document_ocr | trg_audit_capture_v1 | AFTER INSERT OR DELETE OR UPDATE | audit_capture_row_v1() |
| document_ocr | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| document_versions | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| event_program | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| event_shift_members | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| event_task_assignees | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| member_status_history | trg_audit_capture_v1 | AFTER INSERT OR DELETE OR UPDATE | audit_capture_row_v1() |
| member_status_history | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| member_timeline | trg_audit_capture_v1 | AFTER INSERT OR DELETE OR UPDATE | audit_capture_row_v1() |
| member_timeline | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| product_variants | trg_audit_capture_v1 | AFTER INSERT OR DELETE OR UPDATE | audit_capture_row_v1() |
| product_variants | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| stock_lots | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |
| stock_reservations | trg_audit_stamp_v1 | BEFORE INSERT OR UPDATE | audit_stamp_row_v1() |

Origem comum: instalação automática em 20260811160313_rc1_global_audit_foundation.sql, sobre tabelas antecipadas pela 1000. A mesma migration histórica omite exatamente estes 18 triggers após o scan; as instalações canónicas posteriores continuam ativas. As funções partilhadas não foram removidas. Snapshot esperado: ausência destes triggers. O JSON final contém, por trigger, fontes históricas, consumidores versionados, dependências da função e efeitos antes/depois de UPDATE. Não há chamadas diretas a triggers: a execução é acionada por DML; os writers e cadeias remanescentes foram exercitados pelos harnesses.

Foram preservados 390 triggers anteriores, comparando definição, função/corpo (normalizando apenas CRLF/LF), enabled, configuração e SECURITY DEFINER. Recriação temporária dos extras em savepoints reproduz o efeito antigo; rollback confirma a ausência final. A remoção de stamp deixa de sobrescrever autores/carimbos; a remoção de capture elimina a auditoria adicional observada, sem afetar os captures canónicos. A fixture de permissões document_versions agora envia auth.uid() como created_by: antes enviava um autor fixo e dependia do stamp para o corrigir. Nenhuma policy foi enfraquecida.

## Ledger de stock

Omitida da 1000 a FK extra fk_stock_movements_variant_id: product_variant_id → product_variants(id) ON DELETE CASCADE. Não foi criada uma substituição: o snapshot não tem esta FK legacy. O campo legacy mantém o UUID mesmo após DELETE e pode ficar sem alvo, tal como no snapshot. A FK canónica stock_movements_variant_id_fkey, sobre variant_id, continua ON DELETE SET NULL: o movimento sobrevive e a ligação fica NULL. Ambas as variantes têm regressões reais de DELETE com triggers ativos e rollback. BEFORE conservado em PHASE_HIGH_RISK_FINAL_CLOSURE_BEFORE.json.

## Validação

Replay 154/154 com adaptadores; 362 verificações específicas; 19 verificações de ausência; 390 triggers preservados; 16 harnesses SQL verdes; analyze sem issues; Flutter 269 passed/15 skips; contratos 19 passed/2 skips; Web release local; git diff --check verde. Skips não contam como executados. Falhas iniciais de argumentos dos dois harnesses incrementais foram corrigidas fornecendo o catálogo local; a fixture de autor foi corrigida conforme descrito.

## Readiness

Pronto para revisão e commit/push do conjunto local documentado; nenhuma dessas ações foi executada. Este resultado fecha os 373 high-risk, sem certificar prontidão de rollout produtivo nem reclassificar os 275 F médios. Limites: 275 medium F remain in prior reconciliation classification; this closure does not reclassify them. 39 historical applied-body provenance gaps remain; matching names/versions do not prove remote SQL body identity. Local PostgreSQL adapters do not validate GoTrue, PostgREST HTTP/cache, Storage, Edge/providers, native pg_net/pg_cron or external consumers. Captured production snapshot only; no production freshness or rollout preflight performed.
