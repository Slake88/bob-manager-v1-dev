# BOB Manager — Roadmap RC1.5

## Princípio transversal: mobile-first

A interface deve ser desenhada e validada para utilização diária em telemóveis Android e iOS, mantendo também boa utilização em Web/Desktop.

Requisitos mínimos:
- leitura confortável em ecrãs estreitos;
- controlos com área de toque adequada;
- formulários com disposição vertical em mobile;
- tabelas/grelhas com scroll, condensação ou representação alternativa quando necessário;
- evitar colunas fixas que prejudiquem a leitura em telemóvel;
- diálogos e bottom sheets com scroll e respeito por safe areas/teclado;
- testar os módulos críticos em larguras típicas de smartphone Android e iPhone antes de fechar cada versão.

## Extratos e Relatórios Financeiros

Adicionar ao módulo de Tesouraria:
- extratos por período;
- filtros por conta;
- filtros por centro de custo;
- filtros por tipo de movimento;
- saldo inicial e final do período;
- totais de receitas e despesas;
- exportação PDF, Excel e CSV;
- gráficos de evolução da tesouraria;
- relatórios mensais e anuais.

## Fotografia do membro

Adicionar ao módulo Membros:
- tirar fotografia através da câmara do telemóvel;
- escolher fotografia da galeria;
- guardar a fotografia no Supabase Storage;
- guardar no perfil apenas o caminho/referência segura;
- mostrar fotografia na ficha do membro;
- mostrar miniatura nas listas onde houver espaço;
- imagem opcional, com fallback para avatar genérico;
- regras de acesso alinhadas com as permissões do módulo Membros.

## Contas de utilizador e acesso à aplicação

Integrar a gestão de acesso diretamente na ficha de Membros, sem guardar nem expor passwords em texto legível.

Fluxo pretendido:
- campo de email de acesso associado ao membro;
- estado visual da conta: Sem acesso / Convite enviado / Ativo / Bloqueado;
- botão exclusivo dos perfis autorizados para `Criar acesso / Enviar convite`;
- o convite é enviado por email e o próprio membro escolhe a sua password;
- o Super Admin nunca visualiza nem recupera a password atual de outro utilizador;
- botão `Enviar redefinição de password` para casos de esquecimento;
- possibilidade de reenviar convite quando ainda não foi aceite;
- possibilidade de bloquear/desbloquear acesso sem apagar a ficha do membro;
- alteração da própria password pelo utilizador autenticado;
- auditoria de criação, convite, bloqueio, desbloqueio e pedidos de recuperação, sem registar passwords;
- implementação das ações administrativas através de serviço seguro no servidor/Edge Function, sem expor `service_role` na aplicação Flutter;
- permissões efetivas continuam a ser definidas pela matriz dinâmica por cargo e exceções individuais.

Princípio de segurança: passwords são privadas e irreversíveis. Mesmo o Super Admin não deve conseguir vê-las; em caso de esquecimento, o procedimento é sempre redefinir a password.
