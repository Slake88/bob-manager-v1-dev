# Commit 18 — Histórico avançado do membro, patches e manutenção de motas

## Objetivo

Completar as áreas avançadas do perfil de membro previstas na RC1, substituindo placeholders por integração real com Supabase para:

- várias motas por membro, com mota principal e arquivo não destrutivo;
- histórico de manutenção por mota;
- faturas e outros documentos privados associados às manutenções;
- patches/distinções com pedido, aprovação e entrega;
- desconto real de stock apenas no momento da entrega do patch;
- Timeline automática do percurso do membro.

## Auditoria prévia

Antes deste commit:

- `member_motorcycles` já existia e suportava várias linhas por membro;
- a UI apresentava apenas a mota principal;
- ao limpar os campos da mota principal, o fluxo antigo removia fisicamente o registo;
- `MemberRepository.related()` devolvia listas vazias em Supabase real para `maintenance_records`, `member_patch_awards` e `member_timeline`;
- as tabelas `maintenance_records`, `member_patch_awards` e `member_timeline` não existiam;
- a Loja já tinha `products`, `product_variants` e a marca `institutional_delivery`, pelo que não foi criado um segundo catálogo de patches;
- o Inventário já tinha stock por localização e movimentos, reutilizados na entrega institucional.

## Migrations

Foram aplicadas duas migrations novas:

- `20260812165729_rc1_member_history_patches_motorcycle_maintenance.sql`
- `20260812170032_rc1_member_history_performance_hardening.sql`

A segunda migration resulta da revisão do Performance Advisor e cobre apenas a nova superfície deste commit: índices de foreign keys e separação das políticas de escrita para evitar políticas permissivas duplicadas em `SELECT`.

## Motas

`member_motorcycles` passa a ter:

- `active`;
- `acquired_on`;
- `retired_on`;
- `notes`;
- garantia de no máximo uma mota principal ativa por membro.

Foram criados os RPCs:

- `save_member_motorcycle_v1`;
- `archive_member_motorcycle_v1`.

Arquivar uma mota não apaga o registo. A manutenção e a Timeline permanecem ligadas à mota histórica. Se a mota arquivada era a principal, outra mota ativa é promovida automaticamente quando existe.

O fluxo legado do formulário de membro deixa de apagar a mota principal: a ausência de dados arquiva o registo.

## Manutenção

Nova tabela `maintenance_records` com:

- mota;
- data;
- tipo de serviço;
- descrição;
- quilometragem;
- oficina/fornecedor;
- custo;
- próxima revisão por data e/ou quilometragem;
- notas.

O histórico de manutenção não tem operação de delete na aplicação. Pode ser corrigido por update, mantendo o percurso histórico.

### Documentos de manutenção

Nova tabela `maintenance_attachments` e bucket privado:

`member-maintenance`

Configuração:

- `public = false`;
- limite por objeto: 15 MB;
- PDF, JPEG, PNG e WEBP;
- URLs assinadas temporárias para consulta;
- caminhos isolados por clube, membro e manutenção.

Formato do caminho:

`<club_id>/members/<member_id>/maintenance/<maintenance_id>/<versao>_<ficheiro>`

O upload usa substituição segura: se o ficheiro chegar ao Storage mas o registo da metadata falhar, o objeto acabado de carregar é removido.

## Privacidade da manutenção

Manutenções e anexos são visíveis/editáveis apenas por:

- utilizadores com `manageMembers`; ou
- o próprio membro, quando tem `editOwnMemberProfile`.

Isto evita que a manutenção, custos e faturas pessoais das motas sejam expostos genericamente a todos os utilizadores com `viewMembers`.

## Patches e distinções

Nova tabela `member_patch_awards` com estados:

- `pending`;
- `approved`;
- `delivered`;
- `cancelled`.

O catálogo é lido diretamente dos produtos da Loja que estejam:

- ativos;
- na área `shop`;
- com `institutional_delivery = true`.

Não existe catálogo paralelo de patches.

### Fluxo

1. A Direção cria o pedido para o membro.
2. A Direção aprova ou cancela.
3. Um utilizador com `manageInventory` confirma a entrega e escolhe o local de stock.
4. Só nesse momento é descontada uma unidade do stock da localização.
5. É criado um `stock_movement` de ajuste com quantidade `-1`.
6. O pedido passa a `delivered` e regista responsável/local de entrega.

A entrega ocorre dentro do RPC `deliver_member_patch_v1`, para que stock e estado do patch sejam tratados na mesma transação PostgreSQL.

## Timeline automática

Nova tabela `member_timeline`.

São produzidos automaticamente eventos para:

- criação do membro;
- alteração de estado;
- entrada como Prospect;
- Full Colors;
- atribuição/fim de cargo;
- adição/arquivo/mudança de mota principal;
- nova manutenção;
- pedido/aprovação/entrega/cancelamento de patch.

A Timeline diferencia eventos do clube e eventos privados do membro. Manutenções e eventos sensíveis de motas/patches permanecem privados do membro/direção; a entrega concluída do patch pode integrar o percurso de clube.

## Histórico de estado

Foi criada `member_status_history`, alimentada automaticamente quando o estado do membro muda.

## RLS e hardening

As cinco novas tabelas têm RLS ativo:

- `member_status_history`;
- `maintenance_records`;
- `maintenance_attachments`;
- `member_patch_awards`;
- `member_timeline`.

Foram também removidas políticas antigas demasiado amplas de `members`, `club_positions` e `member_positions`, que davam uma superfície de escrita baseada apenas em acesso ao clube. Cargos e relações de cargos passam a exigir `manageMembers` para escrita.

A segunda migration acrescenta índices para as foreign keys da nova superfície e substitui políticas `FOR ALL` de cargos/motas por políticas específicas de INSERT/UPDATE/DELETE, evitando SELECT permissivo duplicado.

## Segurança RPC

Os RPCs de aplicação são executáveis por `authenticated` e fazem a autorização no servidor.

As funções internas de Timeline/triggers não são executáveis diretamente por `authenticated`.

Depois das migrations foi reconfirmado:

`anon SECURITY DEFINER executable = 0`

mantendo o invariante estabelecido no Commit 15.

## Flutter

Foi criado `MemberLifecycleRepository`, responsável por:

- motas;
- manutenção;
- documentos privados;
- patches;
- stock de entrega;
- Timeline.

Foi criado `MemberHistoryScreen` com quatro separadores:

1. Motas
2. Manutenção
3. Patches
4. Timeline

O detalhe do membro passa a apresentar as quatro áreas como cartões navegáveis com contadores reais.

## Dependências

Não foram adicionadas dependências. Foram reutilizados:

- `file_picker`;
- `url_launcher`;
- `supabase_flutter`.

## Testes

Foram adicionados testes unitários para:

- isolamento do caminho privado de documentos por clube/membro/manutenção;
- sanitização do nome do ficheiro;
- MIME types permitidos;
- etiquetas dos estados de patches em português.

## Critérios de fecho

- migrations aplicadas;
- novas tabelas com RLS ativo;
- bucket `member-maintenance` privado;
- `anon SECURITY DEFINER = 0` preservado;
- Performance/Security Advisors revistos;
- Flutter analyze verde;
- Flutter tests verdes;
- Flutter Web build verde;
- CI GitHub verde;
- sem alterações fora do âmbito do Commit 18.
