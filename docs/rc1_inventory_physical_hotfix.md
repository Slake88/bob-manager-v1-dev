# RC1 — Hotfix Inventário Físico

Correção do erro Flutter `setState() callback argument returned a Future` no Inventário Físico.

Foram substituídas todas as chamadas `setState(_reload)` do ecrã de contagens por callbacks síncronos que apenas atualizam o Future usado pela interface.

A lógica de contagem, RPCs e ajustes de stock não foi alterada.
