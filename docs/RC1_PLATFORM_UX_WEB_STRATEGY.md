# BOB Manager — Estratégia de Plataforma, UX e Portal Web

**Estado:** Aprovado  
**Aplicável a partir de:** Commit 23  
**Âmbito:** Android, iOS, tablet e Web/Desktop

## 1. Decisão de produto

O BOB Manager é uma aplicação **Mobile First**.

A prioridade de experiência é, por ordem:

1. Android;
2. iOS;
3. tablets;
4. Web/Desktop como acesso complementar.

A versão Web/Desktop deve permanecer totalmente funcional e profissional, mas não pode condicionar a aplicação a uma interface de computador reduzida para caber num telemóvel.

Todos os novos módulos, fluxos e refactors devem ser desenhados primeiro para utilização confortável com uma mão e toque, sendo depois adaptados a ecrãs maiores.

## 2. Princípio adaptativo

A aplicação deve usar o mesmo domínio, regras, permissões, repositórios e backend em todas as plataformas. O que muda é a apresentação e a navegação conforme o espaço disponível.

Referência de projeto:

- **Compacto:** largura inferior a 600 logical pixels — smartphones;
- **Médio:** 600 a 999 logical pixels — tablets e janelas intermédias;
- **Expandido:** 1000 logical pixels ou superior — desktop/web.

Estes limites são uma convenção interna do BOB Manager e podem ser refinados se testes reais demonstrarem necessidade.

## 3. Navegação

### Compacto — Android/iOS

A navegação principal deve privilegiar:

- acesso às áreas mais utilizadas com no máximo 4–5 destinos visíveis;
- destino `Mais` para os restantes módulos quando necessário;
- AppBar simples com ações globais realmente úteis, como Pesquisa e Notificações;
- navegação contextual dentro de cada módulo através de tabs, segmented controls, bottom sheets ou páginas de detalhe;
- evitar menus extensos que obriguem o utilizador a procurar repetidamente a mesma funcionalidade.

Um NavigationDrawer pode continuar a existir como navegação secundária/completa, mas não deve ser a única forma de navegação diária em smartphones.

### Médio — Tablet

Pode usar NavigationRail, tabs e layouts mestre/detalhe quando melhorarem a utilização sem duplicar lógica.

### Expandido — Web/Desktop

Pode usar NavigationRail ou navegação lateral persistente e aproveitar a largura disponível para:

- listas + detalhe;
- filtros laterais;
- cartões em grelha;
- tabelas apenas quando forem realmente a representação mais adequada.

A versão desktop não deve introduzir funcionalidades exclusivas sem justificação funcional e de permissões.

## 4. Regras de interação mobile

Todos os novos ecrãs e os ecrãs alterados devem cumprir, sempre que aplicável:

- alvos de toque preferencialmente com pelo menos 48 × 48 logical pixels;
- espaçamento suficiente entre ações destrutivas e ações principais;
- ações principais claramente identificáveis;
- evitar depender de hover, clique direito ou precisão de rato;
- formulários de uma coluna em smartphone salvo exceções muito simples;
- teclado adequado ao tipo de campo;
- formulários e diálogos devem continuar utilizáveis com o teclado aberto;
- respeitar SafeArea quando elementos ficam junto aos limites do ecrã;
- evitar scroll horizontal como navegação normal;
- evitar texto demasiado pequeno para conseguir mostrar mais informação;
- confirmar operações destrutivas ou financeiramente relevantes;
- feedback visual imediato para loading, sucesso, erro e estado vazio.

## 5. Formulários

Os formulários devem ser organizados por intenção e não apenas pela estrutura das tabelas.

Regras:

- agrupar campos relacionados;
- mostrar primeiro os campos mais importantes;
- campos avançados podem ficar em secções expansíveis quando fizer sentido;
- validação deve indicar claramente o campo e o problema;
- preservar os valores introduzidos quando ocorre um erro recuperável;
- botões Guardar/Confirmar devem ser fáceis de alcançar em smartphone;
- formulários longos devem preferir secções ou etapas lógicas em vez de uma parede contínua de campos.

## 6. Listas e detalhe

Em smartphone:

- preferir Cards/ListTiles com hierarquia visual clara;
- limitar informação secundária visível na lista;
- abrir detalhe para informação completa;
- disponibilizar pesquisa e filtros próximos do contexto;
- evitar tabelas largas.

Em desktop:

- a mesma informação pode ser apresentada em grelha/tabela ou mestre-detalhe se melhorar produtividade;
- não revelar campos adicionais apenas porque existe mais espaço: permissões e privacidade são iguais em todas as plataformas.

## 7. Estados obrigatórios de UX

Cada ecrã que carrega dados deve tratar explicitamente:

- loading;
- lista vazia / sem resultados;
- erro recuperável;
- falta de permissão;
- sucesso após uma ação relevante.

Mensagens destinadas ao utilizador devem ser claras e não expor detalhes técnicos do Supabase, SQL, Storage ou stack traces.

## 8. Consistência visual

A aplicação deve consolidar progressivamente um design system BOB Manager baseado em Material 3 e identidade Blue On Black.

Princípios:

- azul institucional `#0C18D2` como cor de identidade, usado com moderação;
- tema escuro como identidade atual;
- tipografia e pesos consistentes;
- raios, espaçamentos, cards, botões, chips e feedback coerentes entre módulos;
- ícones Material usados de forma consistente;
- não criar estilos isolados por módulo quando um componente reutilizável resolve o problema.

A qualidade visual deve parecer a de uma aplicação instalada, não a de um formulário administrativo genérico.

## 9. Acessibilidade e legibilidade

A implementação deve privilegiar:

- contraste adequado;
- labels compreensíveis;
- tooltips onde úteis em ações apenas com ícone;
- não depender exclusivamente de cor para transmitir estado;
- tamanhos e espaçamentos que permitam utilização confortável;
- suporte à orientação e dimensões reais de dispositivos sem overflow.

## 10. Portal Web dos membros

O BOB Manager deve ficar preparado para publicação futura num subdomínio do clube, preferencialmente:

`https://app.<dominio-do-clube>`

O site institucional continuará separado, por exemplo:

`https://www.<dominio-do-clube>`

No site institucional deverá existir uma ação clara como `Área de Membros` / `BOB Manager`, que abre o subdomínio da aplicação.

Fluxo esperado:

1. membro visita o site do clube;
2. seleciona `Área de Membros`;
3. abre `app.<dominio-do-clube>`;
4. sem sessão válida, vê o login BOB Manager;
5. com sessão válida, a aplicação restaura a sessão e abre a área autorizada.

## 11. Arquitetura do portal Web

O portal Web usa a **mesma aplicação Flutter e o mesmo Supabase** das apps móveis.

Não deve existir uma base de dados paralela nem permissões diferentes para PC.

Arquitetura pretendida:

- Flutter Android;
- Flutter iOS;
- Flutter Web;
- Supabase Auth;
- Supabase Database;
- Supabase Storage;
- mesmas políticas/RPCs/Edge Functions e auditoria.

O frontend Web poderá ser alojado num serviço apropriado e associado ao subdomínio do clube. O alojamento da aplicação não precisa de ser o mesmo alojamento do site institucional.

## 12. Autenticação Web e domínio

Quando o portal Web for publicado:

- usar HTTPS;
- configurar a URL pública real do BOB Manager no Supabase Auth;
- configurar apenas redirects necessários e controlados;
- recuperação de password e convites devem regressar ao domínio oficial da aplicação;
- nunca expor `service_role` ou secret keys no Flutter Web;
- usar apenas a publishable key adequada ao cliente e manter autorização efetiva no servidor/RLS/RPCs.

A configuração do domínio será feita numa fase de deployment; o desenvolvimento deve, desde já, evitar pressupostos que impeçam a aplicação de funcionar em Web.

## 13. Critérios de aceitação para commits futuros

Sempre que um commit acrescentar ou alterar UI, deve ser validado pelo menos contra estas perguntas:

1. Funciona confortavelmente num smartphone estreito?
2. Existe overflow horizontal?
3. As ações principais são fáceis de encontrar e tocar?
4. O formulário continua utilizável com teclado aberto?
5. Loading, vazio e erro estão tratados?
6. A navegação exige passos desnecessários?
7. O layout aproveita tablet/desktop sem prejudicar mobile?
8. As permissões são iguais independentemente da plataforma?
9. O ecrã parece coerente com os restantes módulos?
10. `flutter analyze`, `flutter test` e `flutter build web` continuam verdes?

## 14. Impacto na arquitetura existente

A base atual já suporta Flutter Web e o CI valida `Build Flutter Web`, mas o Shell atual depende sobretudo de NavigationDrawer e ainda não constitui a experiência mobile-first final.

Por esse motivo, antes de aprofundar muitos módulos novos, deve ser criada uma fundação adaptativa comum para navegação e componentes responsivos, para que os módulos seguintes nasçam já sobre o padrão correto.

## 15. Regra de evolução

A migração visual será incremental.

Não é necessário reescrever todos os ecrãs num único commit. Contudo:

- todo ecrã novo deve cumprir esta estratégia;
- todo ecrã existente significativamente alterado deve aproximar-se desta estratégia;
- problemas globais de navegação/componentes devem ser resolvidos em componentes partilhados, evitando correções repetidas módulo a módulo.
