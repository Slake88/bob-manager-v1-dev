# Commit 22 — Pesquisa Global Segura

## Objetivo

Implementar o requisito `REQ-PESQUI-001`: pesquisa global segura por membro, mota, matrícula e entidades, sem descarregar tabelas completas para o dispositivo e sem permitir descoberta de módulos/campos sem autorização.

## Âmbito funcional

A Pesquisa Global fica acessível pela lupa no `ShellScreen` para utilizadores autenticados.

Tipos pesquisáveis:

- Membros
- Motas
- Documentos
- Produtos de Inventário/Loja/Bar
- Eventos

A pesquisa aceita pelo menos 2 caracteres e normaliza acentos, espaços e separadores. Exemplo: uma matrícula pode ser procurada com ou sem hífens.

## Segurança

A pesquisa é executada no servidor através de:

- `public.global_search_v1(uuid,text,integer)`

A função:

- exige `auth.uid()`;
- confirma membership ativo no clube;
- limita a pesquisa ao `club_id` recebido;
- limita o texto a 80 caracteres;
- limita a resposta a no máximo 50 resultados;
- tem `EXECUTE` revogado para `anon`;
- não devolve colunas sensíveis.

Permissões por tipo:

- Membros/Motas: `viewMembers`
- Documentos: `viewDocuments`
- Documentos sensíveis: adicionalmente `viewSensitiveDocuments`
- Produtos: `viewInventory`
- Eventos: `viewEvents`

Não foi criada uma nova permissão de “pesquisa”. O acesso continua a ser consequência direta das permissões dos módulos pesquisados.

## Campos deliberadamente excluídos

A resposta da RPC não inclui:

- NIF;
- morada/código postal;
- email;
- telefone;
- contacto de emergência;
- notas privadas;
- custos/preços internos do inventário;
- stock detalhado;
- orçamento de eventos;
- `storage_path` ou outros caminhos de ficheiros;
- payloads de auditoria.

Os documentos sensíveis nem sequer entram nos resultados se o utilizador não tiver `viewSensitiveDocuments`.

## Ranking

Resultados exatos recebem prioridade sobre prefixos e correspondências parciais.

Prioridades relevantes:

- matrícula exata;
- SKU exato;
- alcunha/nome exato;
- início do nome/matrícula;
- correspondência parcial.

## Flutter

Novos ficheiros:

- `apps/mobile/lib/core/global_search.dart`
- `apps/mobile/lib/repositories/global_search_repository.dart`
- `apps/mobile/lib/screens/global_search_screen.dart`
- `apps/mobile/test/global_search_test.dart`

Alterado:

- `apps/mobile/lib/screens/shell_screen.dart`

O ecrã usa debounce de 350 ms para evitar uma chamada ao servidor por tecla.

Os resultados são agrupados por tipo e mostram apenas os campos seguros devolvidos pela RPC.

## Navegação

- Membro: abre diretamente `MemberDetailScreen`.
- Mota: abre diretamente a ficha do membro proprietário.
- Documento: volta a validar a visibilidade pelo `DocumentRepository` e abre por URL assinada quando existe ficheiro; caso contrário abre o módulo Documentos.
- Produto: abre o módulo Património & Inventário.
- Evento: abre o módulo Eventos.

## Demo mode

Sem configuração Supabase a pesquisa remota devolve lista vazia. A funcionalidade de produção depende da RPC e nunca simula uma pesquisa insegura sobre dados locais.

## Migration

- `20260813083645_rc1_secure_global_search.sql`

A migration também instala `unaccent` no schema `extensions` para pesquisa tolerante a acentos.

## Validação Supabase

Teste autenticado executado contra a RPC com sucesso.

Invariantes verificados após a migration:

- `anon` não pode executar `global_search_v1`;
- `authenticated` pode executar;
- a função valida membership e permissões antes de consultar cada módulo.

## Testes Flutter

`global_search_test.dart` cobre:

- normalização de acentos e separadores;
- política de tipos visíveis por permissão;
- parsing da resposta RPC sem utilizar campos extra/sensíveis.

Fecho do commit exige:

- `flutter analyze`
- `flutter test`
- Build Flutter Web
