# Commit 20 — Exportação Integral Segura do Clube

## Objetivo

Implementar o requisito aprovado `REQ-RELATÓ-002`: exportação integral do clube, limitada à Direção e integralmente auditada.

O Commit 19 continua responsável pelos relatórios operacionais/filtrados em PDF, Excel e CSV. Este commit cria um mecanismo distinto para arquivo administrativo estruturado e preparação de futuras migrações/importações.

## Autorização

A exportação integral é exclusiva a:

- Presidente;
- Vice-Presidente;
- Administrador;
- Super Admin.

A autorização é validada duas vezes:

1. no Flutter, para navegação e UX;
2. no Supabase, dentro das RPCs `SECURITY DEFINER`.

Ter permissões de relatórios individuais não concede este acesso.

## Backend

Migrations:

- `20260812210544_rc1_secure_full_export.sql`
- `20260812213047_rc1_full_export_rls_bridge.sql`

A primeira cria `public.exports`, que contém apenas metadata da operação:

- utilizador que pediu;
- clube;
- áreas selecionadas;
- opções sensíveis/ficheiros;
- estado;
- contagens;
- dimensão final;
- código de erro seguro;
- timestamps.

O ZIP nunca é guardado no Supabase.

### RPCs

- `begin_club_export_v1`
- `complete_club_export_v1`
- `fail_club_export_v1`

As três exigem autenticação e cargo fixo de Direção.

`begin_club_export_v1` também exige `viewEmergencyData` e `viewSensitiveDocuments` quando a opção de dados altamente sensíveis está ativa.

O `anon` não tem `EXECUTE`.

### Bridge de exportação integral

A segunda migration adiciona `club_export_dataset_v1`, uma RPC `SECURITY DEFINER`
com allowlist fechada dos datasets suportados. A RPC:

- exige exportação própria em estado `running`;
- valida novamente Presidente/Vice-Presidente/Administrador/Super Admin;
- garante que o dataset pertence a uma área selecionada;
- exige `include_sensitive=true` e as permissões sensíveis para datasets protegidos;
- pagina no máximo 1000 linhas por chamada;
- expõe apenas as colunas explicitamente aprovadas.

Desta forma, a exportação integral não depende das RLS operacionais de cada módulo,
mas também não cria acesso normal/browse às tabelas.

Para ficheiros, `club_export_file_access_v1` e a policy
`club_export_files_select` dão leitura temporária apenas enquanto existe uma
exportação própria `running`, com `include_files=true`, para o respetivo clube e
área. A janela máxima dessa autorização temporária é de duas horas. Documentos
sensíveis continuam a exigir a opção sensível e as permissões adicionais.

### Auditoria

O início, conclusão e falha são registados em `audit_log`.

A auditoria não guarda:

- conteúdo do ZIP;
- CSVs;
- passwords;
- tokens;
- payloads exportados;
- mensagens de erro arbitrárias.

Em caso de falha é guardado apenas um `error_code` normalizado.

## Formato

Formato nativo:

`bob-export-v1`

Nome:

`BOB_Export_Integral_YYYYMMDD_HHmm.zip`

Estrutura:

```text
manifest.json
membros/
tesouraria/
financeiro/
quotas/
euromilhoes/
eventos/
inventario/
documentos/
comunicacao/
agenda/
oficial_semana/
configuracao/
auditoria/
ficheiros/   # apenas quando solicitado
```

Cada dataset é CSV UTF-8 com BOM, `;` e escaping RFC-style de aspas.

O `manifest.json` contém:

- versão;
- data UTC;
- id da exportação;
- identificação não secreta do clube;
- áreas;
- opções;
- datasets e contagens;
- ficheiros incluídos e tamanhos;
- exclusões de segurança.

## Privacidade

A exportação normal de membros não contém NIF, morada, contacto de emergência nem notas privadas.

Quando a opção sensível é explicitamente ativada, estes campos passam para:

`membros/dados_sensiveis.csv`

Documentos `sensitive=true` são igualmente separados e só entram com a opção protegida.

Nunca são incluídos:

- passwords ou dados de sessão Auth;
- `service_role`;
- tokens/dispositivos push;
- payloads completos de `audit_log`;
- payloads OCR brutos;
- informação interna de notificações.

## Ficheiros físicos

A opção `Incluir ficheiros armazenados` usa o cliente autenticado e as políticas de Storage/RLS existentes.

Buckets conhecidos suportados:

- `member-photos`
- `member-maintenance`
- `club-documents`
- `financial-documents`
- `inventory-media`

Não existe bypass com `service_role`.

Para proteger memória em Android/iOS/Web, a soma de CSVs + ficheiros de entrada é limitada a 200 MB. Se um ficheiro selecionado não puder ser lido, a exportação falha em vez de declarar um backup incompleto como concluído.

## Áreas exportadas

### Membros

- membros;
- motas;
- cargos;
- histórico de estados;
- timeline;
- patches;
- manutenção;
- metadata dos anexos;
- dados sensíveis opcionais.

### Tesouraria

- contas;
- categorias;
- centros de custo;
- movimentos.

### Pedidos & Pagamentos

- pedidos;
- metadata de anexos;
- metadata de documentos ligados a movimentos.

### Quotas

- planos;
- obrigações;
- pagamentos.

### Euromilhões

- participantes;
- sorteios;
- chaves;
- participações;
- resultados;
- cobranças;
- multas;
- prémios.

### Eventos

- eventos;
- inscrições;
- voluntários;
- parceiros.

### Inventário

- produtos e variantes;
- localizações e saldos;
- movimentos;
- encomendas/linhas/pagamentos;
- património, imagens, kits e componentes dos kits;
- eventos/empréstimos/manutenção de património;
- categorias, preços e visibilidade;
- inventários físicos e respetivas linhas;
- operações/sessões do Bar.

### Documentos

- metadata normal;
- metadata sensível opcional;
- ficheiros opcionais.

### Comunicação

- comunicados;
- confirmações de leitura.

### Agenda / Oficial da Semana

- itens da agenda;
- jantares;
- rotação;
- ausências;
- pedidos de troca.

### Configuração

- identificação do clube;
- cargos;
- matriz de permissões;
- parâmetros;
- memberships;
- exceções individuais.

### Auditoria

Apenas metadata essencial:

- id;
- actor;
- entidade;
- ação;
- data.

Os objetos `before_data`, `after_data` e `data` não são exportados.

## Flutter

Novos componentes:

- `core/club_export.dart`
- `repositories/club_export_repository.dart`
- `repositories/club_export_specs_members_finance.dart`
- `repositories/club_export_specs_operations.dart`
- `repositories/club_export_specs_support.dart`
- `services/club_export_service.dart`
- `screens/club_export_screen.dart`
- `screens/reports_hub_screen.dart`

O Centro de Relatórios mostra a Exportação Integral apenas quando o cargo fixo a permite.

A navegação do módulo Relatórios também reconhece esse direito fixo independentemente das permissões de relatórios individuais.

## Dependência ZIP

`archive: ^4.0.9`

A versão já se encontrava resolvida no lockfile como dependência transitiva; passa a ser uma dependência direta do módulo mobile.

## Testes

Cobertura adicionada para:

- matriz fixa de acesso;
- exclusão de campos altamente sensíveis;
- sanitização contra path traversal;
- BOM/CSV/escaping;
- criação real de ZIP com `manifest.json`.

O catálogo Dart e a allowlist SQL foram comparados automaticamente: ambos
contêm exatamente 72 datasets.

Foi também feito um teste transacional como `authenticated` com o Super Admin
real, usando `ROLLBACK`, para validar início da exportação, leitura via
`club_export_dataset_v1` e autorização temporária de ficheiros sem deixar
registos de teste nem auditoria residual.

## Fora do Commit 20

- importação/restauro do ZIP;
- reversão de importações;
- exportações agendadas;
- upload automático do backup para Storage;
- backups server-side;
- encriptação/password do ZIP.

Esses pontos devem ser tratados em commits próprios, começando pelo Assistente de Importação previsto para o Commit 21.
