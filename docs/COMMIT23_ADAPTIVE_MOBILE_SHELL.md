# Commit 23 — Fundação Mobile-First e Shell Adaptativo

## Objetivo

Criar uma fundação de navegação adaptativa comum ao BOB Manager para que Android e iOS sejam a experiência principal, mantendo tablet e Web/Desktop profissionais sem duplicar lógica.

Este commit implementa a estratégia definida em `docs/RC1_PLATFORM_UX_WEB_STRATEGY.md`.

## Âmbito

### Breakpoints partilhados

Novo `core/adaptive_layout.dart`:

- Compacto: < 600 logical pixels;
- Médio: 600–999;
- Expandido: >= 1000.

### Política de navegação

Novo `core/app_navigation.dart`:

- seleção de módulos por `code`, não por índice global;
- prioridades mobile:
  1. Dashboard;
  2. Membros;
  3. Agenda;
  4. Eventos;
- se alguma prioridade não estiver disponível por permissões, a barra preenche com módulos visíveis até ao máximo de quatro;
- `Mais` representa todos os restantes módulos;
- quando uma permissão remove o módulo atualmente selecionado, a navegação regressa de forma segura ao Dashboard ou ao primeiro módulo permitido.

## Smartphone

O Shell compacto passa a ter:

- NavigationBar inferior;
- até quatro destinos principais + `Mais`;
- NavigationDrawer completo mantido como navegação secundária;
- AppBar com Pesquisa Global e Notificações;
- ações menos frequentes (`Atualizar permissões`, `Terminar sessão`) agrupadas num menu de overflow;
- `Mais` abre um bottom sheet com cartões das áreas restantes e informação do utilizador.

Objetivo: reduzir o número de passos das ações diárias e evitar depender exclusivamente do menu lateral.

## Tablet

O Shell médio usa:

- NavigationRail com os destinos principais;
- destino `Mais` para os módulos restantes;
- conteúdo do módulo ocupa a área disponível à direita.

## Web/Desktop

O Shell expandido usa:

- navegação lateral persistente;
- todos os módulos permitidos visíveis;
- conteúdo em painel expandido;
- mesmas regras, permissões e ModuleRouter das apps móveis.

## Segurança e permissões

Este commit não altera o modelo de autorização.

- `_visibleModules` continua a ser a fonte para determinar o que o utilizador pode abrir;
- a navegação nunca cria acesso a um módulo que não esteja autorizado;
- Pesquisa Global e notificações mantêm os seus controlos existentes;
- não existe migration Supabase;
- não existe nova Edge Function;
- não existe nova dependência Flutter.

## Robustez

A seleção deixa de depender do índice do módulo na lista global.

Isto evita que uma alteração dinâmica de permissões faça um índice existente passar a apontar silenciosamente para outro módulo.

## UX

O commit mantém a identidade atual Material 3 / tema escuro / azul BOB e melhora:

- acesso com o polegar em smartphone;
- hierarquia das ações globais;
- descoberta das áreas secundárias;
- legibilidade de títulos longos na AppBar através de ellipsis;
- consistência entre mobile, tablet e desktop.

## Testes

Novo `test/adaptive_navigation_test.dart` cobre:

- breakpoints;
- prioridade dos destinos mobile;
- fallback quando permissões removem prioridades;
- seleção de `Mais` para módulos secundários;
- fallback seguro para Dashboard.

## Critérios para fecho

- `flutter analyze` verde;
- `flutter test` verde;
- `flutter build web` verde;
- validar visualmente pelo menos um viewport smartphone após sincronizar o repositório local;
- nenhum ficheiro não relacionado incluído.
