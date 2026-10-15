# Commit 9 — Documentos/comprovativos financeiros + galeria

## Objetivo
Associar múltiplos documentos a cada movimento de Tesouraria sem substituir o histórico por um único `document_path`.

## Categorias
- Talão / recibo (`receipt`)
- Comprovativo de pagamento (`payment_proof`)
- Fatura / PDF / outro (`invoice_other`)

## Regras principais
- Os ficheiros continuam no bucket privado `financial-documents`.
- Cada movimento pode ter vários documentos e um documento principal.
- Documentos provenientes da Central de Pedidos & Pagamentos são ligados ao movimento quando este é liquidado, sem duplicar o objeto no Storage.
- Documentos herdados de pedidos ficam protegidos contra eliminação na galeria do movimento.
- Documentos carregados diretamente na Tesouraria podem ser eliminados por utilizadores com permissão financeira adequada.
- O campo legado `treasury_transactions.document_path` passa a refletir o documento principal para compatibilidade.
- Auditoria global é aplicada à nova tabela.
- A origem `bar_ocr` fica reservada para o Commit 11, permitindo preservar cada original individualmente.

## Interface
Ao tocar num movimento em Tesouraria abre-se a página `Documentos do movimento`, com padrão visual inspirado na Galeria 2.2:
- documento principal em destaque;
- miniaturas/documentos secundários;
- abertura de imagem com zoom;
- PDF aberto externamente através de URL assinada;
- carregamento múltiplo;
- escolha da categoria;
- definição do documento principal.
