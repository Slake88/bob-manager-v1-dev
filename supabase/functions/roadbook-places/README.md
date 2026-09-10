# Roadbook Places

Proxy autenticado para pesquisa de locais do Roadbook através da Google Places API (New).

## Configuração

1. Ativar **Places API (New)** no projeto Google Cloud usado pelo BOB Manager.
2. Associar uma conta de faturação ao projeto Google Cloud.
3. Criar uma API key dedicada e restringi-la à **Places API (New)**.
4. Guardar a chave nos secrets das Supabase Edge Functions com o nome `GOOGLE_MAPS_API_KEY`.
5. Manter `verify_jwt = true` no deploy da função.

A chave Google nunca deve ser incluída no código Flutter, no repositório Git ou em `--dart-define`.

## Utilização

O cliente Flutter usa um token de sessão UUID v4 por pesquisa. O autocomplete só é iniciado a partir de 3 caracteres e o detalhe do local é pedido apenas depois da seleção. A função devolve apenas os campos necessários ao Roadbook: texto/endereço e coordenadas.

No editor de paragens, o campo **Local** apresenta sugestões Google diretamente após pelo menos 3 caracteres e cerca de 450 ms sem nova escrita. A lupa mantém a pesquisa dedicada e continua a ser possível guardar um local escrito manualmente; nesse caso não são mantidas coordenadas Google antigas.

A função exige a permissão `manageEventRoadbook` para o clube indicado no pedido.
