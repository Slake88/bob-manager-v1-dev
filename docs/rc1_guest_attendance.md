# RC1 — Presença individual de acompanhantes

Esta evolução completa a gestão de participantes em Eventos com controlo individual dos acompanhantes.

- Cada acompanhante mantém estado próprio (`confirmed` / `pending`).
- Cada acompanhante pode ter check-in individual e hora de presença.
- Cada acompanhante pode ter notas operacionais próprias.
- O check-in rápido confirma automaticamente um acompanhante pendente.
- O total de check-ins do evento inclui membros e acompanhantes.
- A gestão de estado, check-in e notas exige `manageEventParticipants` no servidor.
- A remoção/adicionar acompanhantes mantém as permissões de participação já existentes.
- A capacidade do evento continua a contar cada acompanhante uma única vez, independentemente do estado de presença.
