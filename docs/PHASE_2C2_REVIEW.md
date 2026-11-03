# Fase 2C.2 — migration aplicada e validada em produção

## Aplicação autorizada

Foi aplicada exclusivamente a migration aprovada, sem deploy Web e sem executar
recálculo/rebuild da escala. Depois da aplicação, as operações no Supabase foram
apenas consultas read-only ao histórico, funções, permissões e advisor de segurança.
Não foram executados smoke tests transacionais nem RPCs que possam escrever dados.

Registo confirmado no histórico:
`20261013145457_rc1_weekly_officer_calendar_assignment_split`.
O Supabase atribuiu a versão `20261013145457` ao aplicar o SQL. O ficheiro novo da
cópia isolada foi renomeado para corresponder a essa versão, sem alterar um byte
do SQL aprovado e sem reescrever o histórico de produção. O hash aprovado mantém-se.

Foram verificadas as 13 funções afetadas: corpos idênticos ao SQL aprovado, owner
postgres, SECURITY DEFINER, search_path `pg_catalog, public, pg_temp`, VOLATILE
exceto o helper can_manage, que permanece STABLE. O ensure não chama rebuild.
A nova RPC de rebuild concede EXECUTE apenas a authenticated e contém a guarda
de gestão. Rebuilds internos, trigger de append e lock privado não concedem
EXECUTE a PUBLIC/anon/authenticated/service_role. O schema privado não concede
USAGE aos papéis da API. As quatro tabelas continuam com RLS ativo e SELECT
direto para authenticated. Confirmados zero callers cron de rebuild.

O advisor de segurança respondeu com as categorias conhecidas
`authenticated_security_definer_function_executable` e
`auth_leaked_password_protection`, ambas WARN; não foi efetuada nenhuma alteração
fora do âmbito da migration. A resposta agrupada não fornece uma contagem por
função comparável aos 176 avisos individuais reportados na fase anterior.
Referências: [funções SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[proteção contra passwords comprometidas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Resultados de catálogo em `PHASE_2C2_PRODUCTION_RESULTS.json`.
O checkout original permanece intacto; não houve commit ou push. A publicação
Flutter e o primeiro recálculo não foram realizados e continuam separados.

## Histórico da preparação e revisão

Base: `31ac81711ed89fd6d3578ded76fd66b2c4d43d84`.
Preparada numa cópia isolada do checkout. Durante preparação e revisão não houve
commit, push, deploy ou escrita em produção. A confirmação do schema usou SELECTs.
As migrations anteriores não foram editadas.

## Estado final da validação

A candidata passou 66 verificações num PostgreSQL local reconstruído a partir do
catálogo confirmado da produção após a 2C.1. A reconstrução histórica do zero
permanece com problemas anteriores, mas a alternativa de validar sobre o schema
confirmado foi concluída. A revisão final não identificou bloqueios adicionais.
A aplicação autorizada posterior está documentada no início deste relatório.

## Parecer da revisão final

A candidata está aprovada tecnicamente para aplicação controlada da migration,
depois de autorização específica e confirmação de que o schema não mudou desde
o catálogo testado. Esta aprovação não autoriza push, publicação Flutter ou o
primeiro recálculo. Essas ações continuam separadas.

Foi corrigido um detalhe na interface: o recálculo aparecia em demonstração,
embora o repositório não suporte essa operação nesse modo. A ação passa a ficar
oculta quando indisponível. Foi acrescentado um teste de regressão; os três testes
de interface passaram e a suíte final passou com 263 testes. Os quatro testes de
contratos de RPC passaram separadamente com HTTP simulado. A análise final Flutter
não encontrou problemas. A compilação Web release final também passou, sem
publicação. A migration SQL permaneceu inalterada nesta revisão;
as 66 verificações sobre o catálogo confirmado continuam aplicáveis.

SHA-256 da migration SQL revista:
`ca9f895a0ee09bb51bd051bc4d37ed692759b26ba9347cd419f151d93404a4ac`.

Revisão de SQL: assinatura/retorno do ensure preservados, nenhuma chamada de rebuild
no carregamento, autorização por adesão ativa e papel fixo, helpers sem execução
direta de API, lock antes das leituras/escritas da gestão e preservação das fontes
manuais/swaps/externas. O início antigo de uma ausência editada é incluído no
recálculo. A migration contém apenas definições/permissões, sem backfill ou rebuild.

Revisão de Flutter: capacidade obtida no servidor, recálculo explícito com intervalo
e confirmação, bloqueio do botão durante a execução e nenhum rebuild em refresh
ou navegação. Novas datas continuam “Por definir” até uma operação de gestão.

Foram recolhidos apenas metadados em 13/10/2026 às 12:43:26 de Lisboa:
131 tabelas, 288 funções, oito enums, constraints, índices, políticas, ACLs e 291
triggers. Não foram copiadas linhas de membros, perfis, contas ou outros dados de
produção. Os dados de teste são inteiramente fictícios.

Antes da candidata, o restaurador comparou os tipos/nulabilidade de todas as
colunas, constraints, triggers, RLS, ACLs de tabelas, as 288 definições de funções
e EXECUTE efetivo de anon/authenticated/service_role com o catálogo recolhido.
O estado real NOT NULL de `clubs.slug` e `profiles.email` foi preservado na base
local; não foi alterado para acomodar fixtures.

As 66 verificações incluem os cenários nativos anteriores, a primeira aplicação
da migration com atribuições existentes, a RPC real `agenda_calendar_v1` para
membro comum, acesso por clube, ausência de autenticação, necessidade de viewAgenda,
ocultação de entradas da Direção e preservação integral dos jantares ao consultar.
Os resultados estão em `PHASE_2C2_CATALOG_RESULTS.json`.

As funções, constraints, índices e triggers da aplicação vieram do catálogo; auth,
storage.foldername e net.http_post usam adapters locais. Não foram testados login
real, PostgREST remoto, entrega de push ou o serviço Storage. O motor local é 17.10,
e o de produção confirmado é 17.6. Nenhum destes serviços foi alterado nesta fase.
O transporte Flutter das RPCs foi coberto separadamente com HTTP simulado.

Consultas finais read-only confirmaram 2C.1 presente, candidata ausente, nova RPC
de rebuild ausente e zero tarefas cron referenciando os rebuilds internos.
Os callers SQL encontrados no catálogo são os sete conhecidos do módulo; esta
verificação não inventaria consumidores externos fora da base e do código revisto.

## Comportamento

`ensure_weekly_officer_schedule_v1(uuid,integer)` mantém assinatura e retorno:
apenas insere quintas regulares em falta, com responsável nulo. Anos anteriores
ao atual devolvem zero. No ano atual só gera datas de hoje em diante. Não toca
em linhas existentes. Ano nulo passa a ser rejeitado explicitamente.

`rebuild_weekly_officer_schedule_v1(uuid,integer)` é uma nova entrada explícita.
Exige adesão ativa no clube alvo com `president`, `vice_president` ou `super_admin`.
Garante as datas e recalcula as atribuições automáticas do ano selecionado, desde
hoje no ano atual. Devolve intervalo, linhas inseridas, elegíveis, atribuídas e
alteradas. `changed` conta novas linhas elegíveis e linhas existentes cujo
responsável final mudou; não representa o número de UPDATEs internos.

O algoritmo original foi preservado: disponibilidade, contagem anual e desempate
pela rotação. Atribuições manuais, trocas e externos são preservados, assim como
jantares extraordinários, passados, concluídos, cancelados e fechados.
`force_included` continua a sobrepor-se às exclusões de disponibilidade.

Agenda e escala continuam a chamar o calendário ao carregar. O ecrã da escala
consulta a capacidade no servidor e disponibiliza uma ação de recálculo com
confirmação e intervalo visível. Carregamentos e refresh, incluindo de gestores,
nunca chamam o recálculo. Clientes antigos beneficiam da mudança da RPC existente.
Datas novas aparecem como “Por definir” até uma operação de gestão atribuir membros.

## Proteções

Um advisory lock transacional por clube é adquirido antes de leituras/escritas
pelas operações de calendário, rebuild, reorder, disponibilidade, ausências,
edição/fecho de jantar e append de membros à rotação. A chave é partilhada pelas
operações desse clube, incluindo a criação automática de rotação por trigger.
O helper está num schema privado sem acesso dos papéis de API.

Helpers de rebuild exigem autorização de gestão e deixam de ter EXECUTE direto
para `service_role`. A nova RPC é concedida apenas a `authenticated`, com guarda
de pertença e papel dentro da função. O `ensure` mantém ACLs anteriores e exige
`auth.uid()`. Todas as funções alteradas usam `pg_catalog, public, pg_temp`.

Ao editar uma ausência, o rebuild começa no menor dos inícios antigo e novo,
limitado a hoje. Isto cobre também alterações de membro.

## Validação executada

- Análise Flutter: sem problemas.
- Compilação Web release: aprovada, sem publicação.
- Patch: aplicação verificada com `git apply --check --whitespace=error` sobre
  o checkout original; o checkout
  original permaneceu no commit base, com apenas o ZIP previamente não rastreado.
- Suíte Flutter padrão final: 263 passaram; quatro testes específicos de RPC foram
  omitidos nessa execução por configuração demo e passaram separadamente.
- Quatro testes de contratos com defines fictícios e HTTP totalmente simulado:
  assinatura de calendário, grelha da Agenda cruzando anos, capacidade do servidor
  sobrepondo-se ao rótulo local e chamada explícita da nova RPC.
- PostgreSQL em memória com PGlite 0.5.9: 43 verificações passaram.
  Cobrem calendário, preservação integral de linhas existentes, papéis e clubes,
  guards, helpers privados, ausências, ausência de candidatos, force inclusion,
  reaplicação da migration e rollback quando a auditoria falha.

- PostgreSQL nativo 17.10 portátil: 58 verificações passaram com sessões TCP
  independentes em `127.0.0.1:55439`. As funções reais de auditoria e os triggers
  de carimbo/captura do módulo foram carregados das migrations versionadas.
  Rebuild, reorder, ensure, inserção/remoção de ausência, edição/fecho/reabertura
  de jantar e append de membro aguardam o advisory lock do mesmo clube e completam
  após commit, sem deadlock nos cenários testados. Um segundo clube avança enquanto
  o primeiro está bloqueado. Aplicar a candidata sobre uma escala já preenchida
  preserva as linhas completas e não acrescenta auditoria de dados.
  O servidor portátil foi encerrado no final; nenhum serviço foi instalado.

Os runners do módulo usam definições versionadas com tabelas mínimas de dependências.
O nativo inclui os triggers reais de auditoria, mas não reproduz toda a plataforma
Supabase/Storage/cron/push nem o histórico integral. Resultados detalhados:
`PHASE_2C2_NATIVE_MODULE_RESULTS.json`.

## Reconstrução integral: impedimento anterior à candidata

Foi iniciada a reconstrução das 143 migrations em ordem numa base nativa nova. A execução parou
na primeira, `1000_bob_manager_v1_complete.sql`, antes de aplicar qualquer migration
posterior ou a candidata:

1. Com validação normal, `has_permission` referencia `membership_roles.membership_id`,
   mas a migration cria `membership_roles.club_membership_id` (também referencia
   `user_permission_overrides.membership_id`). Erro `42703`.
2. Com `check_function_bodies=off`, mantendo os corpos intactos, a criação da vista
   `v_stock_balances` referencia `stock_movements.variant_id`, que não existe nessa
   migration. Erro `42703`. A reconstrução continuou bloqueada.

Os ficheiros históricos não foram alterados nem foram acrescentadas colunas para
esconder estes erros. O runner integral disponibiliza adapters locais de auth,
Storage, `pg_net` e `pg_cron`, sem rede ou execução de jobs. Só as duas declarações
de extensões não disponíveis seriam adaptadas em memória; não chegaram a ser
executadas porque a migration inicial falhou. A tentativa e o erro reproduzível
estão em `PHASE_2C2_NATIVE_REPLAY_RESULTS.json`.

Esta falha não demonstra uma regressão da 2C.2: ocorre na base versionada anterior.
Também não demonstra que o histórico completo seja válido. A validação alternativa
num ambiente descartável com o schema confirmado da 2C.1 foi executada com sucesso.
A correção da baseline histórica continua separada da candidata.

## Reprodução

```powershell
# Na pasta apps/mobile
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/weekly_officer_rpc_split_test.dart --dart-define=SUPABASE_URL=https://example.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=test-key

# No checkout; passar o caminho do módulo PGlite 0.5.9 instalado localmente
node tools/test_weekly_officer_phase2c2.mjs /caminho/pglite/dist/index.js

# Com PostgreSQL portátil previamente iniciado apenas em 127.0.0.1:55439
node tools/test_weekly_officer_phase2c2.mjs /caminho/postgres.js/src/index.js --native
# Sobre o catálogo recolhido da 2C.1; também usa apenas localhost
node tools/test_weekly_officer_phase2c2.mjs /caminho/postgres.js/src/index.js --native --catalog ../phase2c2-tools/phase2c1-schema-catalog.json
# Reproduz a tentativa integral e guarda o erro encontrado na baseline
node tools/test_weekly_officer_native.mjs /caminho/postgres.js/src/index.js
```

## Sequência proposta para aplicação futura

1. Rever o patch e o relatório, incluindo limites dos adapters e a retirada de
   EXECUTE direto de service_role nos helpers internos. Confirmar consumidores
   operacionais externos, se existirem.
2. Após autorização específica, confirmar que não houve mudança de schema desde
   o catálogo testado e preparar um snapshot de recuperação. Aplicar só a migration,
   em transação, sem executar rebuild ou backfill. Verificar assinaturas, ACLs,
   guards e search_path. Consultar advisors após a aplicação autorizada.
3. Verificar Agenda/escala com um membro comum antes de publicar o Flutter.
   Clientes antigos continuam a usar o ensure, que passa a garantir apenas datas.
4. Publicar o Flutter apenas quando autorizado. O primeiro rebuild é uma operação
   de gestão separada, com intervalo explícito, nunca parte da migration.

A preparação e a validação sobre o schema confirmado estão concluídas. A migration
foi posteriormente autorizada e aplicada. Publicação Flutter e primeiro rebuild
não foram autorizados nem realizados. PostgreSQL portátil foi usado localmente e já está encerrado;
não foi criado ambiente remoto nem houve custo de infraestrutura remota.

## Reversão

Não reintroduzir o rebuild no carregamento como rollback: isso restauraria o risco
original. Em caso de problema na interface, retirar a ação de recálculo e manter
o ensure seguro. Um rebuild já executado exige recuperação das atribuições a partir
de auditoria/snapshot previamente verificado; reverter definições não desfaz dados.
Antes de qualquer aplicação real, validar um snapshot e um procedimento de recuperação
no ambiente descartável. Não houve rebuild sobre dados reais nesta preparação.

## Fora desta fase

Swaps e suas RPCs não foram alterados. A aplicação atómica e revalidação de pedidos
desatualizados continuam propostas para fase separada. O drift de `clubs.slug` e
`profiles.email` também fica fora desta alteração.
