# Commit 10 — Notificações push + centro persistente

## Objetivo

Consolidar a tabela `notifications` como caixa persistente por utilizador e acrescentar entrega push por dispositivo através de Firebase Cloud Messaging (FCM), sem perder notificações quando a entrega externa falha.

## Fluxo

1. O domínio cria uma linha em `notifications`.
2. O utilizador vê sempre a notificação na caixa interna quando o módulo está ativo nas preferências.
3. Se `push_enabled=true` e existir um dispositivo FCM ativo, o trigger cria uma linha por dispositivo em `push_deliveries`.
4. `pg_net` chama a Edge Function `push-dispatch` de forma assíncrona.
5. A Edge Function valida a capability aleatória da entrega, reclama atomicamente a linha, envia por FCM HTTP v1 e grava `sent`, `failed`, `deferred` ou `skipped`.
6. Tokens FCM explicitamente inválidos são desativados no servidor.

## Segurança

- Tokens de dispositivo ficam em `push_devices` com RLS de próprio utilizador.
- O cliente nunca recebe credenciais de servidor Firebase.
- `claim_push_delivery_v1`, `complete_push_delivery_v1` e funções internas só podem ser executadas pelo `service_role`/triggers.
- A Edge Function não aceita um ID isolado: exige `delivery_id + dispatch_token` gerados pela base de dados.
- A notificação persistente não depende do sucesso do push.

## Configuração Firebase necessária para entrega real

A infraestrutura pode existir sem Firebase configurado. Nesse estado a caixa interna funciona normalmente e a Edge Function marca tentativas como `deferred`.

No cliente Flutter são usados `firebase_core` e `firebase_messaging`. A instalação deve fornecer os `dart-define` Firebase descritos em `AppConfig`, ou ser adaptada posteriormente para o `firebase_options.dart` produzido por `flutterfire configure`.

No Supabase é necessário guardar como secret da Edge Function:

`FCM_SERVICE_ACCOUNT_JSON=<JSON completo da service account Firebase>`

Nunca colocar este JSON no Git.

Para iOS, ativar Push Notifications e Background Modes/Remote notifications no Xcode e associar a chave APNs ao projeto Firebase. Para Android 13+ o utilizador terá de conceder a permissão de notificações.

## Centro persistente

- badge global de não lidas;
- filtros Todas / Não lidas / Prioritárias;
- arquivo e restauro;
- marcar individual ou todas como lidas;
- preferências por módulo para caixa interna e push;
- navegação para o módulo indicado em `action_route`;
- atualização periódica do badge e atualização imediata quando chega uma mensagem FCM em foreground.
