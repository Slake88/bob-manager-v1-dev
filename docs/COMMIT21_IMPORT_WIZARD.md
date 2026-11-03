# Commit 21 — Assistente Seguro de Importação Excel/CSV

## Objetivo

Implementar o requisito aprovado de Importação:

> Excel/CSV com mapeamento, pré-visualização, edição e reversão.

O Commit 21 introduz uma infraestrutura de importação controlada e auditável. Não reutiliza a Exportação Integral do Commit 20 como mecanismo de restauro; esse fluxo permanece separado.

## Auditoria prévia

Antes da implementação foi confirmado que não existiam no Supabase:

- tabelas `imports` / `import_rows`;
- funções públicas de importação genérica;
- staging de CSV/XLSX;
- fluxo Flutter de mapeamento, pré-visualização ou rollback.

O parser Excel reutiliza a dependência `excel`/`excel_community` já presente no projeto. O seletor de ficheiros reutiliza `file_picker`.

## Destinos suportados

A primeira versão do motor é genérica, com allowlist fechada de quatro destinos:

1. `members` — Membros;
2. `inventory_products` — Produtos de Inventário;
3. `events` — Eventos;
4. `fee_plans` — Planos de Quotas.

Não são importados diretamente neste commit movimentos financeiros, pagamentos, stock movements ou outros ledgers transacionais.

## Autorização

A importação é permitida a:

- Super Admin;
- Presidente;
- Vice-Presidente;
- Administrador;

ou a um perfil explicitamente autorizado com:

- `manageImports`; e
- a permissão de gestão do módulo do destino.

Matriz por destino:

| Destino | Permissão adicional |
| --- | --- |
| Membros | `manageMembers` |
| Produtos | `manageInventory` |
| Eventos | `manageEvents` |
| Planos de Quotas | `manageFees` |

A autorização é validada no Flutter e novamente no Supabase.

As datas protegidas de `Prospect` e `Full Color` continuam sujeitas ao trigger existente: apenas Super Admin, Presidente ou Vice-Presidente as podem definir. O importador não contorna essa regra.

## Migrations

- `20260813070834_rc1_import_wizard_preview_rollback.sql`
- `20260813071838_rc1_import_permission_helper_invoker.sql`

A segunda migration mantém o helper de autorização como `SECURITY INVOKER`; as RPCs de escrita permanecem `SECURITY DEFINER` de forma intencional e fazem autorização explícita antes de qualquer alteração.

## Tabelas

### `imports`

Guarda metadata do processo:

- clube;
- utilizador que iniciou;
- destino;
- nome e formato do ficheiro;
- mapeamento;
- estado;
- contagens válidas/inválidas/aplicadas;
- código de erro normalizado;
- timestamps.

Estados:

- `draft`;
- `ready`;
- `applied`;
- `reverted`;
- `failed`.

### `import_rows`

Guarda o staging temporário:

- número de linha;
- dados de origem;
- dados mapeados;
- erros de validação;
- id do registo criado;
- snapshot técnico usado pelo rollback;
- timestamps.

Após aplicação com sucesso, `source_data` é limpo para `{}` para reduzir a retenção de colunas arbitrárias que não façam parte do destino aprovado.

As duas tabelas têm RLS ativa. `authenticated` tem apenas `SELECT` autorizado; alterações são feitas exclusivamente pelas RPCs controladas.

## RPCs

- `begin_import_v1`
- `stage_import_rows_v1`
- `update_import_row_v1`
- `apply_import_v1`
- `rollback_import_v1`

Helpers internos:

- `import_target_allowed_v1`
- `import_validate_row_v1`
- `import_parse_date_v1`
- `import_parse_timestamptz_v1`
- `import_parse_numeric_v1`
- `import_parse_boolean_v1`

Os helpers de parsing/validação não são expostos ao `anon` nem ao `authenticated`.

## Limites de proteção

No cliente:

- CSV ou XLSX;
- máximo 2 MB;
- máximo 1000 linhas;
- máximo 50 colunas.

No backend:

- máximo 1000 linhas por importação;
- payload de staging até 5 MB.

## CSV

Suporta:

- UTF-8 com/sem BOM;
- fallback Latin-1;
- `;`, `,` ou TAB;
- campos entre aspas;
- aspas duplicadas;
- quebras de linha dentro de campos citados;
- CRLF/LF.

## XLSX

- usa `Excel.decodeBytes`;
- seleciona a primeira folha com conteúdo;
- primeira linha não vazia é o cabeçalho;
- restantes linhas são pré-visualizadas e mapeadas.

## Mapeamento

O assistente tenta reconhecer automaticamente cabeçalhos portugueses e aliases.

O utilizador pode corrigir manualmente o mapeamento antes de enviar as linhas para validação.

Campos obrigatórios têm de estar mapeados antes da pré-visualização.

## Validação server-side

### Membros

- nome obrigatório;
- número positivo;
- número não pode já existir no clube;
- duplicados dentro do próprio ficheiro são rejeitados;
- estado válido;
- datas válidas;
- proteção existente das datas Prospect/Full Color permanece ativa.

### Produtos

- nome obrigatório;
- área `shop` ou `bar`;
- números não negativos;
- booleanos válidos;
- o stock corrente/reservado não é importado.

A criação do produto continua a usar o trigger existente de sincronização de saldos.

### Eventos

- nome obrigatório;
- estado válido;
- datas/horas válidas;
- fim não pode ser anterior ao início;
- capacidade e orçamento não negativos.

### Planos de Quotas

- nome e valor obrigatórios;
- valor não negativo;
- frequência válida;
- dia de vencimento entre 1 e 31;
- booleano de ativo válido.

## Aplicação transacional

`apply_import_v1` aplica todas as linhas numa única unidade transacional.

Se uma linha falhar:

- os registos já inseridos nessa tentativa são revertidos;
- a importação fica `failed`;
- não é declarado sucesso parcial;
- a auditoria recebe apenas um `error_code` normalizado.

## Reversão protegida

O rollback remove apenas registos criados pela importação.

Antes de apagar cada registo é validado:

1. que o registo ainda existe;
2. que não foi alterado após a importação;
3. que não ganhou relações de negócio que tornariam a remoção destrutiva.

Exemplos de bloqueio:

- membro já associado a pedidos financeiros, eventos, motas ou património;
- produto já usado em movimentos, encomendas ou Bar;
- evento já ligado a participantes, tesouraria ou inventário;
- plano de quotas já com obrigações geradas.

Se qualquer linha não puder ser revertida, a tentativa inteira de rollback é anulada para não produzir reversão parcial.

## Auditoria

São registados:

- início;
- staging/validação;
- aplicação;
- falha;
- reversão;
- reversão bloqueada.

Não são colocados no audit log:

- conteúdo completo do ficheiro;
- passwords/tokens;
- mensagens arbitrárias de erro;
- payloads completos das linhas.

## Flutter

Novos componentes:

- `core/importing.dart`
- `services/import_file_parser.dart`
- `repositories/import_repository.dart`
- `screens/import_wizard_screen.dart`

Integração:

- `manageImports` em `AppPermission`;
- cartão **Assistente de Importação** no Centro de Relatórios;
- módulo Relatórios fica visível também quando o utilizador tem um destino de importação autorizado.

## Testes

Cobertura Flutter prevista:

- política `manageImports`;
- mapeamento automático;
- normalização de escolhas/booleanos;
- parser CSV com BOM/aspas/quebras de linha;
- parser XLSX;
- normalização de cabeçalhos.

Teste transacional real de backend executado como `authenticated` com o Super Admin:

1. iniciar importação;
2. staging de um plano de quotas;
3. confirmar validação sem erros;
4. aplicar;
5. confirmar criação;
6. reverter;
7. confirmar remoção;
8. `ROLLBACK` global.

Resultado final: `0` registos de teste residuais.

## Fora do Commit 21

- restauro direto do ZIP `bob-export-v1`;
- importação de anexos/Storage;
- importação de movimentos financeiros/ledgers;
- importação superior a 1000 linhas num único lote;
- agendamento de importações;
- atualização massiva de registos existentes;
- reconciliação automática de duplicados além das regras explícitas.
