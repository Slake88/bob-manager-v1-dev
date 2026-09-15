# Commit 12 — Oficial da Semana / Escala de Jantares

## Objetivo

Criar um módulo próprio para gerir a escala de jantares do clube, com quintas-feiras oficiais, eventos extraordinários, rotação justa, ausências/férias, trocas entre membros e histórico anual.

## Regras funcionais

- O jantar regular é normalmente à quinta-feira.
- Jantares fora da quinta-feira são registados manualmente como extraordinários.
- Ordem base da rotação: Presidente → Vice-Presidente → Sargento de Armas → Tesoureiro → Secretário → Road Captain → restantes membros.
- Novos membros entram automaticamente no fim da rotação.
- A justiça anual usa a menor contagem de jantares oficiais; em empate prevalece a ordem da rotação.
- Uma quinta marcada como fechada não conta e o membro mantém a prioridade para a próxima data elegível.
- Ausências e férias retiram temporariamente o membro das datas abrangidas e recalculam a escala futura.
- Presidente, Vice-Presidente e Superadmin podem alterar ordem, disponibilidade, inclusão/exclusão, férias/ausências, responsáveis e jantares extraordinários.
- Pessoas externas podem ser registadas manualmente com nome, data e descrição do que fizeram.
- Um membro escalado pode pedir troca a outro membro.
- O destinatário aceita ou recusa; aceitar não altera automaticamente a escala.
- Depois da aceitação, a Direção altera a escala e marca o pedido como aplicado.

## Dados

Tabelas:

- `weekly_officer_rotation`
- `weekly_officer_absences`
- `weekly_dinners`
- `weekly_officer_swap_requests`

Todas têm `club_id`, RLS e metadados de auditoria adequados ao seu fluxo.

## Segurança

- Leitura da escala/rotação/ausências: membros autenticados do clube.
- Trocas: apenas intervenientes e gestores da escala.
- Escrita direta nas tabelas não é concedida ao cliente.
- Alterações são feitas por RPCs com validação server-side.
- Nenhum RPC do Commit 12 é executável por `anon`.
- Helpers internos não são executáveis por `authenticated` quando não são necessários pela app/RLS.

## Notificações

O módulo usa `module_code = weekly_officer` e `action_route = weekly_officer`.

São emitidas notificações persistentes para:

- pedido de troca;
- aceitação/recusa de troca;
- conclusão da troca;
- atribuição manual de um jantar quando o membro tem perfil associado.

A entrega push reutiliza a infraestrutura do Commit 10, quando existir dispositivo/configuração FCM válida.

## Flutter

Novo módulo `weekly_officer` com quatro separadores:

1. **Escala** — quintas oficiais e extraordinários, responsável, prato/descrição, estado, fechar/reabrir, editar e pedir troca.
2. **Rotação** — ordem, contador anual, disponibilidade, exclusão/inclusão forçada e períodos de férias/ausência.
3. **Trocas** — pedidos pendentes, aceitar/recusar/cancelar e conclusão pela Direção.
4. **Histórico** — contagem simplificada por membro, extraordinários, último e próximo jantar.

Sem novos plugins Flutter.

## Geração anual

`ensure_weekly_officer_schedule_v1` gera quintas em falta e recalcula apenas a escala necessária. No ano corrente começa na data atual para não fabricar histórico anterior à adoção do módulo.

## Validação server-side efetuada

Testes transacionais com `ROLLBACK`:

- geração de quintas futuras pela ordem aprovada;
- quinta fechada: `status=closed`, sem responsável e a vez é preservada;
- férias/ausência: membro abrangido é ignorado e a escala é recalculada;
- equidade 2026 com três membros atuais: 7 / 7 / 7 jantares oficiais;
- consulta de 2025: 0 linhas automáticas criadas, protegendo o histórico passado.

Nenhum destes testes deixou jantares ou ausências fictícias na base de dados.

## Migrations

- `20260812085920_rc1_weekly_officer_dinner_roster.sql`
- `20260812091054_rc1_weekly_officer_security_hardening.sql`
- `20260812091155_rc1_weekly_officer_history_guard.sql`

As três migrations já foram aplicadas no projeto Supabase remoto durante a construção do Commit 12 e não devem ser reaplicadas manualmente.
