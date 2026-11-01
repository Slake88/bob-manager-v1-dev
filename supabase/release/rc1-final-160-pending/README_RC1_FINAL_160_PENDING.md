# RC1-FINAL — proposta de sequência de 160 etapas

**Estado: CANDIDATO PENDENTE, não certificado e não aplicar automaticamente.** Esta pasta fica fora de `supabase/migrations`; os ficheiros `.pending` e `.blocked` não são migrations para `supabase db push`.

## Composição proposta para instalação limpa

A proposta de ordem está em `RC1_FINAL_160_EXECUTION_PROPOSAL.csv` e contém exatamente 160 entradas:

1. 153 migrations-base em `supabase/release/rc1-final-158-candidate/base_migrations`.
2. Quatro correções previamente aprovadas em `supabase/release/rc1-final-158-candidate/release_migrations`, totalizando o baseline de 157 etapas: consolidação R3–R16, restrições de exportação/manutenção e Bar/Inventário R4/R5.
3. Etapa 158: `158A_public_module_permissions.sql.pending`.
4. Etapa 159: `20261031150000_rc1_user_module_preferences.sql.pending`.
5. Etapa 160: `158B_storage_owner_path_guard_R31B.sql.pending`, que exige execução através do contexto autorizado proprietário de `storage.objects`.

A soma proposta é 160. **A composição exata ainda não passou por uma instalação limpa integral; não está certificada.** O ficheiro histórico `RC1_FINAL_EXECUTION_ORDER.csv` da candidata anterior tem 158 linhas e inclui a migration monolítica bloqueada; não usar essa ordem sem filtrar essa linha. A ordem proposta R31B já a exclui.

## Migration monolítica bloqueada

`20261029110000_rc1_module_view_edit_permissions.sql.blocked` preserva exatamente os mesmos bytes da versão que esteve em `supabase/migrations`, SHA-256 `426BC8333EBD68DBBFBC8C4F490B586401FF4492B09193F57721685E8FA1476E`. Ela contém DDL em `storage.objects`, cujo proprietário é `supabase_storage_admin`; a aplicação como `postgres` falhou por ownership. Não executar esta variante. A proposta divide-a em 158A (schema public) e 158B (Storage).

## Storage gerido

A candidata R31B passou no clone local com execução pelo proprietário legítimo. A autorização e o mecanismo suportado para executar a etapa Storage na instalação gerida BOB TESTE ainda não foram confirmados. Não usar `SET ROLE`, trust de Docker, alteração de owner, grants ou memberships como contorno.

## Atualização incremental

A instalação online tem 173 registos de migrations. As 157 etapas-base não devem ser reaplicadas nela. Uma atualização incremental exige reconciliar o ledger com o estado real e definir como aplicar as etapas públicas e Storage sem perda de dados.

## Artefactos e hashes

`SHA256SUMS_RC1_FINAL_160_PENDING.txt` regista os hashes dos componentes desta proposta. R31B: `E68860B9B93774A297BC4755B2C970C91D21DDB6D13BC4DA4B2BB548EADA73DA`; 158A: `F7B3993019F6D0DE93936620988AF071EB3674A938A1B909099B86ECED1B002D`; preferências: `4D4405B64079A516215DD7921BDE407EAE151CBC710C3D20F6948AA462AE655E`. A candidata 158 anterior e os seus artefactos históricos permanecem inalterados.