# BOB Manager — Roadmap RC1.5

## Princípio transversal: mobile-first

A interface deve ser desenhada e validada para utilização diária em telemóveis Android através de APK, mantendo também boa utilização em Web/Desktop.

Requisitos mínimos:
- leitura confortável em ecrãs estreitos;
- controlos com área de toque adequada;
- formulários com disposição vertical em mobile;
- tabelas/grelhas com scroll, condensação ou representação alternativa quando necessário;
- evitar colunas fixas que prejudiquem a leitura em telemóvel;
- diálogos e bottom sheets com scroll e respeito por safe areas/teclado;
- testar os módulos críticos em largura típica de smartphone antes de fechar cada versão.

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
