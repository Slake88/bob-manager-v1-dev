# RC1-FINAL 158 — adenda de preparação (2026-10-29)

Esta pasta é uma cópia nova do bundle RC1-FINAL de 157 entradas, acrescida da migration `20261029110000_rc1_module_view_edit_permissions.sql` na ordem 158. O bundle original `supabase/release/rc1-final` permanece intacto.

## Evidências desta revisão

- HTTP/Auth/PostgREST: 22/22 testes JWT dirigidos PASS para `viewFinancialRequests`, `viewWeeklyOfficer`, `viewAgenda`, precedência de bloqueios individuais, escrita protegida e `viewDirectionAgenda`.
- Flutter 3.44.8 / Dart 3.12.2: `flutter analyze --no-pub` PASS.
- Testes Flutter dirigidos: `dynamic_permissions_test.dart` (2), `module_access_policy_test.dart` (9), `shell_module_visibility_test.dart` (3) e `shell_module_routes_test.dart` (1), todos PASS.
- `flutter build web --release --no-pub --dart-define=DEMO_MODE=false` PASS com URL loopback de teste e chave local de compilação placeholder. `main.dart.js` SHA-256: `FFC658DC485F5FAA07563A2BD4069FF7BE316A6197E735D08D09630B2C2CB26A`. Os 17 códigos de módulo e as três novas chaves de consulta estão presentes nos assets compilados. O bundle Web não é evidência de login browser.
- Preview estático local disponível em `http://127.0.0.1:55139/`; HTTP 200. O servidor Node foi limitado a loopback; o gateway local mantém CORS para a origem exata. Não foi feito teste de login visual/Chrome.
- Não foram repetidos os 157 replays. A sequência de 158 não foi aplicada numa instalação limpa; esta revisão é candidata para validação, não certificação.
- No clone de testes as definições efetivas e os testes comportamentais das novas permissões estão presentes; não foi encontrada entrada identificável da migration em `public.schema_migrations_bob`. Não se afirma registo no ledger.

## Hashes e ordem

`RC1_FINAL_EXECUTION_ORDER.csv` lista 158 entradas sequenciais. Cada conteúdo foi comparado com o SHA-256 registado nessa ordem. A migration 158 conserva o hash da fonte e não altera migrations históricas.
