# Commit 15 — Hardening global da superfície RPC/Auth

## Objetivo

Reduzir a superfície RPC exposta pela RC1 sem quebrar os fluxos autenticados já existentes.

O Commit 15 não cria módulos funcionais novos. Consolida a segurança do backend antes de avançar para fotografia de membro, gestão de contas e restantes requisitos RC1.

## Auditoria inicial

Estado confirmado no Supabase antes da migration:

- `141` funções `SECURITY DEFINER` no schema `public`;
- `28` executáveis pelo role `anon`;
- `110` executáveis por `authenticated`;
- `10` funções de trigger `SECURITY DEFINER` executáveis diretamente por `authenticated`;
- `euromillions_prize_category_v1(integer,integer)` e `module_view_permission(text)` sinalizadas com `search_path` mutável.

As 28 exposições a `anon` incluíam triggers de Activity Feed e RPCs de Património, Bar, Loja, Euromilhões e helpers de permissões. O problema resultava de privilégios herdados por `PUBLIC` após migrations posteriores ao hardening global anterior.

## Migration

Migration aplicada no Supabase:

`20260812150418_rc1_global_rpc_access_hardening.sql`

### Regras aplicadas

1. Todas as funções `SECURITY DEFINER` públicas perdem `EXECUTE` por `PUBLIC` e `anon`.
2. A superfície que já era utilizável por `authenticated` é capturada antes do hardening e reposta explicitamente, evitando regressões provocadas por privilégios anteriormente herdados de `PUBLIC`.
3. Funções utilizadas exclusivamente como triggers deixam de poder ser invocadas diretamente por `authenticated`.
4. As RPCs server-only do push ficam explicitamente reservadas a `service_role`:
   - `claim_push_delivery_v1`;
   - `complete_push_delivery_v1`;
   - `deactivate_push_device_server_v1`.
5. `euromillions_prize_category_v1` e `module_view_permission` passam a ter `search_path = public, pg_temp`.
6. A migration inclui guardas que falham se ainda existir uma `SECURITY DEFINER` executável por `anon` ou um trigger `SECURITY DEFINER` diretamente executável por `authenticated`.

## Push dispatch

A Edge Function `push-dispatch` continua com `verify_jwt=false` de forma intencional nesta fase.

O endpoint não aceita uma chamada arbitrária: exige `delivery_id` e `dispatch_token`, e a capability é validada server-side por `claim_push_delivery_v1`. Alterar `verify_jwt` sem redesenhar esse fluxo poderia interromper o dispatcher. As RPCs utilizadas por esta Edge Function ficaram restritas a `service_role`.

## Resultado depois da migration

Estado confirmado no Supabase:

- `141` funções `SECURITY DEFINER`;
- `0` executáveis por `anon`;
- `100` executáveis por `authenticated`;
- `0` funções de trigger `SECURITY DEFINER` executáveis diretamente por `authenticated`;
- RPCs server-only do push: `authenticated = false`, `service_role = true`.

O Security Advisor deixou de reportar:

- `anon_security_definer_function_executable`;
- `function_search_path_mutable` para as duas funções corrigidas.

Continuam a existir avisos `authenticated_security_definer_function_executable` para RPCs que fazem parte da API autenticada da aplicação e para helpers de segurança usados por RLS. Esses avisos não devem ser eliminados indiscriminadamente, porque várias destas funções precisam de `SECURITY DEFINER` e validam permissões internamente.

O aviso de Auth relativo a leaked password protection permanece fora do âmbito desta migration e requer decisão/configuração específica do projeto.

## Smoke test de privilégios

Foi confirmado `EXECUTE = true` para `authenticated` nos principais fluxos:

- Tesouraria — `create_treasury_transaction`;
- Quotas — `register_fee_payment_v1`;
- Euromilhões — `register_euromillions_draw_payment_v1`;
- importação oficial do Euromilhões — `process_euromillions_official_result_v1`;
- Loja — `create_shop_order_v1`;
- Bar — `bar_operation_v2`;
- Património — `asset_loan_v1`;
- Inventário — `inventory_transfer_v1`;
- Agenda — `save_agenda_item_v1`;
- Oficial da Semana — `save_weekly_dinner_v1`;
- Pedidos financeiros — `create_reimbursement_draft_v1`.

## Critério de fecho

- migration aplicada no Supabase;
- `anon` em `SECURITY DEFINER`: `0`;
- triggers expostos diretamente a `authenticated`: `0`;
- smoke test de privilégios dos fluxos principais aprovado;
- `flutter analyze` verde no CI;
- `flutter test` verde no CI;
- Flutter CI completo verde no GitHub.
