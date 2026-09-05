# Commit 14 — Fundação de Inventário

## Objetivo

Consolidar o inventário existente sem duplicar Produtos, Loja, Bar, Património ou Inventário Físico.

## Backend

### Hardening

Migration `20260812114950_rc1_inventory_foundation_hardening.sql`:

- RPCs de inventário físico apenas para `authenticated`;
- escrita direta nas tabelas de contagem removida;
- leitura de produtos, variantes e movimentos alinhada com `viewInventory`;
- validação de local, evento e quantidades negativas.

### Stock por localização

Migration `20260812132251_rc1_inventory_location_stock.sql`:

- `products.current_stock` e `product_variants.current_stock` continuam a ser o total global;
- `inventory_stock_balances` distribui esse total por localização;
- Loja usa `Armazém` como local padrão;
- Bar usa `Club House` como local padrão;
- transferências entre locais não alteram o stock global;
- movimentos registam origem e destino;
- inventário físico passa a usar o saldo da localização escolhida;
- stock com variantes é controlado por variante.

## Flutter

- novo separador `Localizações`;
- consulta de stock por local;
- filtros por local, área e pesquisa;
- transferência de stock entre locais;
- histórico de movimentos mostra origem/destino;
- localização obrigatória ao iniciar inventário físico.

## Permissões

- `viewInventory`: consulta;
- `manageInventory`: transferências;
- `performInventoryCount`: contagem física.

## Validação remota

Teste transacional de 1 unidade de `Cerveja Sagres`:

- Club House: 482 -> 481;
- Armazém: 0 -> 1;
- stock global: 482 -> 482;
- soma das localizações: 482;
- `ROLLBACK` aplicado no final.
