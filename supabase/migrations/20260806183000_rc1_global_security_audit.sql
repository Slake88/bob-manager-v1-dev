-- RC1 global security audit and hardening

alter function public.set_updated_at() set search_path = public, pg_temp;

do $$
declare
  fn record;
begin
  for fn in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef = true
  loop
    execute format('revoke execute on function %s from public, anon', fn.signature);
  end loop;
end
$$;

revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.protect_profile_privileges() from authenticated;
revoke execute on function public.validate_treasury_transaction_v1() from authenticated;

alter table public.member_motorcycles enable row level security;
create policy member_motorcycles_read on public.member_motorcycles
for select to authenticated using (public.has_club_access(club_id));
create policy member_motorcycles_manage on public.member_motorcycles
for all to authenticated
using (public.has_club_role(club_id, array['secretary','admin','super_admin']))
with check (public.has_club_role(club_id, array['secretary','admin','super_admin']));

alter table public.treasury_categories enable row level security;
create policy treasury_categories_read on public.treasury_categories
for select to authenticated
using (public.has_club_role(club_id, array['treasurer','admin','super_admin']));
create policy treasury_categories_manage on public.treasury_categories
for all to authenticated
using (public.has_club_role(club_id, array['admin','super_admin']))
with check (public.has_club_role(club_id, array['admin','super_admin']));

alter table public.euromillions_participations enable row level security;
create policy euromillions_participations_read on public.euromillions_participations
for select to authenticated using (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_access(d.club_id))
);
create policy euromillions_participations_manage on public.euromillions_participations
for all to authenticated using (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_role(d.club_id,
            array['euromillions_manager','treasurer','admin','super_admin']))
) with check (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_role(d.club_id,
            array['euromillions_manager','treasurer','admin','super_admin']))
);

alter table public.euromillions_keys enable row level security;
create policy euromillions_keys_read on public.euromillions_keys
for select to authenticated using (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_access(d.club_id))
);
create policy euromillions_keys_manage on public.euromillions_keys
for all to authenticated using (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_role(d.club_id,
            array['euromillions_manager','admin','super_admin']))
) with check (
  exists (select 1 from public.euromillions_draws d
          where d.id = draw_id and public.has_club_role(d.club_id,
            array['euromillions_manager','admin','super_admin']))
);

alter table public.event_partners enable row level security;
create policy event_partners_read on public.event_partners
for select to authenticated using (
  exists (select 1 from public.events e
          where e.id = event_id and public.has_club_access(e.club_id))
);
create policy event_partners_manage on public.event_partners
for all to authenticated using (
  exists (select 1 from public.events e
          where e.id = event_id and public.has_club_role(e.club_id,
            array['event_manager','secretary','admin','super_admin']))
) with check (
  exists (select 1 from public.events e
          where e.id = event_id and public.has_club_role(e.club_id,
            array['event_manager','secretary','admin','super_admin']))
);

alter table public.product_variants enable row level security;
create policy product_variants_read on public.product_variants
for select to authenticated using (
  exists (select 1 from public.products p
          where p.id = product_id and public.has_club_access(p.club_id))
);
create policy product_variants_manage on public.product_variants
for all to authenticated using (
  exists (select 1 from public.products p
          where p.id = product_id and public.has_club_role(p.club_id,
            array['inventory_manager','admin','super_admin']))
) with check (
  exists (select 1 from public.products p
          where p.id = product_id and public.has_club_role(p.club_id,
            array['inventory_manager','admin','super_admin']))
);