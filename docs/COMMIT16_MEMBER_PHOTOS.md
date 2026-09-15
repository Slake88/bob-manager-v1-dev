# Commit 16 — Fotografia privada dos membros

## Objetivo

Completar a fotografia do perfil de membro prevista na RC1, reutilizando a infraestrutura de imagens já existente e mantendo os ficheiros pessoais fora de buckets públicos.

## Base existente reutilizada

Antes deste commit já existiam:

- `members.photo_path` no Supabase;
- `ImageProfiles.member`;
- `ImagePipelineService` e `DefaultImageProcessor`;
- `image_picker` e `image` nas dependências Flutter;
- permissões dinâmicas `viewMembers` e `manageMembers`.

O processador de imagem reencoda a fotografia e, por esse motivo, não conserva EXIF/GPS da imagem original.

## Supabase Storage

Migration aplicada:

`20260812155155_rc1_member_photo_storage.sql`

Foi criado o bucket privado `member-photos` com:

- `public = false`;
- limite de 5 MB por objeto;
- MIME permitido: `image/jpeg`;
- leitura apenas para utilizadores autenticados com `viewMembers` no clube correspondente;
- insert/update/delete apenas para utilizadores autenticados com `manageMembers` no clube correspondente.

Estrutura dos caminhos:

`<club_id>/members/<member_id>/photo_<versao>.jpg`

`<club_id>/members/<member_id>/thumb_<versao>.jpg`

A fotografia principal é guardada em `members.photo_path`. As imagens são apresentadas através de URL assinada temporária, porque o bucket não é público.

## Substituição segura

Uma fotografia nova é carregada para um caminho versionado. O `photo_path` do membro só é alterado depois de fotografia e miniatura estarem no Storage. Só depois da atualização bem-sucedida é feita a limpeza best-effort da versão anterior.

Desta forma, uma falha de upload não remove a fotografia válida que já estava associada ao membro.

## Flutter

Foram adicionados:

- `MemberPhotoRepository` para upload, remoção e URLs assinadas;
- `MemberPhotoAvatar` reutilizável com fallback para a inicial do nome;
- fotografia na listagem de membros;
- fotografia em maior dimensão no detalhe do membro;
- ações Câmara, Galeria e Remover fotografia para utilizadores com `manageMembers`;
- indicador de progresso e mensagens de sucesso/erro.

Não foram adicionadas dependências novas.

## iOS

`Info.plist` passa a declarar:

- `NSCameraUsageDescription` abrangendo QR e fotografia autorizada;
- `NSPhotoLibraryUsageDescription` para seleção de fotografia da galeria.

## Segurança

O bucket é privado e as políticas validam simultaneamente:

1. o bucket;
2. a estrutura de caminho `<club>/members/<member>/...`;
3. a existência do membro nesse clube;
4. a permissão dinâmica do utilizador no clube.

A migration não cria funções `SECURITY DEFINER`. Depois da aplicação foi reconfirmado que o número de funções `SECURITY DEFINER` executáveis por `anon` continua em zero.

## Testes

Foram adicionados testes unitários para:

- construção do caminho versionado da fotografia;
- derivação do caminho da miniatura;
- compatibilidade de fallback com caminhos antigos que não seguem o padrão versionado.

## Critério de fecho

- bucket privado e políticas RLS confirmados no Supabase;
- `anon SECURITY DEFINER = 0` preservado;
- Security Advisor revisto;
- `flutter analyze` verde;
- `flutter test` verde;
- build Flutter Web verde;
- Flutter CI verde no GitHub.
