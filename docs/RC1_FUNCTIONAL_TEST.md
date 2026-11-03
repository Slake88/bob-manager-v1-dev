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


## Web RC1 — Produção

Estado: **validado funcionalmente em 01/09/2026** no ambiente real de produção.

- aplicação publicada em `https://bobmanager.blueonblack.pt`;
- domínio personalizado e HTTPS ativos sem avisos de segurança;
- frontend Flutter Web publicado por GitHub Pages em modo real, ligado ao Supabase;
- login com credenciais reais concluído com sucesso;
- terminar sessão regressa corretamente ao login;
- pedido de recuperação de palavra-passe envia o email do Supabase Auth;
- link de recuperação abre o ecrã `Definir nova palavra-passe`;
- tentativa de reutilizar a palavra-passe atual é recusada;
- nova palavra-passe é aceite e permite entrar sem erro;
- após terminar sessão, novo login com a nova palavra-passe funciona corretamente;
- fluxo de recuperação de palavra-passe validado de ponta a ponta.

Resultado dos testes Web de produção: **aprovado**.

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

## BAR V4

Estado: **validado funcionalmente em 31/08/2026** no ambiente real ligado ao Supabase.

- BAR disponível diretamente na navegação principal;
- separadores Stock, Venda e Movimentos carregam sem ecrã vermelho;
- criar e editar artigo do BAR;
- configurar embalagem/unidade base e conversão de stock;
- configurar múltiplas formas de venda no mesmo artigo, incluindo Shot e Dose;
- confirmar que Shot e Dose descontam do mesmo stock físico;
- configurar quantidade consumida por forma de venda;
- configurar preço Público e preço Membro por forma de venda;
- selecionar Público ou Membro na venda e aplicar automaticamente a tabela correta;
- selecionar membro existente quando a venda é a preço de membro;
- usar conta/nome de grupo quando aplicável;
- configurar o valor do Jantar em Configurações e utilizá-lo automaticamente na venda;
- adicionar item genérico Outro com descrição, quantidade e valor;
- concluir venda e confirmar baixa automática de stock;
- confirmar que uma venda com várias formas do mesmo produto não permite ultrapassar o stock disponível;
- confirmar criação de uma única receita automática na Tesouraria/Club House;
- confirmar método de pagamento e total da venda;
- confirmar que venda concluída mantém histórico da forma de venda, quantidade de stock consumida e preço aplicado;
- confirmar utilizador, data e hora nos Movimentos do BAR;
- confirmar múltiplas fotografias de cartão de consumo;
- confirmar que OCR apenas cria sugestões e nunca altera stock/Tesouraria antes da confirmação;
- confirmar que OCR distingue Shot/Dose apenas quando a informação é inequívoca;
- confirmar rollback transacional em caso de stock insuficiente;
- confirmar persistência dos dados após atualização;
- confirmar que a Auditoria regista utilizador, data/hora e valores antes/depois para as operações do BAR.

Resultado dos testes reais: **aprovado**.

## Inventário

- criar e editar produto;
- registar entrada, saída e ajuste;
- reservar e libertar stock;
- impedir saída de stock indisponível ou reservado;
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
- verificar registo de utilizador, ação e data/hora;
- abrir detalhe de auditoria e confirmar valores antes/depois;
- confirmar que operações técnicas/derivadas não poluem a auditoria;
- confirmar preservação do anonimato dos votos.

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
