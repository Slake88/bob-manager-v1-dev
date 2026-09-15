create index if not exists stock_reservations_location_idx on public.stock_reservations(location_id);
create index if not exists stock_reservations_variant_idx on public.stock_reservations(variant_id) where variant_id is not null;
create index if not exists stock_reservations_released_by_idx on public.stock_reservations(released_by) where released_by is not null;
create index if not exists stock_reservations_created_by_idx on public.stock_reservations(created_by) where created_by is not null;

create index if not exists stock_lots_location_idx on public.stock_lots(location_id);
create index if not exists stock_lots_variant_idx on public.stock_lots(variant_id) where variant_id is not null;
create index if not exists stock_lots_created_by_idx on public.stock_lots(created_by) where created_by is not null;

create index if not exists stock_breakages_location_idx on public.stock_breakages(location_id);
create index if not exists stock_breakages_variant_idx on public.stock_breakages(variant_id) where variant_id is not null;
create index if not exists stock_breakages_created_by_idx on public.stock_breakages(created_by) where created_by is not null;
