# Commit 24 — Tesouraria Operacional Completa

## Objetivo

Fechar o núcleo operacional em falta na Tesouraria da RC1 sem criar uma segunda contabilidade. Obrigações, caixa e correções geram ou referenciam `treasury_transactions`, preservando os relatórios, centros de custo e saldos já existentes.

## Âmbito funcional

- Contas a pagar e a receber com vencimento, estado, liquidações parciais e cancelamento protegido.
- Orçamentos com linhas de receita/despesa e comparação Planeado × Realizado × Desvio.
- Reconciliação bancária por conta e período, com movimentos conciliados e diferença final.
- Sessões de caixa com abertura, valor esperado, contagem, diferença e aprovação separada.
- Gestão de centros de custo.
- Reversão segura de movimentos sem apagar o histórico.
- Hub `Operações` Mobile First dentro do módulo Tesouraria.
- Demo Mode seguro: leitura de dados de exemplo e nenhuma escrita simulada no Supabase.

## Modelo contabilístico

Uma liquidação de conta a pagar cria uma `treasury_transaction` de despesa com `source_type = payable` e `source_id` a apontar para a obrigação. Uma conta a receber cria receita da mesma forma. A reversão cria o movimento inverso com `reversal_of`, mantendo o lançamento original.

Os Extratos & Relatórios usam a regra económica de reversão: um lançamento original que já tenha reversão e o próprio movimento inverso não voltam a inflacionar Receita/Despesa, embora o histórico continue disponível.

## Segurança

Permissões adicionadas:

- `manageTreasuryPlanning`
- `manageCashSessions`
- `approveCashDifferences`
- `reverseTreasuryMovement`

Presidente, Vice-Presidente e Administração mantêm acesso total pelo modelo existente. Tesoureiro recebe planeamento, caixa e reversão por defeito, mas **não** `approveCashDifferences`, garantindo separação de poderes no fecho com diferença.

As novas tabelas usam RLS, grants explícitos para `authenticated` e nenhum acesso `anon`. Operações críticas são RPCs `SECURITY DEFINER` com autorização interna por `has_club_permission`. O invariante global `anon_security_definer_executable = 0` foi confirmado após as migrations.

A reconciliação tem ainda uma trigger server-side que impede associar movimentos de outro clube, outra conta, outro período ou a uma reconciliação já fechada.

## Migrations aplicadas

Estas migrations já estão aplicadas e são imutáveis:

- `20260813102933_rc1_treasury_operational_complete`
- `20260813105052_rc1_treasury_reconciliation_integrity`

Nunca editar nem reaplicar estas migrations; qualquer correção futura deve ser uma nova migration.

## Mobile First

No smartphone, a Tesouraria mantém três destinos curtos: `Resumo`, `Operações` e `Relatórios`. O hub Operações usa cartões grandes e fluxos verticais, evitando uma barra com seis ou sete tabs apertadas. Em tablet/desktop, os mesmos cartões expandem para duas ou três colunas.

## Testes de regressão

`treasury_operational_test.dart` cobre:

- saldo pendente;
- exclusão económica de pares original/reversão;
- separação de permissão para aprovação de diferença de caixa;
- abertura do hub completo em Demo sem inicializar Supabase.
