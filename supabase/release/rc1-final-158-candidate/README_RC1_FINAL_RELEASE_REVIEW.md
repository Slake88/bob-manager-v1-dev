# RC1-FINAL release review — 2026-10-27

## Estado

**Validação integrada do pacote: PASS para instalação, catálogo, testes SQL simulados e backup/restauro; NO-GO para piloto até concluir Auth/PostgREST e Flutter com JWT/API reais.** A campanha de 27/10/2026 executou os 157 ficheiros na ordem de `RC1_FINAL_EXECUTION_ORDER.csv` numa sandbox limpa isolada. Os resultados detalhados, limitações, incidentes e hashes estão em `RELATORIO_CAMPANHA_INTEGRADA_RC1_FINAL_20261027.md` na pasta da campanha. As migrations históricas permanecem intactas.

## Estado Git preservado

Baseline local: `5a56ae549ce5e6a27c334e4dcfb322c2262b31eb`. `rc1-rebuild` e `codex/rc1-pilot-export-allowlist-asset-maintenance-off` apontam para o mesmo commit. As alterações locais existentes foram preservadas; não houve checkout, reset, stash, commit, push, merge ou deploy.

## Diferença exata: 154 históricos vs 153 do replay de auditoria

A árvore Git contém 154 migrations históricas. O pacote R17/R18 tem 153 entradas. A única migration histórica omitida do pacote é:

- `20260807223200_rc1_assets_phase2a_maintenance.sql` — cria `public.asset_maintenance_v1` como SECURITY DEFINER e concede EXECUTE a `authenticated`. A exclusão é necessária para manter a manutenção fora do piloto e cumprir a restrição permanente de não criar/invocar essa função. O ficheiro histórico permanece intacto.

A comparação de conteúdo normalizado também encontrou quatro migrations do pacote de auditoria que não são cópias textuais das versões históricas no repositório. A cópia da foundation no bundle foi reposta para bytes idênticos à migration histórica antes da campanha de 27/10; o histórico não foi alterado. O pacote de release mantém as restantes variantes auditadas com hashes próprias:

1. `1000_bob_manager_v1_complete.sql` — variante do pacote omite `current_profile_id()` que existe na migration histórica.
2. `1001_rc1_accounts_permissions.sql` — variante do pacote omite `account_balance()` e `transfer_between_accounts()` presentes na migration histórica.
3. `20260811192100_rc1_push_notifications_center.sql` — a versão histórica ativa `pg_net` e chama um endpoint externo de push; a variante do pacote omite a extensão e torna o despacho no-op.
4. `20260830175257_rc1_inventory_advanced_maintenance.sql` — a versão histórica ativa `pg_cron` e agenda um job; a variante do pacote omite a extensão e o agendamento.

As hashes de cada lado, ordem e disposição estão em `RC1_FINAL_MIGRATION_MANIFEST.csv`. A candidata EXECFIX1 foi validada contra o conjunto auditado de 153 ficheiros, não contra a execução direta das 154 migrations históricas intactas. A candidata recusa `pg_cron`, `pg_net` ou `asset_maintenance_v1` presentes. O pacote autónomo usa a ordem explícita do manifesto; não executar o diretório `supabase/migrations` como se fosse essa sequência. Não substituí nem editei migrations históricas.

## Artefactos no worktree

- `supabase/release/rc1-final/base_migrations/` — 153 cópias do pacote de auditoria, confirmadas contra os hashes R17/R18.
- `supabase/release/rc1-final/release_migrations/` — candidata EXECFIX1 e migrations piloto, R4 e R5, ordenadas como 154–157.
- `supabase/release/rc1-final/RC1_FINAL_EXECUTION_ORDER.csv` — sequência completa de 157 ficheiros, hashes e dependências.
- `supabase/release/rc1-final/MIGRATION_RC1_SECURITY_CONSOLIDATED_RC1_FINAL_CANDIDATE_EXECFIX1.sql` — cópia de revisão, SHA-256 `92E8989A51157CC5606D8A6B8EB4965E622E43D8B8FC0E8FF82C0BFA13FFDBB`; a mesma candidata está na ordem 154.
- `supabase/migrations/20261024190000_rc1_pilot_exports_and_asset_maintenance_disable.sql` — já existia no worktree, não foi alterada; código de piloto para 14 exports e bloqueio da manutenção.
- `supabase/migrations/20261027195243_rc1_bar_inventory_sales_integrity.sql` — já existia no worktree, não foi alterada; Bar/Inventário R4.
- `supabase/migrations/20261027210000_rc1_bar_sales_dml_guard.sql` — adicionada nesta tarefa a partir do artefacto R5 aprovado; SHA-256 `178CF9149EE4C71A3DFE627B5458E18D1BF138A196B746ACC43530FD673F0BC3`. Fonte original preservada na pasta R5 da auditoria. R5 obteve 30 PASS na R3; esta cópia não foi executada aqui.
- `RC1_FINAL_MIGRATION_MANIFEST.csv` — inventário das 154 migrations históricas, dos 153 artefactos do pacote e das migrações/candidata de release.
- `RC1_FINAL_CORRECTION_EVIDENCE.csv` — proveniência, dependências, hashes, evidência PASS e estado de integração por correção.
- `RC1_FINAL_COMPLETE_DIFF.patch` — diff integral contra o commit-base, incluindo aplicação, migrations e pacote autónomo; exclui apenas o próprio patch e o diff auxiliar anterior.

## Correções e evidências

A candidata EXECFIX1 reúne as correções aprovadas R3–R16 e a correção R10. A campanha de 27/10 executou 157/157 entradas. O teste R10 corrigido passou com claims PostgreSQL simuladas: autorização de saldo, isolamento entre clubes, bloqueio de perfis não autorizados/inativos e movimento legítimo. Isto não equivale a autenticação HTTP/JWT real.

A migration de piloto R12, Bar/Inventário R4 e R5 estão presentes na cadeia de release. A campanha limpa confirmou as policies/catálogo e executou testes SQL simulados de venda, stock, receita, reversão, cancelamento, bloqueio de escrita direta e concorrência. As chamadas Auth/PostgREST reais das exportações, Bar/Inventário e Tesouraria permanecem por executar devido a credenciais de DB incompatíveis no arranque local do GoTrue/PostgREST.

## Bloqueio remanescente para o piloto

Os serviços Auth e PostgREST não conseguiram autenticar-se na base de teste com as credenciais sintéticas configuradas (SQLSTATE 28P01 para `supabase_auth_admin` e `authenticator`). Não foram alteradas roles nem enfraquecida autenticação. Alinhar o mecanismo local de fornecimento das credenciais com o snapshot, depois executar os testes HTTP/JWT e os fluxos Flutter essenciais. Até estes passarem, manter **NO-GO**; o replay e testes SQL simulados não certificam a integração API nem o piloto.
