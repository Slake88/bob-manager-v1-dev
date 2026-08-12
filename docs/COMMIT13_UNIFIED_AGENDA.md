# Commit 13 — Agenda / Calendário Unificado

## Objetivo

Concentrar num único calendário a operação diária do clube sem duplicar os dados
dos módulos existentes.

## Fontes

A função `agenda_calendar_v1` agrega, em tempo real:

- reuniões, prazos e lembretes manuais de `agenda_items`;
- eventos de `events`;
- aniversários e marcos Prospect / Full Colors de `members`;
- jantares do módulo Oficial da Semana;
- validade de documentos;
- cobranças pendentes.

Os registos originais permanecem nas respetivas tabelas.

## Privacidade

- `viewAgenda` controla o acesso geral.
- `manageAgenda` controla criação e edição de itens manuais.
- `viewDirectionAgenda` controla itens reservados à Direção.
- cobranças individuais só aparecem ao próprio membro ou a utilizadores com
  `manageFees`;
- documentos sensíveis só aparecem quando o utilizador já tem
  `viewSensitiveDocuments`;
- eventos em draft só aparecem a quem já pode gerir Eventos.
- nenhum RPC novo é executável por `anon`.

## Ecrã Flutter

Calendário mensal sem plugins adicionais, com filtros:

- Tudo
- Reuniões
- Eventos
- Aniversários
- Marcos
- Jantares
- Prazos
- Cobranças

Utilizadores com `manageAgenda` podem criar reuniões, prazos e lembretes,
definir visibilidade Todos/Direção, prioridade e notificação imediata.

## Notificações

`Notificar agora` cria uma notificação persistente no módulo `agenda`,
respeitando `notification_preferences`. O transporte push físico continua a
usar a infraestrutura de push existente no projeto.

## Migrations

- `20260812101034_rc1_unified_agenda_calendar.sql`
- `20260812101137_rc1_unified_agenda_hardening.sql`
