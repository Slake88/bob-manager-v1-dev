# Commit 26 — Eventos Avançados

## Objetivo

Completar o módulo Eventos da RC1 sem substituir a agenda já estável. O módulo passa a ter dois destinos Mobile First: `Agenda`, que preserva o calendário existente, e `Gestão`, que concentra propostas, roadbook, operação e o modelo Rock & Ride In.

## Requisitos fechados

- `REQ-EVENTO-001` — qualquer membro pode propor um evento; a aprovação/rejeição é reservada aos perfis autorizados.
- `REQ-EVENTO-002` — acompanhantes passam a ter registos próprios e um participante pode ter vários acompanhantes.
- `REQ-EVENTO-003` — passeios com roadbook, paragens e vista de emergência.
- `REQ-EVENTO-004` — Rock & Ride In com bandas, expositores, patrocinadores/apoios e configuração de Octanas.
- `REQ-EVENTO-005` — tarefas, responsáveis, turnos/escalas, programa e incidentes.

## Arquitetura Mobile First

A agenda mensal e o detalhe de evento existentes são preservados. O novo `EventsModuleScreen` acrescenta uma navegação curta `Agenda | Gestão`, evitando uma barra de tabs extensa no smartphone.

A área Gestão apresenta propostas e uma entrada operacional por evento. Dentro do evento existem hubs para:

- acompanhantes;
- roadbook;
- vista de emergência;
- operação;
- Rock & Ride In.

## Modelo de dados

O `events` existente recebe apenas `event_kind` (`general`, `ride`, `rock_ride_in`) e `is_private`.

Novas tabelas:

- `event_proposals`;
- `event_guests`;
- `event_routes` e `event_route_stops`;
- `event_bands`;
- `event_exhibitors`;
- `event_sponsors`;
- `event_octane_configs`;
- `event_tasks` e `event_task_assignees`;
- `event_shifts` e `event_shift_members`;
- `event_program`;
- `event_incidents`.

O acompanhante antigo guardado em `event_registrations.guest_name` foi preservado por migração para `event_guests`.

## Emergência

A base RC1 real ainda não possui `member_emergency_data`. Para não duplicar informação, a vista de emergência do passeio usa o campo existente `members.emergency_contact`, juntamente com nome, nickname e telefone dos membros inscritos.

## Permissões

Foram acrescentadas ao modelo dinâmico:

- `proposeEvents`;
- `approveEventProposals`;
- `manageEventRoadbook`;
- `manageEventOperations`;
- `manageRockRide`;
- `manageEventFinance`.

O membro comum pode propor. Road Captain concentra roadbook e operação. Responsável de Eventos gere roadbook, operação e Rock & Ride In. Tesoureiro recebe aprovação prevista e a componente financeira. Presidente, Vice-Presidente e Administração mantêm o modelo de acesso global existente.

## Segurança e integridade

Todas as 14 novas tabelas têm RLS ativo e nenhum privilégio para `anon`.

Os workflows de proposta são atómicos:

- `submit_event_proposal_v1`;
- `approve_event_proposal_v1`;
- `reject_event_proposal_v1`;
- `withdraw_event_proposal_v1`.

A confirmação de tarefa e atualização de presença em turno usam:

- `acknowledge_event_task_v1`;
- `set_event_shift_member_status_v1`.

Os RPCs privilegiados validam autenticação e autorização internamente, usam `search_path` fechado e não são executáveis por `anon`.

Triggers garantem que filhos, membros, tarefas, turnos, paragens e responsáveis pertencem ao mesmo clube/evento. O `club_id` dos filhos é sempre derivado do evento no servidor.

## Migrations aplicadas

Estas migrations já estão aplicadas no Supabase e são imutáveis:

- `20260814090737_rc1_events_advanced_schema`;
- `20260814090851_rc1_events_advanced_integrity`;
- `20260814091043_rc1_events_advanced_permissions`;
- `20260814091121_rc1_events_advanced_security_workflows`;
- `20260814091147_rc1_events_advanced_legacy_guests`;
- `20260814091512_rc1_events_advanced_performance_hardening`.

Qualquer correção futura deve ser uma nova migration.

## Performance

O Advisor foi executado após as migrations. Foram acrescentados índices nas novas relações e também nas foreign keys já existentes de inscrições, voluntários e parceiros de Eventos. Políticas `FOR ALL` foram separadas em `INSERT`, `UPDATE` e `DELETE` para evitar avaliação permissiva duplicada no `SELECT`.

## Testes

`events_advanced_repository_test.dart` cobre:

- membro comum pode propor mas não gerir operação;
- Road Captain gere roadbook e operação;
- Tesoureiro aprova propostas e gere finanças do evento;
- Responsável de Eventos gere as áreas operacionais avançadas;
- normalização de tipos de evento e cartão 10 + 1 Octanas;
- overview completo em Demo Mode sem depender do Supabase real.
