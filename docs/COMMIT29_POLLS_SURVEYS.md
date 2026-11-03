# Commit 29 — Votações / Inquéritos

## Objetivo

Implementar `REQ-COMUNI-002` dentro do módulo Comunicação, preservando o ecrã e os fluxos atuais de Comunicados.

## Modelo funcional

- dois tipos: **Votação** e **Inquérito**;
- votação **anónima na aplicação** ou identificada;
- escolha única ou múltipla;
- estados `draft`, `published`, `closed` e `cancelled`;
- abertura e fecho por data/hora, com fecho opcional;
- resultados ocultos até ao fecho por defeito, inclusive para gestores, com opção explícita de resultados em tempo real;
- votos submetidos são imutáveis;
- Prospects não são elegíveis; os restantes membros ativos com `viewCommunication` podem votar;
- gestão usa a permissão existente `manageCommunication`.

## Privacidade e integridade

A votação anónima conserva internamente o `profile_id` apenas para garantir unicidade/elegibilidade. A política RLS impede a gestão de consultar a associação pessoa → opção em votações anónimas. A aplicação apresenta resultados através de `poll_result_counts`, uma tabela agregada mantida por trigger.

Para votações identificadas, a gestão pode consultar os registos de voto ao nível da base, respeitando RLS.

A escolha única é protegida por índice único parcial em `(poll_id, profile_id)`, definido pelo trigger `poll_vote_validate_internal_v1`; desta forma dois pedidos concorrentes não conseguem criar um segundo voto.

## Supabase

Tabelas:

- `polls`
- `poll_options`
- `poll_votes`
- `poll_result_counts` — camada agregada de resultados

Segurança:

- RLS ativo nas quatro tabelas;
- zero privilégios `anon`;
- votos sem `UPDATE` nem `DELETE` para `authenticated`;
- helpers `poll_*_internal_v1` são `SECURITY DEFINER` apenas para triggers e não têm `EXECUTE` para `authenticated`;
- políticas usam as permissões existentes do clube;
- resultados intermédios só são legíveis quando `show_results_before_close=true`; caso contrário ficam bloqueados até ao fecho/fim da janela, também para gestores;
- foreign keys do Commit 29 têm índices de cobertura.

Migrations reais:

- `20260830182741_rc1_polls_surveys_schema_security.sql`
- `20260830182825_rc1_polls_surveys_policy_hardening.sql`
- `20260830182954_rc1_polls_surveys_performance_hardening.sql`
- `20260830183032_rc1_polls_surveys_rls_qualification_fix.sql`
- `20260830183857_rc1_polls_surveys_result_visibility_hardening.sql`

## Mobile First

Comunicação passa a ter:

1. **Comunicados** — ecrã anterior preservado;
2. **Votações** — área nova.

A área Votações tem as duas vistas pedidas no requirements:

- **Votações**: abertas, agendadas, fechadas e, para gestores, rascunhos;
- **Resultados**: votações cujos resultados estão disponíveis.

O detalhe mostra opções como escolha única/múltipla, confirmação de voto imutável e resultados por contagem/percentagem. Gestores podem criar/editar rascunhos, publicar, encerrar e cancelar.

## Validação backend

Foi executado um teste real dentro de transação com `ROLLBACK`:

- criação de rascunho;
- duas opções;
- publicação;
- voto;
- resultado agregado = 1;
- rollback sem dados persistentes.

Foi também testada a tentativa de segundo voto em escolha única; a base manteve apenas 1 voto, confirmando a restrição concorrente.

## Testes Flutter

- `POLL-UNIT-01`: elegibilidade e permissões;
- `POLL-INT-01`: criar → publicar → votar → impedir segundo voto → fechar → resultado;
- escolha múltipla;
- helpers de agenda, estado e visibilidade de resultados.
