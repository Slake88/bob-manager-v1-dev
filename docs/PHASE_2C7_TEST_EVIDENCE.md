# Fase 2C.7 — evidência local de testes

Executado em 14/10/2026 (Europe/Lisbon), checkout `rc1-rebuild`, HEAD `9c893b6c181415487d3851e8bacaef8f3ebc22cb`.

## SQL

Da raiz do checkout:

```text
node tools/test_cross_club_phase2c7.mjs ../phase2c2-tools/pg-driver/package/src/index.js ../phase2c2-tools/phase2c1-schema-catalog.json
```

Requer o cluster de teste local iniciado em `127.0.0.1:55440`. O harness não aceita host/URL/porta remotos: cria sempre uma base nova com prefixo `bob_phase2c7_`. O SQL recusa outro nome/endereço/porta. O catálogo contém somente esquema, sem dados de produção. Todos os dados de teste são sintéticos, com endereços `example.invalid`.

Resultado final em `PHASE_2C7_SQL_RESULTS.json`: `status=passed`, `caseCount=35`, sete grupos de checks. Baseline vulnerável reproduzida, matriz candidata completa duas vezes, contratos/ACLs exatos, preflight de ausência/ACL, permissões anteriores, seis checks de concorrência e reaplicação sem DML. O cluster e as bases são descartáveis locais. O resultado não equivale a teste remoto ou replay integral das migrations.

## Flutter e contratos

Os comandos seguintes foram executados a partir de `apps/mobile`. No Windows, o launcher foi a snapshot instalada do próprio Flutter, devido ao wrapper `.bat` bloqueado no sandbox; o acesso ao lock/cache do SDK foi permitido pelo mecanismo automático da sessão. Não foram alteradas dependências nem executado pub get.

```text
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/lottery_read_write_split_test.dart test/lottery_screen_split_test.dart test/self_profile_phase2c4_test.dart test/fees_phase2c5_test.dart test/active_membership_phase2c6_test.dart test/weekly_officer_rpc_split_test.dart --dart-define=SUPABASE_URL=https://example.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=test-key
flutter build web --release --no-pub --dart-define=DEMO_MODE=true
```

Launcher efetivo: `C:/Users/Israel.Sousa/Documents/flutter/bin/cache/dart-sdk/bin/dart.exe C:/Users/Israel.Sousa/Documents/flutter/bin/cache/flutter_tools.snapshot`, seguido de cada comando acima sem o primeiro `flutter`.

| Check | Resultado |
| --- | --- |
| analyze | `No issues found! (ran in 9.2s)`; exit 0 |
| suite | `00:46 +269 ~15: All tests passed!`; exit 0 |
| contratos HTTP simulado | `00:09 +19 ~2: All tests passed!`; exit 0 |
| web release | `Wasm dry run succeeded`, `Built build/web`, 84,7s; exit 0 |

Os dois skips dos contratos são casos exclusivos de demo em `self_profile_phase2c4_test.dart`; a suite normal demo cobre-os. Os 15 skips da suite são os contratos que exigem configuração fictícia fora de demo. Nenhuma credencial real foi usada na execução explícita de contratos e os clientes usam MockClient.

Logs brutos locais preservados fora do checkout: `../phase2c2-tools/phase2c7-flutter-test.log`, `phase2c7-contracts.log`, `phase2c7-web-build.log`. O output de analyze foi capturado na sessão. Este documento e o JSON são a evidência versionável, sem incluir ficheiros temporários/build no conjunto para commit.

## Integridade e limites

`node --check tools/test_cross_club_phase2c7.mjs` e `git diff --check`: exit 0. Verificação separada do conteúdo de todos os ficheiros novos: sem espaços no fim de linha ou conflitos; terminações LF. Nenhum ficheiro staged, commit ou push. Artefacto web gerado apenas em `apps/mobile/build/web` (ignorado pelo Git).

Documentação consultada: [CREATE FUNCTION](https://www.postgresql.org/docs/current/sql-createfunction.html), [Database Functions](https://supabase.com/docs/guides/database/functions), [Supabase Changelog](https://supabase.com/changelog). O endpoint changelog.md não foi legível pelo navegador; foi consultada a versão HTML. As atualizações consultadas não exigiram alterar o contrato SQL usado nesta fase.
