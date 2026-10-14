# Fase 2C.7 — validação de referências entre clubes

14/10/2026, Europe/Lisbon. Candidata exclusivamente local no branch `rc1-rebuild`, base `9c893b6c181415487d3851e8bacaef8f3ebc22cb` (2C.6). Sem commit, push, deploy ou consultas/escritas em produção nesta tarefa.

## Parecer

Pronta para revisão e autorização de commit/push. As cinco RPCs impedem as oito associações UUID cross-club identificadas, preservando os contratos e permissões existentes. Todos os checks locais pedidos passaram. Isto não declara readiness de deploy: o catálogo efetivo de produção não foi consultado nesta fase.

## Inventário e callers reais

| RPC | Última definição versionada anterior | Caller de aplicação encontrado | Validação acrescentada |
| --- | --- | --- | --- |
| `create_treasury_transaction` | `20260807152300_rc1_dynamic_permissions_rpc_core.sql` | Nenhum em Flutter/Edge; legacy mantida | `category` → `treasury_categories`, `cost_center` → `cost_centers`, `event_ref` → `events` |
| `create_member_with_position` | `20260807152300_rc1_dynamic_permissions_rpc_core.sql` | Nenhum em Flutter/Edge; legacy mantida | `position_ref` → `club_positions` |
| `asset_loan_v1` | `20260807223100_rc1_assets_phase2a_loans.sql` | `assets_operations_repository.dart:103`, método `loan`; `assets_phase2_screen.dart:64` e `assets_qr_screen.dart:118` | `p_member` → `members`, `p_event` → `events` |
| `log_asset_event_v1` | `20260807202000_rc1_assets_phase1.sql` | `assets_repository.dart:179`, método `logEvent`; criação/edição da ficha e fotografia principal no mesmo repository | `p_asset` → `inventory_assets` |
| `create_shop_order_v1` | `20260807174500_rc1_shop_variants_orders_photos.sql` | `shop_repository.dart:249`, método `createOrder`; `shop_screen.dart:368` | `p_member` → `members` |

Pesquisa nas migrations, Flutter e Edge Functions do checkout. Não foram encontrados callers SQL internos das cinco RPCs. Documentação e testes não contam como callers de negócio; consumidores externos não versionados não foram verificados. As cinco definições do catálogo sem dados guardado têm os mesmos contratos e comportamento relevante; a regressão parte desse catálogo e aplica as migrations 2C.1–2C.6.

## Constraints e triggers

O inventário do catálogo foi restaurado com constraints e triggers reais, sem os desativar para os testes. Nas tabelas `treasury_transactions`, `member_positions`, `asset_loans`, `asset_events` e `shop_orders`, as FKs das referências alvo verificam apenas o UUID, não `(club_id,id)`. Triggers de auditoria/autoria, atividade e balanço não fecham essas oito associações. RLS das tabelas de destino verifica permissões no clube da linha; SECURITY DEFINER exige verificação explícita das referências.

`treasury_transactions_balance_guard` executa `validate_treasury_transaction_v1`: já verifica conta de origem e destino ativas e do clube, tipo de transferência, valor e saldo. Não se duplicou esta validação. Os testes continuam a rejeitar contas de outro clube. `asset_loan_v1` já verifica o bem ativo, clube, bloqueio FOR UPDATE, empréstimo em curso e tipo de destinatário. `create_shop_order_v1` já verifica produto do clube/loja/ativo e variante ativa do produto. Estes checks ficam preservados, incluindo as suas mensagens anteriores.

## Migration e comportamento preservado

`20261014133347_rc1_cross_club_references.sql` foi criada pelo CLI com `migration new`; contém apenas DDL transacional e preflight, sem backfill, DML de negócio ou chamadas de RPC. Usa CREATE OR REPLACE, conserva nomes e ordem dos parâmetros, tipos, defaults, retorno UUID, SECURITY DEFINER, owners, OIDs, ACLs, volatilidade, strictness e parallelism. Todas as cinco funções fixam `search_path = pg_catalog, public, pg_temp`.

O preflight exige que as cinco assinaturas já existam e que PUBLIC/anon não tenham EXECUTE efetivo. Caso contrário, aborta antes de substituir qualquer função. Não cria endpoints adicionais e não acrescenta grants. Authenticated e service_role conservam exatamente as ACLs anteriores; o utilizador continua a precisar das permissões de clube dentro da função. Os erros de autorização anteriores são comparados exatamente antes/depois para todos os 35 casos e para identidade ausente/utilizador sem permissão.

Cada referência nova preenchida é consultada por UUID e clube, após a autorização e antes da primeira escrita, com FOR SHARE. O bloqueio impede alterar `club_id` ou apagar a linha validada durante a transação. É mais forte que FOR KEY SHARE porque `club_id` pode ser uma coluna não-chave. Se a referência mudar enquanto se espera pelo lock, a consulta só aceita uma linha que ainda satisfaça o clube. Dois clientes locais confirmaram espera por lock nas seis tabelas de referência.

Referência inexistente e referência de outro clube recebem o mesmo SQLSTATE `22023` e a mesma mensagem por entidade, sem UUID, nome ou clube de terceiros:

- `Categoria: referência inválida para o clube.`
- `Centro de custo: referência inválida para o clube.`
- `Evento: referência inválida para o clube.`
- `Cargo: referência inválida para o clube.`
- `Membro: referência inválida para o clube.`
- `Bem patrimonial: referência inválida para o clube.`

Parâmetros opcionais NULL não fazem lookup nem ganham novas exigências. Não se acrescentaram regras de atividade para categoria/centro/cargo/membro/evento nem exclusividade de destinatários de empréstimo. Ambos os UUIDs preenchidos em empréstimos são validados independentemente do borrower_type, pois ambos são persistidos. Empréstimos com destinatários NULL continuam aceites onde a baseline aceitava. O log continua a aceitar bens inativos do clube e metadata NULL continua a converter-se em `{}`. `p_asset` é obrigatório no log: NULL passa a receber o erro explícito, em vez da violação NOT NULL posterior. Tesouraria mantém destino ignorado para movimentos que não sejam transferência. Valores, normalização de texto, autor, linhas de detalhe, auditoria, atividade e emissão de eventos continuam existentes.

Não há alterações Flutter nem necessidade de novos contratos Flutter/CI: assinaturas, transporte e parsing não mudam. Os contratos existentes foram executados com HTTP simulado. A nova regressão SQL automatiza o comportamento de base de dados, contratos de catálogo, preflight, ausência de mutações e concorrência. O harness depende do catálogo local de esquema já usado nas fases anteriores, não disponível num runner CI limpo; não foi adicionado um workflow que fingisse reproduzir essa baseline.

## Validação

- SQL: 35 casos, mais verificações de permissões, proteções anteriores, ACLs, preflight, duas ligações concorrentes e reaplicação. Reproduz aceitação cross-club na baseline; candidata rejeita todas as oito referências, com UUIDs inexistentes e externos indistinguíveis. Matriz completa executada duas vezes; fixtures povoadas preservadas na reaplicação.
- Rejeições: snapshots de todas as linhas públicas, net local e Storage antes/depois; nenhum efeito de negócio/auditoria/notificações/rede local. Chamadas válidas verificam retorno e efeitos reais, depois são revertidas por subtransação. O script completo termina em ROLLBACK. Sequências de auditoria podem avançar no cluster descartável, como é normal em PostgreSQL; não se afirma reversão de sequências.
- `git diff --check`: aprovado; novos ficheiros também verificados individualmente para whitespace (não estão staged).
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 269 aprovados, 15 omitidos pela configuração demo existente.
- Contratos existentes com configuração fictícia/HTTP em memória: 19 aprovados, 2 omitidos por serem exclusivos de demo; cobertos na suite demo anterior.
- `flutter build web --release --no-pub --dart-define=DEMO_MODE=true`: aprovado, Wasm dry run aprovado; artefacto apenas local.
- `node --check tools/test_cross_club_phase2c7.mjs`: aprovado.

Evidência legível por máquina: `docs/PHASE_2C7_SQL_RESULTS.json`. Comandos, ambiente e resumos: `docs/PHASE_2C7_TEST_EVIDENCE.md`.

## Limites e riscos residuais

O ensaio usa PostgreSQL nativo 17.10 com catálogo PostgreSQL 17.6 capturado em 13/10/2026, 131 tabelas, 288 funções e 291 triggers. Aplica as migrations de segurança 2C.1–2C.6; não é replay integral do histórico nem stack Supabase completo. Auth/Storage/net são adaptadores locais. Não foi feita uma chamada HTTP real às RPCs via PostgREST nem uma sessão de UI contra Supabase. A sintaxe/semântica segue documentação oficial de CREATE FUNCTION e Database Functions, consultada em 14/10/2026.

Esta fase protege as associações criadas pelas cinco RPCs. Não corrige dados históricos, escritas diretas nas tabelas, outros caminhos de escrita ou mudança posterior do clube de uma entidade já referenciada; FKs compostas/RLS/triggers universais seriam outro âmbito. Locks duram até ao fim da transação e podem causar espera com updates/deletes concorrentes; transactions longas de consumidores externos aumentam contenção. Não se alterou a política de timeouts global. As validações antigas de contas/produto/variante conservam o seu comportamento e concorrência anterior.

Antes de um deploy futuro autorizado: confirmar por leitura assinaturas, owners, ACLs, definições e triggers efetivos; guardar baseline para revisão e parar perante drift não explicado. Rollback de DDL falhado é transacional. Depois de publicado, preferir correção forward; restaurar as definições antigas reabriria o risco e exige decisão específica. Nenhum deploy está autorizado por este parecer.

## Ficheiros exatos adicionados

Todos relativos ao checkout `phase2c3/`:

1. `supabase/migrations/20261014133347_rc1_cross_club_references.sql`
2. `supabase/tests/phase2c7_cross_club_references_regression.sql`
3. `tools/test_cross_club_phase2c7.mjs`
4. `docs/PHASE_2C7_SQL_RESULTS.json`
5. `docs/PHASE_2C7_TEST_EVIDENCE.md`
6. `docs/PHASE_2C7_REVIEW.md`

Nenhum ficheiro versionado pré-existente foi alterado. Permanecem fora do âmbito `asset_maintenance_v1`, drift `clubs.slug`/`profiles.email`, leaked-password protection, `sources/` e `BOB_Manager_arquitetura.zip`.
