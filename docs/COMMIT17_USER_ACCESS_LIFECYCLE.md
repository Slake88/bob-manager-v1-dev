# Commit 17 — Gestão de contas e acessos dos utilizadores

## Objetivo

Completar o ciclo administrativo de acesso ao BOB Manager sem expor credenciais privilegiadas no Flutter.

O Commit 17 permite:

- identificar membros sem conta;
- enviar convite de acesso por email;
- distinguir convite enviado, conta ativa e conta bloqueada;
- reenviar um convite ainda não utilizado;
- enviar reposição de palavra-passe;
- alterar o perfil/cargo de acesso;
- bloquear e desbloquear login;
- concluir a palavra-passe a partir do fluxo de convite ou recuperação;
- auditar as operações administrativas.

## Auditoria inicial

Antes deste commit o `AuthService` tratava apenas de login, restauro da sessão, logout e hidratação de permissões.

Não existia gestão de `auth.users` na aplicação nem um fluxo para criar, convidar, recuperar, bloquear ou reativar contas.

Foi também encontrada uma inconsistência entre a aplicação e a base de dados: a matriz de permissões já conhecia cargos como Presidente, Vice-Presidente, Road Captain, Prospect e Responsável Euromilhões, mas a constraint antiga de `club_memberships.access_role` ainda recusava vários desses valores.

## Permissão dedicada

Foi criada a permissão dinâmica:

`manageUserAccess`

Por defeito fica ativa para:

- `president`;
- `vice_president`;
- `admin`;
- `administrator`.

Os restantes cargos recebem `false` por defeito e podem ser alterados posteriormente pela matriz de permissões.

O Super Admin continua a ter acesso total independentemente da matriz.

A Administração pode agora ser aberta por quem tenha `manageSettings` **ou** `manageUserAccess`. Desta forma a gestão de contas pode ser delegada sem conceder acesso aos parâmetros gerais do clube.

## Migration

Migration aplicada no Supabase:

`20260812161845_rc1_user_access_lifecycle_v2.sql`

A migration:

1. alinha a constraint `club_memberships_access_role_check` com os cargos usados na aplicação;
2. introduz `manageUserAccess` na matriz dinâmica;
3. mantém os triggers de auditoria e timestamps ativos;
4. suspende apenas o trigger de Activity Feed durante o seed técnico da nova permission key, porque migrations não possuem `auth.uid()`; o trigger é reativado antes do fim da própria transação.

Uma primeira tentativa de migration foi rejeitada pelo próprio trigger de Activity Feed e revertida integralmente. Essa tentativa não ficou registada no histórico de migrations. A versão efetivamente aplicada é a `v2` acima.

## Edge Function administrativa

Foi criada e publicada:

`user-access-admin`

Configuração:

- `verify_jwt = true`;
- utiliza o JWT do utilizador para verificar `manageUserAccess` no clube;
- utiliza a service role apenas dentro da Edge Function para operações administrativas de Supabase Auth;
- nenhuma service role key é enviada ou guardada no Flutter.

### Estados apresentados

- `no_access` — membro sem conta associada;
- `invited` — convite enviado, sem primeiro login;
- `active` — conta ativa;
- `blocked` — membership/profile inativo ou conta Auth banida.

### Operações

- `list`;
- `invite`;
- `resend_invite`;
- `send_password_reset`;
- `change_role`;
- `block`;
- `unblock`.

## Convite e ativação

Ao convidar um membro:

1. é criado o utilizador através da API administrativa do Supabase Auth;
2. `profiles` é criado/atualizado;
3. `club_memberships` recebe o perfil de acesso escolhido;
4. `members.profile_id` liga o membro à conta;
5. o convite recebe metadata `must_set_password=true`;
6. após abrir o convite, a app apresenta o ecrã para definir a palavra-passe;
7. depois de concluído o setup, `must_set_password` passa a `false`.

Se a criação Auth for bem-sucedida mas a ligação posterior à base de dados falhar, a Edge Function tenta remover a conta Auth recém-criada, evitando utilizadores órfãos.

## Recuperação de palavra-passe

O ecrã de login passa a ter `Esqueci a palavra-passe`.

A recuperação usa o fluxo nativo Supabase Auth. Quando a app recebe o evento `passwordRecovery`, apresenta o mesmo ecrã seguro de definição de nova palavra-passe utilizado pela ativação do convite.

Administradores com `manageUserAccess` também podem disparar a reposição a partir da ficha da conta.

## Bloqueio e desbloqueio

Bloquear atua em três níveis:

- `club_memberships.active = false`;
- `profiles.active = false`;
- ban na conta Supabase Auth.

Desbloquear repõe membership e profile como ativos e remove o ban Auth.

O `AuthService` passou ainda a rejeitar explicitamente um `profiles.active = false` durante a hidratação da sessão.

## Proteções administrativas

- o ecrã não permite criar ou atribuir `super_admin`;
- a conta `super_admin` não pode ser bloqueada nem ter o cargo alterado por este fluxo;
- o utilizador autenticado não pode bloquear nem alterar a própria conta através do ecrã administrativo;
- todas as operações validam o clube e `manageUserAccess` novamente na Edge Function, não apenas na UI.

## Auditoria

A Edge Function grava em `audit_log` as operações de acesso relevantes, incluindo:

- convite;
- reenvio de convite;
- envio de reset;
- alteração de cargo;
- bloqueio;
- desbloqueio.

## Flutter

Foram adicionados:

- `UserAccessRepository`;
- `UserAccessScreen`;
- `PasswordSetupScreen`;
- integração em Administração;
- fluxo self-service de reposição no Login;
- tratamento de `AuthChangeEvent.passwordRecovery` no bootstrap;
- nova permissão `manageUserAccess`.

## Testes

Foram adicionados testes para confirmar:

- que `manageUserAccess` pode ser delegado sem `manageSettings`;
- que Super Admin continua com acesso total;
- que os cargos agora aceites pela constraint são reconhecidos por `AppRole`.

## Critério de fecho

- migration aplicada no Supabase;
- Edge Function `user-access-admin` ativa com JWT obrigatório;
- `manageUserAccess` validada na matriz;
- constraint de cargos validada;
- hardening do Commit 15 preservado (`anon SECURITY DEFINER = 0`);
- Security Advisor revisto;
- `flutter analyze` verde;
- `flutter test` verde;
- Flutter Web build verde;
- Flutter CI verde no GitHub.
