# RC1 — Plano de teste funcional real

## Arranque

Executar a aplicação com:

```powershell
cd C:\project\BOB_Manager_v1_0_DEV\apps\mobile
flutter run -d chrome `
  --dart-define=SUPABASE_URL=O_TEU_SUPABASE_URL `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=A_TUA_CHAVE_PUBLICA
```

Critérios:

- não aparece o indicador de modo Demo;
- o login é apresentado sem erros técnicos;
- uma sessão válida é recuperada após atualizar a página;
- terminar sessão regressa ao login.

## Dashboard

- abre sem ecrã vermelho;
- mostra membros, Prospects, quotas, eventos, stock e documentos;
- os valores financeiros aparecem apenas para cargos autorizados;
- os totais correspondem aos dados existentes no Supabase.

## Membros

- listar membros;
- pesquisar por nome, alcunha, número, mota e matrícula;
- abrir detalhe;
- criar, editar e desativar/eliminar conforme permissões;
- adicionar e consultar motas;
- confirmar que um membro comum não altera dados de terceiros.

## Tesouraria

- listar todas as contas e saldos;
- criar receita;
- criar despesa com centro de custo obrigatório;
- transferir entre duas contas diferentes;
- impedir saldo negativo fora da conta Caixa;
- criar, renomear e desativar contas apenas com cargo autorizado;
- confirmar que o Tesoureiro movimenta dinheiro mas não gere contas.

## Quotas

- listar obrigações;
- criar quota para um membro;
- registar pagamento parcial;
- registar pagamento final;
- confirmar movimento automático na conta Quotas;
- impedir pagamento superior ao saldo pendente.

## Euromilhões

- listar participantes;
- adicionar participante ligado a membro;
- validar cinco números e duas estrelas sem repetição;
- registar pagamento;
- confirmar entrada automática na conta Euromilhões.

## Eventos

- criar e editar evento;
- adicionar participante e acompanhante;
- adicionar voluntário e função;
- confirmar receitas, despesas e resultado por evento;
- validar permissões de Eventos, Secretaria e Road Captain.

## Inventário

- criar e editar produto;
- registar entrada, saída e ajuste;
- reservar e libertar stock;
- impedir venda de stock indisponível ou reservado;
- registar venda e confirmar receita automática na conta Club House;
- confirmar alerta de stock mínimo.

## Documentos

- carregar PDF ou imagem;
- abrir através de URL temporária;
- editar metadados;
- validar documento sensível com dois cargos diferentes;
- testar alerta de validade;
- eliminar documento e confirmar remoção do Storage.

## Comunicação

- criar comunicado imediato;
- criar comunicado agendado;
- testar audiência;
- confirmar leitura com um membro;
- impedir confirmação duplicada;
- confirmar que comunicados expirados deixam de aparecer ao membro comum.

## Administração

- criar e editar configuração;
- consultar auditoria;
- confirmar que membro comum não acede;
- verificar registo de utilizador, ação e data.

## Registo de resultado

Para cada falha guardar:

- módulo;
- ação executada;
- mensagem apresentada;
- captura de ecrã;
- cargo do utilizador;
- hora aproximada;
- se o problema desaparece após atualizar a página.

Um bloco só é aprovado quando não produz ecrã vermelho, a alteração aparece após atualização e as permissões são respeitadas por dois cargos diferentes.
