# Fase 2C.6 — adesão ativa nos caminhos pessoais

14/10/2026, Europe/Lisbon. Candidata local no branch `rc1-rebuild`, base `6229f7059c9f058b7550aaec34ac4ba73808ab6e`. Implementação local revista para commit/push e CI; sem deploy ou escrita em produção. A pré-verificação anterior consultou apenas metadados de produção.

## Parecer e limites

Favorável à revisão da implementação local. Nenhum blocker funcional local identificado nos testes descritos abaixo. Não constitui autorização de deploy nem declaração de reconciliação integral entre branch e produção.

A pré-verificação anterior comparou, apenas por leitura, as oito funções alvo e as políticas antigas relevantes com o catálogo efetivo de produção e confirmou a superfície esperada: RPCs/helpers SECURITY DEFINER executáveis por authenticated e caminhos pessoais ainda na configuração antiga. Esta confirmação foi reportada na conversa “Continuar verificação Git” em 14/10/2026; não é uma nova consulta nesta revisão. Antes do deploy, repetir o preflight para detetar alterações entretanto ocorridas. A auditoria de referência assinala diferenças de baseline e funções não reconstruídas pelas migrations; esta fase não as reconcilia. O ensaio local usa catálogo de esquema sem dados capturado em 13/10/2026 e aplica as migrations 2C.1–2C.5. Não equivale a replay integral do histórico nem a uma instância completa de Supabase.

## Alteração funcional

A identidade/autoria histórica só autoriza operações pessoais se existir `club_memberships` para o clube e perfil atuais com `active IS TRUE`. A verificação consulta a tabela em cada operação, sem depender de claims de adesão em JWT ou de cache Flutter. A revogação produz efeito nas operações seguintes à confirmação da alteração da adesão; não pretende cancelar transações já em curso nem invalidar ficheiros anteriormente descarregados/URLs assinadas já emitidas.

Os helpers `current_financial_member_v1` e `current_weekly_officer_member_v1` devolvem NULL sem identidade/adesão ativa; `financial_request_access_v1` devolve false. `fee_credit_balance_v1` devolve NULL quando não autorizado, conforme o requisito de helpers pessoais; para autorizados preserva o saldo numérico e o limite inferior zero. O cliente existente converte NULL em zero através de `feeNumber`, sem mudar transporte, API ou UI.

As mutações de cancelamento de pagamento comunicado, confirmação de tarefa/turno e retirada de proposta exigem adesão ativa no caminho pessoal. Os ramos de gestão por `has_club_permission` são preservados. A retirada de proposta continua exclusiva do autor: não foi acrescentada uma exceção para gestores. Tarefas/turnos de acompanhantes continuam reservados a quem já tinha permissão de operações.

As três RPCs de trocas e as operações financeiras de edição, submissão e anexos passam a beneficiar dos helpers protegidos, sem duplicar nem alterar os seus contratos. Trocas continuam manuais e não recalculam a escala.

## Inventário e callers

Oito funções substituídas, com as mesmas assinaturas, defaults, tipos de retorno e SECURITY DEFINER:

- `current_financial_member_v1(uuid)` — `financial_requests_repository.dart`; criação/edição/submissão/anexos em SQL.
- `financial_request_access_v1(uuid)` — RLS de pedidos/anexos e `financial_storage_access_v2`, incluindo Storage financeiro.
- `current_weekly_officer_member_v1(uuid)` — `weekly_officer_repository.dart`; pedido/resposta/cancelamento de trocas e respetiva leitura.
- `fee_credit_balance_v1(uuid,uuid)` e `cancel_reported_fee_payment_v1(uuid,uuid)` — `fees_operational_repository.dart`.
- `acknowledge_event_task_v1(uuid,boolean)`, `set_event_shift_member_status_v1(uuid,text)` e `withdraw_event_proposal_v1(uuid)` — `events_advanced_repository.dart`.

Definições mais recentes de tarefas/turnos vêm da migration de acompanhantes de 15/09; preservam o suporte a acompanhantes. Não foram encontrados callers Edge dos alvos na pesquisa do código disponível. Consumidores externos não versionados não foram verificados.

Doze políticas substituídas: `financial_requests_read`, `fee_credits_select`, `reported_payments_select`, `fee_exemptions_select`, `fee_adjustments_select`, `fee_payment_allocations_select`, `event_proposals_select`, `event_guests_insert/update/delete`, `fee_payment_proofs_select_v1` e `fee_payment_proofs_delete_v1`.

A leitura de pedidos delega no helper único. Anexos e Storage financeiro conservam as políticas existentes que delegam em `financial_request_access_v1`; o teste executa as suas expressões SQL reais. Os comprovativos de quotas exigem adesão ativa tanto para ler como para remover pelo caminho pessoal, incluindo uploads ainda sem pagamento comunicado. A inserção já exigia adesão ativa. Conservam-se os acessos de gestão e a proteção de comprovativos processados. Nas políticas de convidados qualifica-se a correlação `m.club_id=event_guests.club_id`, em vez da comparação tautológica da baseline, restringindo o caminho pessoal ao clube da linha.

Todas as oito funções fixam `search_path = pg_catalog, public, pg_temp`. CREATE OR REPLACE preserva os OIDs e os grants de serviço existentes; PUBLIC/anon ficam sem EXECUTE, authenticated conserva EXECUTE, incluindo helpers de RLS. Não são criados helpers/API adicionais nem tabelas/índices. Migration transacional, reaplicável, apenas definições/políticas/permissões; sem backfill ou chamadas de negócio.

## Testes locais e evidência

- `git diff --check`: aprovado; novos ficheiros também verificados separadamente quanto a whitespace.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 269 aprovados, 15 omitidos em modo demo (incluindo os três novos contratos, executados separadamente com configuração fictícia).
- Contratos `active_membership_phase2c6_test.dart`, `weekly_officer_rpc_split_test.dart` e `fees_phase2c5_test.dart`, com URL/chave fictícias e HTTP em memória: 9 aprovados. NULL/saldo autorizado, assinaturas e respostas void, erro servidor sem fallback/repetição e contratos anteriores. O novo contrato está incluído no workflow Flutter.
- `flutter build web --release --no-pub --dart-define=DEMO_MODE=true`: aprovado, incluindo Wasm dry run. Artefacto apenas local, não publicado.
- PostgreSQL nativo descartável em `127.0.0.1:55439`, base `bob_phase2c6_*`: aprovado. O harness fixa endereço/porta e cria base nova; o SQL recusa outro endereço/nome de base. Apenas fixtures sintéticas e metadados de esquema.
- Reproduz a falha de acesso financeiro com owner inativo antes da candidata. Matriz com owner ativo/inativo, identidade ausente, vínculo sem adesão, adesão sem membro, terceiro, dois clubes, gestor sem membro ligado e gestor inativo com overrides. Testa RPCs financeiras, tarefas/turnos de membro/acompanhante, propostas, quotas e trocas; RLS de pedidos/anexos/quotas/isenções/ajustes/alocações/propostas/trocas e Storage; rejeição sem alterações em todas as tabelas públicas/Storage, incluindo auditoria/notificações. Valida contratos/ACLs exatos, caminhos fixos e ausência de alterações nas funções fora dos oito alvos.
- Reaplica a migration, compara definições/ACLs e repete a regressão completa. Reaplicação com tabelas povoadas preserva todas as linhas de negócio/auditoria/notificações/Storage. Resultado legível por máquina em `PHASE_2C6_SQL_RESULTS.json`.

Reprodução a partir da raiz do repositório:

```text
node tools/test_active_membership_phase2c6.mjs <caminho-local-postgres.js/src/index.js> <catalogo-de-esquema-sem-dados.json>
```

Requer PostgreSQL local isolado já iniciado no endpoint fixo, extensões da baseline e o catálogo referido no resultado. O SQL termina em rollback. O harness conserva apenas fixtures sintéticas na base descartável para a comparação de reaplicação; nenhum parâmetro aceita um URL remoto. Os adaptadores auth/Storage/net são locais: foram verificadas políticas PostgreSQL, não os endpoints HTTP do serviço Storage, emissão/expiração de URLs assinadas nem uma sessão Flutter real contra Supabase.

## Plano de publicação futuro

1. Obter autorização separada para publicação. Confirmar base/branch, migrations até à 2C.5, assinaturas, owners, ACLs, políticas permissivas adicionais e triggers de produção apenas por consultas de catálogo. Se houver diferença não explicada nos objetos afetados, parar e reconciliar antes de aplicar.
2. Rever e guardar as definições/ACLs/políticas anteriores. O ensaio remoto numa development branch foi tentado, mas o Supabase recusou a criação: a organização Blue on Black está no plano Free (`free / tier_free`) e branching exige Pro ou superior. Por decisão do utilizador, o ensaio remoto de Storage fica dispensado nesta etapa; aceita-se a evidência SQL local e a comparação read-only já realizada. Não foi criada uma branch nem um projeto adicional. Esta limitação mantém por verificar os endpoints HTTP reais de Storage e URLs assinadas; não usar produção para regressões transacionais ou RPCs de negócio.
3. Aplicar apenas a migration `20261014113517_rc1_active_membership_personal_access.sql` por processo autorizado, de forma transacional. Não executar geradores, backfill ou RPCs para validar. Considerar a janela de locks curtos de DDL.
4. Verificar por leitura catálogo, caminhos, grants, políticas e registo da migration. Não é necessário deploy Flutter coordenado: os contratos existentes são mantidos. O build desta tarefa é apenas evidência local.

## Rollback considerations

Não há transformação nem dados a reverter. Se a transação falhar, o DDL é revertido integralmente. Após aplicação, não remover simplesmente o registo da migration nem repor cegamente os helpers antigos: isso reabre acesso de adesões inativas. Preferir correção forward que preserve a adesão ativa. Um rollback excecional requer autorização e restauração exata das definições/políticas/ACLs recolhidas no preflight, com aceitação explícita do risco de reabrir acesso. Nenhum script de rollback automático inseguro é fornecido.

## Ficheiros alterados

Todos relativos à raiz `phase2c3/` deste checkout:

- `.github/workflows/flutter-ci.yml`
- `apps/mobile/test/active_membership_phase2c6_test.dart`
- `supabase/migrations/20261014113517_rc1_active_membership_personal_access.sql`
- `supabase/tests/phase2c6_active_membership_regression.sql`
- `tools/test_active_membership_phase2c6.mjs`
- `docs/PHASE_2C6_SQL_RESULTS.json`
- `docs/PHASE_2C6_REVIEW.md`

Sem alterações funcionais Flutter. Ficam fora desta fase as cinco RPCs da 2C.7 (incluindo as duas legacy), `asset_maintenance_v1`, drift de `clubs.slug`/`profiles.email`, proteção de passwords comprometidas, `sources/` e `BOB_Manager_arquitetura.zip`.
