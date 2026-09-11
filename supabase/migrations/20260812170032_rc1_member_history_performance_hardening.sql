-- Commit 18 hardening: indexes de FKs e políticas sem SELECT duplicado.

create index if not exists members_profile_id_idx on public.members(profile_id) where profile_id is not null;
create index if not exists member_motorcycles_member_id_idx on public.member_motorcycles(member_id);
create index if not exists member_positions_club_id_idx on public.member_positions(club_id);
create index if not exists member_positions_position_id_idx on public.member_positions(position_id);
create index if not exists member_status_history_member_id_idx on public.member_status_history(member_id);
create index if not exists maintenance_records_member_id_idx on public.maintenance_records(member_id);
create index if not exists maintenance_attachments_club_id_idx on public.maintenance_attachments(club_id);
create index if not exists maintenance_attachments_member_id_idx on public.maintenance_attachments(member_id);
create index if not exists member_patch_awards_member_id_idx on public.member_patch_awards(member_id);
create index if not exists member_patch_awards_product_id_idx on public.member_patch_awards(product_id);
create index if not exists member_patch_awards_variant_id_idx on public.member_patch_awards(variant_id) where variant_id is not null;
create index if not exists member_patch_awards_inventory_location_id_idx on public.member_patch_awards(inventory_location_id) where inventory_location_id is not null;
create index if not exists member_timeline_member_id_idx on public.member_timeline(member_id);

-- Evita múltiplas políticas permissivas em SELECT; a gestão continua igual.
drop policy if exists club_positions_manage_v2 on public.club_positions;
create policy club_positions_insert_v2 on public.club_positions
  for insert to authenticated
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy club_positions_update_v2 on public.club_positions
  for update to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy club_positions_delete_v2 on public.club_positions
  for delete to authenticated
  using (public.has_club_permission(club_id,'manageMembers'));

drop policy if exists member_positions_manage_v2 on public.member_positions;
create policy member_positions_insert_v2 on public.member_positions
  for insert to authenticated
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy member_positions_update_v2 on public.member_positions
  for update to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy member_positions_delete_v2 on public.member_positions
  for delete to authenticated
  using (public.has_club_permission(club_id,'manageMembers'));

drop policy if exists member_motorcycles_manage_v2 on public.member_motorcycles;
create policy member_motorcycles_insert_v2 on public.member_motorcycles
  for insert to authenticated
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy member_motorcycles_update_v2 on public.member_motorcycles
  for update to authenticated
  using (public.has_club_permission(club_id,'manageMembers'))
  with check (public.has_club_permission(club_id,'manageMembers'));
create policy member_motorcycles_delete_v2 on public.member_motorcycles
  for delete to authenticated
  using (public.has_club_permission(club_id,'manageMembers'));
