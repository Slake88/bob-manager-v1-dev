# Commit 19 — Centro Global de Relatórios e Exportações

## Objetivo

Substituir os placeholders do módulo `Relatórios` por um centro transversal real, reutilizando os dados, permissões e RLS já existentes em cada módulo, sem duplicar os relatórios financeiros da Tesouraria.

## Âmbito

O Centro Global disponibiliza relatórios para:

- Membros;
- Quotas;
- Eventos;
- Inventário — stock;
- Inventário — stock por localização;
- Inventário — movimentos;
- Documentos;
- Comunicação;
- Tesouraria, através de ligação para o ecrã financeiro já existente.

As importações ficam deliberadamente fora deste commit.

## Arquitetura

### Catálogo

`apps/mobile/lib/core/reporting.dart`

Define:

- tipos de relatório;
- colunas e tipos de valores;
- filtros;
- permissões mínimas por relatório;
- catálogo único usado pelo menu e pelo Centro de Relatórios.

O módulo `Relatórios` deixa de depender exclusivamente de `viewFinancialReports`. Passa a aparecer quando o utilizador possui pelo menos uma permissão de leitura correspondente a um relatório disponível.

### Repositório

`apps/mobile/lib/repositories/reports_repository.dart`

O repositório não cria um canal paralelo de acesso aos dados. Reutiliza os repositórios existentes:

- `MemberRepository`;
- `FeesRepository`;
- `EventsRepository`;
- `InventoryRepository`;
- `InventoryControlRepository`;
- `DocumentRepository`;
- `CommunicationRepository`.

Antes de carregar qualquer relatório volta a validar a permissão correspondente no `AppSession`.

Isto preserva:

1. permissões dinâmicas da aplicação;
2. RLS do Supabase;
3. filtros de visibilidade já existentes, incluindo documentos sensíveis e audiências de comunicação.

### Exportação

`apps/mobile/lib/services/report_export_service.dart`

Motor transversal para:

- PDF;
- Excel (`.xlsx`);
- CSV UTF-8 com BOM e separador `;` para boa compatibilidade com Excel em Windows/PT;
- partilha nativa através de `share_plus`.

Os ficheiros incluem:

- identificação BLUE ON BLACK;
- nome do relatório;
- data/hora de geração;
- filtros aplicados;
- métricas do conjunto filtrado;
- apenas as colunas aprovadas para o relatório.

## Privacidade

### Membros

A exportação genérica não contém:

- NIF;
- morada;
- telefone;
- email;
- contacto de emergência;
- tipo sanguíneo;
- alergias;
- notas médicas;
- notas privadas;
- caminhos de Storage.

Inclui apenas dados operacionais do clube: número, nome, alcunha, estado, datas de percurso, cargo e mota principal.

### Eventos

O relatório operacional não exporta o orçamento do evento.

### Inventário

Os relatórios gerais exportam quantidades e estado operacional. Não usam um novo endpoint privilegiado.

### Documentos

`DocumentRepository.listDocuments()` continua a remover documentos sensíveis quando o utilizador não tem `viewSensitiveDocuments`.

A exportação não inclui `storage_path`, nome físico interno, MIME ou conteúdo do ficheiro.

### Comunicação

`CommunicationRepository.listAnnouncements()` mantém as regras de audiência e publicação. O relatório mostra apenas comunicados que o utilizador já pode consultar.

## Filtros

Conforme o relatório:

- pesquisa textual;
- período;
- estado;
- prioridade;
- tipo de movimento;
- estado de stock.

Os filtros são aplicados antes da pré-visualização e da exportação; PDF, Excel e CSV recebem exatamente o mesmo conjunto filtrado.

## Tesouraria

Não foi criada uma segunda implementação financeira.

O cartão `Tesouraria` abre `TreasuryReportsScreen`, preservando o Commit 4 e os filtros/exportações já existentes.

## Supabase

Este commit não requer nova migration.

Os dados necessários já existem e são consultados através das APIs/repositórios atuais. O novo Centro de Relatórios não adiciona função `SECURITY DEFINER`, tabela, bucket ou Edge Function.

## Validação prevista

- `flutter analyze`;
- `flutter test`;
- build Flutter Web;
- CI do GitHub Actions;
- verificação do diff final;
- confirmação de que não existem migrations novas nem alterações fora do âmbito.

## Critério de fecho

O Commit 19 fica concluído quando:

1. o módulo Relatórios deixa de apresentar placeholders;
2. cada cartão visível abre um relatório real ou o relatório financeiro existente;
3. PDF, Excel e CSV funcionam sobre o mesmo conjunto filtrado;
4. o catálogo respeita permissões por módulo;
5. dados sensíveis não entram em exportações genéricas;
6. analyze, testes e build Web ficam verdes.
