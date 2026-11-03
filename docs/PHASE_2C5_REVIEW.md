# Fase 2C.5 — preparação explícita de quotas

14/10/2026, Europe/Lisbon. Candidata local sobre rc1-rebuild, base c146a7508ab7322906e0923210fe5df610857ce6. Sem commit/push/deploy ou acesso remoto nesta implementação.

## Comportamento

Abrir, atualizar e navegar entre anos consulta apenas. Alterar configurações ou criar/editar/importar membros não gera dívida. A ação Preparar ano exige confirmação, fica desativada durante execução e oculta em demo/anos passados. A UI usa o ano do dispositivo como conveniência; o servidor decide pelo ano de Europe/Lisbon.

A nova RPC public.prepare_member_fees_year_v1(uuid,integer) exige auth.uid(), has_club_access IS TRUE e manageFees IS TRUE. Permite ano atual e futuros até 2100. Mantém os estados elegíveis prospect/full_color/active, valores configurados e geração anual de mensalidades (incluindo meses anteriores dentro do ano atual). Não atualiza quotas existentes. Inscrição é incluída só se a entrada pertence ao ano preparado: não cria inscrições históricas com preços atuais. Sem correções/backfill de dados.

Helper SECURITY INVOKER em bob_fees_private, sem USAGE/EXECUTE para PUBLIC/anon/authenticated/service_role. Wrapper público SECURITY DEFINER apenas com EXECUTE authenticated; sem service_role pois não existe caller de serviço identificado. Ambos fixam search_path=pg_catalog,public,pg_temp. Lock transacional por clube serializa preparações, incluindo inscrição.

As assinaturas antigas sync_member_fee_obligations_v1(uuid,integer,uuid), generate_monthly_fees(uuid,integer,uuid), generate_member_fees_internal(uuid,integer) ficam como stubs SECURITY INVOKER que falham sem escrever; execução externa revogada. trg_member_fee_autogenerate é removido e a função de trigger antiga fica sem escrita/privilégios externos. Outros triggers e operações de pagamento/reversão não são alterados.

## Ficheiros

- supabase/migrations/20261014100444_rc1_explicit_fee_preparation.sql
- apps/mobile/lib/repositories/fees_repository.dart
- apps/mobile/lib/screens/fees_annual_screen.dart
- apps/mobile/test/fees_phase2c5_test.dart
- supabase/tests/phase2c5_fees_regression.sql
- tools/test_fees_phase2c5.mjs
- docs/PHASE_2C5_SQL_RESULTS.json
- .github/workflows/flutter-ci.yml (contratos HTTP simulados)
- este relatório

## Validação

- Análise Flutter: sem problemas.
- Suite Flutter: 269 aprovados, 12 omitidos em demo.
- Contratos 2C.5 com URL/chave fictícias e HTTP simulado: 2 aprovados; abertura, refresh, navegação, cancelamento, confirmação, permissão e alteração de configurações.
- PostgreSQL local isolado 127.0.0.1:55439, base nova bob_phase2c5_*, catálogo de esquema sem dados reais e migrations 2C.1–2C.4 antes da candidata. Fixtures sintéticas com triggers/RLS reais; auth ausente, clube sem acesso/inativo, permissão/overrides, passado/null/limite, atual/futuro, isolamento de clube, preservação de obrigações após mudança de preço, ACLs, search_path, ausência do trigger e reexecução da migration sem escritas de negócio. Duas ligações concorrentes confirmam ausência de duplicados. Resultado em PHASE_2C5_SQL_RESULTS.json.
- O SQL avulso termina em rollback; o harness conserva apenas fixtures sintéticas na base local descartável para testar concorrência. Endereço fixo, sem parâmetro de URL remota. Adaptadores auth/storage/net locais não equivalem a Supabase completo.
- Build Web release local com DEMO_MODE=true: aprovado, incluindo Wasm dry run. Artefacto não publicado.

## Publicação futura — requer autorização separada

Coordenar backend e Web numa janela controlada: o cliente antigo chama sync_member_fee_obligations_v1 ao carregar quotas e deixará de conseguir fazê-lo após revogação. Não publicar apenas Web porque a nova RPC ainda não existe em produção. Clientes antigos em cache devem recarregar a aplicação. Preparar build/commit candidato para revisão antes de qualquer publicação.

Produção deve receber apenas verificações read-only de catálogo antes/depois; nunca testes SQL transacionais nem invocações de negócio. Não executar geradores para validar o deploy. Reverter a migration antiga reativaria geração implícita e não deve ser um rollback automático.

Património/Tesouraria, drift clubs.slug/profiles.email, passwords comprometidas, sources/ e BOB_Manager_arquitetura.zip preservados.
