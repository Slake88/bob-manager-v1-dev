# BOB Manager — Roadmap RC1.5

## Política transversal obrigatória: Mobile First + Web complementar

Android e iOS são as plataformas principais do BOB Manager. A experiência deve ser desenhada e validada primeiro para utilização diária em smartphone, mantendo também uma experiência profissional e totalmente funcional em tablet e Web/Desktop.

A política completa está definida em `docs/RC1_PLATFORM_UX_WEB_STRATEGY.md` e aplica-se a todos os commits a partir do Commit 23.

Requisitos mínimos para qualquer UI nova ou significativamente alterada:
- leitura confortável em ecrãs estreitos;
- controlos com área de toque adequada;
- ações principais fáceis de encontrar e executar com o dedo;
- formulários com disposição vertical em mobile;
- tabelas/grelhas com condensação, scroll controlado ou representação alternativa quando necessário;
- evitar colunas fixas e scroll horizontal como navegação normal em telemóvel;
- diálogos, bottom sheets e formulários com scroll e respeito por safe areas/teclado;
- loading, estado vazio, erro e falta de permissão explicitamente tratados;
- navegação adaptativa: mobile primeiro, tablet intermédio, Web/Desktop expandido;
- permissões e privacidade idênticas em todas as plataformas;
- testar módulos críticos em larguras típicas de smartphone Android e iPhone antes de fechar cada versão;
- manter `flutter analyze`, `flutter test` e `flutter build web` verdes.

### Portal Web dos membros

O BOB Manager deve ficar preparado para publicação futura num subdomínio do domínio institucional do clube, preferencialmente:

`https://app.<dominio-do-clube>`

O site público continuará em `www.<dominio-do-clube>` e terá um botão/imagem `Área de Membros` que abre diretamente o BOB Manager. Sem sessão válida, o membro vê o login; com sessão válida, a aplicação restaura o acesso e abre a área autorizada.

O portal Web usa a mesma aplicação Flutter, autenticação, base de dados, Storage, permissões e auditoria do Android/iOS. Não será criado um backend paralelo para PC.

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
