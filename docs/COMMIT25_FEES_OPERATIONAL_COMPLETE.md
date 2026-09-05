# Commit 25 — Quotas Operacionais Completas

Quotas passa a suportar recebimentos distribuídos por várias mensalidades, pagamentos parciais, crédito por excesso, isenções, ajustes, reversões e pagamentos comunicados pelo membro.

Regra central: um recebimento cria um único movimento de Tesouraria; a distribuição pelas quotas fica nas allocations.

O Flutter apresenta duas áreas: Operações e Mapa anual. O ecrã anual anterior é preservado e a nova área operacional é Mobile First.

Migrations incluídas: 20260813151110, 20260813151240, 20260813151356, 20260813151451 e 20260813151628.

Os testes cobrem cálculo do saldo, pagamento parcial, distribuição multi-mês, prioridade da dívida mais antiga, excesso em crédito e vencimento.
