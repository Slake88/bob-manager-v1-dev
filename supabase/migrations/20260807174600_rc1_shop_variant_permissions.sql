drop policy if exists product_variants_insert on public.product_variants;
drop policy if exists product_variants_update on public.product_variants;
drop policy if exists product_variants_delete on public.product_variants;

create policy product_variants_insert on public.product_variants
for insert to authenticated
with check (
  exists(
    select 1 from public.products p
    where p.id=product_id
      and public.has_club_permission(p.club_id,'manageMerchandising')
  )
);

create policy product_variants_update on public.product_variants
for update to authenticated
using (
  exists(
    select 1 from public.products p
    where p.id=product_id
      and public.has_club_permission(p.club_id,'manageMerchandising')
  )
)
with check (
  exists(
    select 1 from public.products p
    where p.id=product_id
      and public.has_club_permission(p.club_id,'manageMerchandising')
  )
);

create policy product_variants_delete on public.product_variants
for delete to authenticated
using (
  exists(
    select 1 from public.products p
    where p.id=product_id
      and public.has_club_permission(p.club_id,'manageMerchandising')
  )
);
