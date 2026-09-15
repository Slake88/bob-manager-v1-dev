# Commit 27 — Documentos Avançados

## Objetivo

Completar o módulo Documentos da RC1 com arquivo documental versionado, aprovações, OCR, arquivo pessoal privado, galeria de eventos e Cápsula do Tempo/Livro anual, preservando a Biblioteca existente.

## Requisitos cobertos

### REQ-DOCUME-001 — Arquivo, versões, links, aprovações e OCR

- `documents` continua a ser o registo principal.
- `document_versions` mantém todas as versões físicas e identifica a versão atual.
- `document_links` relaciona documentos com entidades do sistema e pode ser gerido no detalhe documental.
- `document_approvals` mantém pedidos e decisões sem apagar histórico.
- `document_ocr` guarda estado, texto extraído e confiança.
- O upload antigo cria automaticamente a versão 1.0.
- Novas versões usam `register_document_version_v1`.
- Aprovações usam `request_document_approval_v1` e `decide_document_approval_v1`.
- OCR usa `start_document_ocr_v1` + Edge Function `document-ocr`.

### REQ-DOCUME-002 — Arquivo pessoal privado / 500 MB

- `documents.scope = personal` identifica o arquivo pessoal.
- `owner_profile_id` define o proprietário.
- RLS permite leitura ao próprio e à direção com autorização documental.
- O limite é 500 MB por utilizador.
- A quota conta todas as versões físicas armazenadas.
- `document_access_log` regista abertura/download através da aplicação.
- O bucket `club-documents` permanece privado.

### REQ-DOCUME-003 — Galeria de eventos

- Fotografias são documentos com `scope = event_gallery` e `event_id`.
- `document_links` regista a ligação explícita ao evento.
- Membros com acesso documental podem consultar e descarregar.
- `manageEventGallery` controla uploads da galeria.
- Formatos de upload da galeria: JPG, PNG e WEBP.

### REQ-DOCUME-004 — Cápsula do Tempo / Livro anual

- `annual_books` define cada livro anual.
- `annual_book_items` guarda os capítulos/itens ordenados.
- O editor suporta rascunho, pré-visualização e publicação.
- Cada livro pode receber capítulos livres, documentos existentes e marcos da `member_timeline` do respetivo ano.
- A estrutura continua preparada para itens ligados a eventos e membros.
- `manageAnnualBooks` controla a edição.

## Mobile First

O módulo Documentos passa a ter cinco destinos:

1. Biblioteca
2. Meu arquivo
3. Aprovar
4. Galeria
5. Livro

A Biblioteca antiga é preservada e permanece acessível pela área de Gestão da Biblioteca.

O detalhe documental concentra:

- versão atual;
- histórico de versões;
- ligações;
- estado de aprovação;
- execução/resultado de OCR;
- abertura segura do ficheiro.

## Permissões novas

- `approveDocuments`
- `runDocumentOcr`
- `manageEventGallery`
- `manageAnnualBooks`

Fallback legado:

- Secretário: workflow documental completo.
- Responsável de Eventos: Galeria.
- Presidente, Vice-Presidente e Administrador: acesso total pelo mecanismo global existente.

A matriz dinâmica `club_role_permissions` continua a ser a fonte de verdade em produção.

## Storage e segurança

- Bucket: `club-documents` (privado).
- Biblioteca geral: `<club_id>/...`
- Versões: `<club_id>/versions/<document_id>/...`
- Arquivo pessoal: `<club_id>/personal/<auth.uid>/...`
- Galeria: `<club_id>/gallery/<event_id>/...`
- A antiga policy de leitura do Storage foi substituída para comparar corretamente `storage.objects.name` com `storage_path`.
- Nenhum privilégio é concedido a `anon` nas tabelas novas.
- RPCs do Commit 27 usam `SECURITY INVOKER`.

## OCR documental

A Edge Function `document-ocr` reutiliza Google Cloud Vision, separada do OCR financeiro.

Suporta:

- JPEG
- PNG
- WEBP
- PDF (primeiras 5 páginas no modo direto)

O ficheiro enviado diretamente ao Vision deve ter menos de 7 MB. O limite geral do bucket continua a ser 20 MB.

O resultado fica persistido em `document_ocr.raw_text`, `confidence` e `status`.

## Migrations Supabase

- `20260814112515_rc1_documents_advanced_schema.sql`
- `20260814112535_rc1_documents_advanced_permissions.sql`
- `20260814112700_rc1_documents_advanced_security_workflows.sql`
- `20260814113020_rc1_documents_advanced_performance_hardening.sql`

## Validação esperada

- `flutter analyze`
- `flutter test`
- Flutter Web build no CI
- Security Advisor sem novos avisos causados pelo Commit 27
- Performance Advisor sem foreign keys novas sem índice

Os avisos históricos de outros módulos não são alterados neste commit para evitar mudanças fora de âmbito.
