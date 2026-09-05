# Commit 8 — Central de Pedidos, Cobranças e Pagamentos

## Fluxo membro → clube
1. O membro cria um pedido de reembolso.
2. É obrigatório anexar pelo menos um talão/recibo antes da submissão.
3. A Tesouraria pode aprovar, rejeitar ou pedir informação adicional.
4. Depois da aprovação, a Tesouraria escolhe conta e método de pagamento.
5. Transferência/MB Way exigem comprovativo do pagamento do clube.
6. Ao liquidar, é criada automaticamente uma despesa em `treasury_transactions`.

## Fluxo clube → membro
1. Um utilizador com `approveExpenseRequests` cria uma cobrança para um ou vários membros elegíveis.
2. Categorias: Quota, Euromilhões, Cartão Bar e Outro.
3. O membro recebe notificação e pode anexar comprovativo.
4. A Tesouraria valida ou rejeita o comprovativo.
5. Numerário pode ser liquidado diretamente pela Tesouraria.
6. Ao validar, é criada automaticamente uma receita em `treasury_transactions`.

## Segurança e auditoria
- `financial_requests` e `financial_request_attachments` têm RLS.
- O membro só vê os seus processos; gestores autorizados veem todos os processos do clube.
- O bucket `financial-documents` é privado.
- Os novos registos usam `audit_stamp_row_v1` e `audit_capture_row_v1`.
- Helpers internos de notificação/atividade não são executáveis diretamente por `anon` nem `authenticated`.
