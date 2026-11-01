# BOB Manager RC1 — Validação final do bundle integrado

**Data:** 2026-10-27  
**Âmbito:** pré-validação estática do bundle RC1-FINAL; nenhum Docker, replay, migration, teste funcional, Auth/PostgREST ou backup/restauro foi executado nesta ronda.  
**Resultado:** **BLOCKED antes da criação da sandbox.** A base auditada reduz a cobertura dos triggers de auditoria em tabelas financeiras, de permissões e dados sensíveis. A instrução do utilizador exige interromper a aplicação perante incompatibilidade concreta. Não criei recursos nem alterei o bundle SQL.

## Fase 1 — compatibilidade estática

| Verificação | Resultado | Evidência |
|---|---|---|
| 157 ficheiros, ordem e SHA-256 | PASS | `RC1_FINAL_EXECUTION_ORDER.csv`: 157 linhas, 157 caminhos e ordens únicos; todos os ficheiros existem e os hashes coincidem. SHA-256 do CSV: `72E9E33DAD3139C6D16A101DBABF5E37FB539C5C622036517F4E9054C4BCC7D1`. |
| Funções omitidas (`current_profile_id`, `account_balance`, `transfer_between_accounts`) | PASS estático limitado | As definições existem nas migrations históricas 1000/1001 e faltam no bundle-base. Busca de call sites Dart não encontrou chamadas. A aplicação usa os RPCs atuais `treasury_account_balances_v1` e operações `treasury_*`. Não foi testada a superfície RPC para consumidores externos nem substituído o teste por conclusão de segurança. |
| Foundation de auditoria | **FAIL — bloqueio concreto** | A variante `20260811160313_rc1_global_audit_foundation.sql` contém uma lista de exclusão de 50 tabelas e salta, para essas tabelas, a criação de `trg_audit_stamp_v1` e `trg_audit_capture_v1`. A lista inclui `financial_accounts`, `financial_transactions`, `financial_categories`, `member_emergency_data`, `member_fee_assignments`, `permission_change_log`, `role_permissions`, `roles`, `inventory_counts` e `stock_locations`. A versão histórica não tem esse `if` de exclusão e cria os triggers no loop. Há, portanto, redução real de cobertura deste mecanismo de auditoria; não confirmei se triggers diferentes cobrem cada tabela. |
| `pg_net`, `pg_cron`, `asset_maintenance_v1` na base de 153 ficheiros | PASS estático | A varredura do diretório `base_migrations` encontrou zero instruções de criação/agendamento dessas extensões ou função. A migration histórica de manutenção está explicitamente excluída. |
| Compatibilidade com Supabase CLI normal | BLOCKED/limitação de processo | O bundle fica em `supabase/release/rc1-final`, fora de `supabase/migrations`; a CLI não o descobre automaticamente. A ordem CSV exige um executor explícito. Executar as migrations históricas diretamente inclui 154 ficheiros e não equivale ao bundle. A campanha R17/R18 anterior utilizou o conjunto auditado de 153. |

### Funções omitidas

A migration histórica 1000 define `current_profile_id()`. A 1001 define `account_balance()` e `transfer_between_accounts()`; a segunda chama a primeira. A versão auditada omite as três por não estarem presentes no estado capturado. Na pesquisa local não encontrei consumidores Dart. Isso reduz o risco de regressão na aplicação Flutter atual, mas não comprova que nenhum consumidor externo use essas RPCs; não foi encontrado nem testado contrato externo no âmbito permitido.

### Foundation de auditoria — causa e correção mínima

A variante de replay documenta que omite “baseline-scan extras”, mas a lista efetiva contém 50 nomes. Não é uma alteração meramente cosmética: os nomes incluem tabelas que contêm saldos, transações, permissões, dados de emergência e inventário. Sem prova de cobertura equivalente por outros triggers, não posso declarar que a alteração preserva os registos essenciais.

**Correção mínima proposta:** no pacote de release, substituir apenas a cópia da migration `20260811160313_rc1_global_audit_foundation.sql` pela versão histórica intacta, preservando o ficheiro histórico no repositório; recalcular hash/manifesto e rever os triggers esperados nessas 50 tabelas. Depois, executar a campanha limpa e testar apenas o efeito de auditoria adicional e os fluxos financeiros/Bar afetados. Não alterei a cópia nesta tarefa porque a ordem solicitada era interromper a aplicação perante incompatibilidade real.

## Fases 2–4 — não executadas

| Área | Estado | Motivo |
|---|---|---|
| Nova sandbox e execução dos 157 ficheiros | BLOCKED | Parado na Fase 1, antes de Docker. Nenhum recurso novo foi criado. |
| Tesouraria R10, Agenda, exports, Património e Bar/Inventário | NOT TESTED nesta ronda | Não houve instalação integrada. Evidências anteriores mantêm o seu âmbito: não certificam esta composição corrigida. |
| Backup e restauro independente | NOT TESTED | Nenhuma base integrada foi criada; não há dados R10/R4/R5 deste bundle para comparar nem duração de recuperação medida. |
| Recursos anteriores/R3 | NOT TOUCHED | Não foram consultados nem alterados. Não acedi a staging ou produção. |

## Evidência anteriormente válida, sem repetição

- R17/R18: 153/153 migrations-base PASS e hashes do conjunto auditado.
- Campanha RC1-FINAL: candidata EXECFIX1 aplicada e catálogo pós-candidata PASS; teste comportamental R10 parou na pré-condição da fixture (`override actor precondition failed`), antes dos casos financeiros.
- Exportações: R2 HTTP reportou 14 permitidas e 58 recusadas; manutenção HTTP 404.
- Bar/Inventário R4 e R5: testes HTTP locais previamente aprovados, R5 com 30 PASS. Não foram reexecutados nem transferidos para esta composição.

## Estado Git e preservação

O bundle e as alterações anteriores no worktree foram preservados. Não foram alteradas migrations históricas, código da aplicação, bases de dados, ambientes Docker, R3, backups, staging ou produção. Não houve commit, push, merge ou deploy.

**Decisão:** RC1-FINAL permanece **BLOCKED**. A próxima ação mínima é corrigir apenas a variante da foundation, atualizar hashes e rever cobertura de auditoria; só depois repetir a validação integrada finita, com a fixture R10 válida. Nenhum teste das fases 2–4 pode ser marcado PASS nesta ronda.
