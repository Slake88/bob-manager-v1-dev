# BOB Manager v1.0 DEV

Repositório integral gerado a partir do Master Blueprint, Arquitetura Técnica,
Esquema Definitivo e Matriz de Rastreabilidade v1.0.

## Validação

```powershell
.\scripts\validate.ps1
```

## Execução

```powershell
.\scripts\run_dev.ps1
```

A aplicação arranca em modo demonstração quando `config/dev.json` não existe.

## RC1

A gestão de eventos inclui CRUD base, confirmação segura de eliminação na Agenda e na Gestão, filtragem por estado e atualização forçada dos dados ao alternar entre os separadores Agenda e Gestão. A sincronização é feita no módulo ativo `EventsModuleV2Screen`, preservando o mês selecionado na Agenda e o filtro de estado na Gestão.

A ficha base do evento permite definir nome, tipo de evento, local, início, fim opcional, descrição/notas, orçamento, capacidade prevista e estado. O repositório valida que o fim é posterior ao início, que a capacidade é um inteiro positivo e que o tipo de evento pertence ao catálogo suportado. O detalhe operacional na Gestão apresenta também o tipo, estado, local, início, fim, capacidade prevista, orçamento e descrição/notas do evento. A lista de Gestão permite editar diretamente a ficha base através do ícone de edição de cada evento, atualizando de imediato a lista e mantendo a sincronização com a Agenda.

A operação do evento disponibiliza agora a gestão integrada de participantes e acompanhantes através da mesma ficha V2 usada na Agenda, permitindo consultar inscrições, adicionar ou remover membros, associar vários acompanhantes e removê-los individualmente, mantendo as permissões e regras de segurança já existentes na base de dados. Cada inscrição pode ainda ser marcada como Confirmada ou Pendente, receber notas operacionais e ter o check-in registado ou anulado com data e hora, incluindo contagem imediata das presenças na ficha do evento.

Os voluntários são geridos na ficha de participantes e ficam disponíveis na Operação do evento para atribuição a tarefas e turnos. As tarefas suportam descrição, prioridade, estado, prazo, notas, edição, eliminação e vários voluntários atribuídos. Os turnos suportam área, início e fim, número de pessoas necessárias, estado, notas, edição, eliminação e atribuição de voluntários, incluindo o estado individual de presença (Atribuído, Confirmado, Presente, Ausente ou Cancelado). A estrutura de dados e as políticas RLS necessárias já existiam, pelo que esta integração não exigiu migração da base de dados.
