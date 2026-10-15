# Commit 28 — Inventário Avançado

## Objetivo

Completar os requisitos de inventário avançado sem substituir a fundação existente de Loja, localizações, movimentos, transferências e inventário físico.

## Entregue

### Reservas

- qualquer membro com acesso ao inventário pode reservar stock em seu próprio nome;
- a reserva não representa pagamento nem venda;
- prazo máximo fixo de 30 dias;
- o membro pode cancelar a própria reserva;
- o responsável de inventário pode libertar reservas;
- o stock reservado é refletido em `inventory_stock_balances` e nos agregados de produto/variante;
- o stock disponível exclui reservas e lotes expirados/em quarentena.

### Libertação automática

- extensão `pg_cron` ativada;
- job `bob-inventory-advanced-hourly` executa aos 5 minutos de cada hora;
- reservas vencidas são libertadas automaticamente no servidor;
- o mesmo job atualiza o estado dos lotes pela validade e quantidade.

### Lotes e validades

- receção de stock por lote, artigo/variante e localização;
- data de receção, validade opcional, custo unitário, fornecedor e notas;
- estados `active`, `expired`, `depleted` e `quarantined`;
- custos e lotes restritos a `manageInventory`;
- alertas Mobile First para lotes com validade nos próximos 30 dias e lotes expirados.

### Quebras e perdas

- registo de quebra, validade, dano, perda ou outro motivo;
- lote opcional; sem lote explícito, o consumo de lotes segue prioridade pela validade mais próxima;
- redução atómica do stock por localização;
- movimento de stock criado com tipo `loss`;
- histórico preservado em `stock_breakages`.

### Mobile First

O módulo Inventário mantém toda a área anterior em **Geral** e acrescenta **Stock avançado** com:

1. Reservas;
2. Lotes & Validades;
3. Quebras.

A área avançada apresenta indicadores rápidos de reservas ativas, reservas próximas da expiração, lotes próximos da validade, lotes expirados e quebras do mês, respeitando as permissões do utilizador.

## Segurança

- RLS ativo em `stock_reservations`, `stock_lots` e `stock_breakages`;
- zero privilégios `anon` nas novas tabelas e RPCs;
- helpers internos não executáveis por `authenticated`;
- membro lê apenas as próprias reservas;
- lotes, custos e quebras exigem `manageInventory`;
- operações de escrita são feitas por RPCs atómicos com validação de clube, artigo, variante, localização, membro e quantidade.

## Migrations

- `20260830175121_rc1_inventory_advanced_schema.sql`
- `20260830175159_rc1_inventory_advanced_reservations.sql`
- `20260830175243_rc1_inventory_advanced_lots_breakages.sql`
- `20260830175257_rc1_inventory_advanced_maintenance.sql`
- `20260830175500_rc1_inventory_advanced_performance_hardening.sql`

## Validação prevista

- testes de permissões membro vs responsável de inventário;
- reserva por 30 dias e cancelamento em modo demonstração;
- receção de lote e registo de quebra em modo demonstração;
- helpers de estados/motivos;
- `flutter analyze`;
- `flutter test`;
- build Flutter Web em CI.
