# Commit 11 — OCR Financeiro / Bar

## Motor OCR principal

O OCR do BOB Manager usa Google Cloud Vision `DOCUMENT_TEXT_DETECTION`.

- processamento no servidor através da Edge Function `financial-ocr`;
- endpoint europeu (`eu-vision.googleapis.com`);
- JPG/JPEG, PNG, WEBP e PDF;
- PDF síncrono: até 5 páginas por pedido;
- neste fluxo direto, ficheiros enviados ao Vision são limitados a cerca de 7 MB para respeitar o limite do pedido JSON;
- os documentos financeiros continuam a poder ter até 20 MB; apenas a leitura OCR direta pode pedir compressão.

## Secrets necessários

No Supabase Edge Functions / Secrets:

- `GOOGLE_VISION_API_KEY`
- `GOOGLE_CLOUD_PROJECT_ID`

A API key deve ficar apenas no Supabase. Nunca deve ser colocada no Flutter nem no Git.

## Estruturação dos dados

O Google Cloud Vision extrai o texto. O BOB Manager aplica regras determinísticas para propor:

- fornecedor;
- NIF/NIPC;
- número do documento;
- data;
- moeda;
- subtotal;
- IVA;
- total;
- método de pagamento;
- linhas/artigos;
- confiança e avisos.

A leitura é sempre uma proposta para revisão humana. O OCR não grava automaticamente valores contabilísticos.

## Bar

Um documento pode conter várias linhas. Na confirmação:

- cada linha confirmada atualiza o stock do artigo associado;
- é criada uma única despesa de Tesouraria para o total do documento;
- o documento original fica ligado à transação financeira;
- toda a operação é transacional.

## Financeiro

Nos documentos de uma transação, o OCR pode extrair dados para apoio à conferência, mas não altera automaticamente o movimento existente.

## OpenAI

OpenAI deixou de ser requisito do Commit 11 e não é chamada pela Edge Function atual.

A arquitetura mantém `provider` e `model` genéricos para permitir, no futuro, um enriquecimento opcional por OpenAI ou outro fornecedor sem redesenhar a base de dados.

## Segurança

- Edge Function com JWT obrigatório.
- Jobs do Bar exigem `manageBar`.
- Jobs financeiros exigem `createTreasuryMovement` ou `approveExpenseRequests`.
- Os novos RPCs não são executáveis por `anon`.
- Credenciais Google ficam exclusivamente nos secrets server-side.

## Migrations

- `20260811202432_rc1_financial_ocr_foundation.sql`
- `20260811202501_rc1_bar_ocr_confirmation.sql`
- `20260811204001_rc1_financial_ocr_hardening.sql`

Estas migrations já foram aplicadas no projeto remoto durante a construção do Commit 11.
