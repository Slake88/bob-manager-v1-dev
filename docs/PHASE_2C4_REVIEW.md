# Fase 2C.4 — edição do próprio perfil

14/10/2026, Europe/Lisbon. Branch `rc1-rebuild`, base `3a56f99a5a9b3659bd0057212af596dcfa2fb81c`.

## Alterações

- `20261014091135_rc1_self_profile_permission_and_cardinality.sql`: substitui v1/v2 mantendo assinaturas, SECURITY DEFINER, search_path endurecido e EXECUTE para authenticated/service_role; revoga PUBLIC/anon. Exige auth.uid(), has_club_access e has_club_permission(editOwnMemberProfile), com verificações fail-closed. SELECT INTO STRICT/FOR UPDATE exige uma ficha ligada ao utilizador e clube, bloqueia a ficha durante a atualização e produz erros explícitos para zero (42501) ou múltiplas fichas (21000). Preserva trim/null, campos, JSON de emergência, updated_at/updated_by e tax_number apenas no v2.
- `20261014091136_rc1_members_unique_club_profile.sql`: migration separada e transacional. Bloqueia escritas em members, com lock_timeout de 10 segundos; verifica duplicados sem os corrigir automaticamente. Cria UNIQUE parcial (club_id,profile_id) WHERE profile_id IS NOT NULL. Reaplicação aceita o índice correto; colisão com definição incompatível falha sem eliminar objetos. A criação bloqueia escritas durante o build; eventual execução requer janela adequada e aprovação posterior.
- `apps/mobile/lib/screens/member_detail_screen.dart`: botão de edição do próprio perfil passa a respeitar a permissão dinâmica. Gestão de membros mantém o caminho existente. Repository já usa v2, sem mudança de produção no repository.
- `apps/mobile/test/self_profile_phase2c4_test.dart`: UI acompanha concessão/revogação da permissão e não dá acesso a outro perfil; contrato HTTP simulado exige v2, clube e todos os campos, incluindo NIF.
- `.github/workflows/flutter-ci.yml`: executa o contrato v2 com configuração fictícia e HTTP em memória. Deploy Web continua exclusivamente manual.
- `supabase/tests/phase2c4_self_profile_regression.sql` e `phase2c4_self_profile_index_regression.sql`: regressões SQL, restritas a base nova com prefixo bob_phase2c4_ e endpoint 127.0.0.1, com rollback.
- `tools/test_self_profile_phase2c4.mjs`: harness local com endereço fixo, restauro de catálogo e fixtures sintéticas; testa abortos por duplicados/índice incompatível e reaplicação sem alterar rows/audit.
- `docs/PHASE_2C4_SQL_RESULTS.json`: resultados da execução SQL local.

## Validação

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 269 passaram, 10 omitidos por configuração demo (incluindo o novo contrato HTTP).
- Teste v2 separado com URL/chave fictícias: 1 passou, 2 testes UI omitidos fora de demo; os dois testes UI passaram na suite geral.
- `flutter build web --release --no-pub --dart-define=DEMO_MODE=true`: passou, incluindo Wasm dry run. Artefacto apenas local.
- SQL em PostgreSQL 17.10 local, catálogo de 131 tabelas/288 funções/291 triggers, sem dados reais: auth ausente, acesso cross-club/inativo, permissão de cargo revogada, manageMembers sem permissão própria, override allow/deny, ACLs exatas, service_role autenticado, zero/múltiplas fichas, retorno UUID, isolamento de outro membro, v1 sem alterar NIF, v2 com NIF, todos os campos/JSON, limpeza null/blank, índice único, null links, cross-club, abortos e idempotência. RLS e triggers reais do catálogo.
- SQL nunca executado em produção; nenhuma URL remota é aceite pelo harness. Auth/storage/net são adaptadores locais; não equivalem a um ambiente Supabase completo. Nenhum advisor remoto foi executado.

Sem deploy, aplicação remota de migrations, escrita ou acesso ao Supabase/produção. Sem alterações a outras fases, drift clubs.slug/profiles.email ou BOB_Manager_arquitetura.zip. sources/ e cópias sincronizadas preservadas.

- Revisão final: git diff --check e git diff --cached --check passaram; apenas os 10 ficheiros da Fase 2C.4 foram selecionados para commit.
