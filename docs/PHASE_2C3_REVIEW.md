# Fase 2C.3 — Euromilhões: candidata validada, deploy pendente

Data: 13/10/2026 (Europe/Lisbon). Branch: `rc1-rebuild`.
Base: `7cba7f6d25e55f47635dd6329780f9d9d81a2c31`.

## Comportamento

- `loadMonth`, refresh, navegação mensal e listagem de participantes são apenas consultas. Sem importação, geração ou sync global.
- Todos os membros visíveis são representados; membros sem row aparecem como `non_player` virtual, sem UUID de jogador inventado. Configurar cria/upsert apenas o membro escolhido, conservando o UUID existente. RLS exige `manageLottery` e referência a membro do mesmo clube.
- `Preparar mês` exige `manageLottery`, confirmação explícita e mês atual/futuro. Fica oculto em DEMO_MODE e em meses passados. Durante execução o botão fica desativado.
- RPC pública `prepare_euromillions_month_v1(uuid,integer,integer)` com auth, acesso ao clube, permissão e validação temporal. Helper privado SECURITY INVOKER, sem grants externos; wrappers públicos SECURITY DEFINER apenas onde necessários para escrever cobranças sob RLS.
- Assinaturas antigas de generate/sync preservadas sem execute para PUBLIC/anon/authenticated/service_role. Generate delega no helper protegido; sync global foi desativado e já não é SECURITY DEFINER.
- Pagamento mensal mantém `manageLottery` e o pagamento por sorteio existente. Atual/futuro prepara explicitamente; passado paga apenas cobranças existentes do jogador escolhido, sem reconstruir outras datas. Ausência de histórico devolve erro claro; cobranças já pagas continuam idempotentes.
- `Atualizar oficial` requer `manageLottery` na interface e na Edge Function. Nunca corre no carregamento. `service_role` permanece apenas no processamento oficial já previsto na Fase 2A.
- Conforme confirmação adicional do utilizador, importação e processamento manual/oficial de resultados de meses passados são bloqueados também no servidor. RPC de resultados conserva os guards e a lógica da Fase 2A, adicionando apenas o guard temporal antes das escritas. A assinatura antiga `process_euromillions_result_v1` recebe também auth/acesso explícitos, search_path endurecido e bloqueio temporal para impedir um caminho direto alternativo; preserva `manageLottery`, retirando service_role por não ter caller oficial.
- Histórico mensal mostra jogadores com cobranças/multas/prémios existentes e montantes realmente registados. Não calcula custo passado com preço atual nem compara resultados passados com chaves atuais. O separador de configuração identifica explicitamente as chaves como atuais.
- Limite temporal canónico no servidor: mês de `Europe/Lisbon`. Guard local usa a data do dispositivo como conveniência; o servidor decide a autorização final.
- Não foram criados períodos históricos, alterados dados existentes, feito backfill, nem alteradas outras fases ou leaked password protection. Operações monetárias mantêm os critérios existentes; não foi criado histórico de chaves/preços.

## Testes e evidência

- `git diff --check`: passou.
- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 267 passaram, 9 omitidos por configuração demo. Contratos da 2C.3 executados separadamente com URL/chave fictícias e MockClient: 9 passaram. Os 4 contratos RPC da 2C.2 também foram reexecutados com HTTP simulado.
- `flutter build web --release --no-pub`: passou, incluindo Wasm dry run; artefacto apenas local.
- SQL: PostgreSQL 17.10 local em `127.0.0.1:55439`, base nova com fixtures fictícias. Restauro do catálogo de esquema previamente capturado (131 tabelas, 288 funções, 291 triggers), sem dados reais; aplicação das fases 2C.1/2C.2 e candidata, guards/grants por assinatura, RLS real, triggers de auditoria reais, passado/atual/futuro, pagamento histórico, ausência de cobranças, input inválido, idempotência, configuração seletiva e bloqueio de resultados passados.
- O regression SQL exige nome de base local específico e servidor loopback, termina com rollback, e o harness não aceita URL remota. **Nunca foi executado em produção.**
- Migration aplicada e reaplicada apenas localmente: dados e auditoria preservados. [Resultado SQL](PHASE_2C3_SQL_RESULTS.json).
- Edge Function: 8 contratos de identidade/permissão/tempo com Supabase e fetch simulados, sem HTTP real. [Resultado Edge](PHASE_2C3_EDGE_RESULTS.json).
- A CLI gerou `20261013155418_rc1_euromillions_explicit_month_preparation.sql` localmente; nenhuma aplicação remota.
- A resolução de dependências Flutter encontrou a limitação Windows de symlinks; as dependências já resolvidas foram usadas com `--no-pub`. Não se alterou Developer Mode nem o lockfile.

## Revisão e publicação

Diff revisto: apenas repositório/ecrã/testes Euromilhões, Edge Function, migration/regression SQL, ferramentas/relatórios e dois workflows. CI passa a executar também os contratos simulados da 2C.3.

**O workflow Web agora só permite `workflow_dispatch`**, para impedir deploy automático no push desta candidata ainda não aprovada para produção. Nenhum workflow foi acionado manualmente. Flutter CI continua em push e PR. Esta alteração é necessária para cumprir a instrução de parar antes do deploy.

PR existente #1 permanece rascunho, sem merge. `BOB_Manager_arquitetura.zip` não foi adicionado nem alterado; não existe no novo checkout e não faz parte dos ficheiros staged. A cópia anterior de revisão e todos os ficheiros sincronizados em `sources/` foram preservados.

**Nenhum acesso ao Supabase/produção, deploy, importação real, preparação real, pagamento real ou alteração de dados reais foi efetuado nesta tarefa.** A candidata requer validação e autorização posterior antes de aplicar migration, publicar a Edge Function e publicar Web; publicar só Web deixaria uma RPC nova indisponível no servidor.
