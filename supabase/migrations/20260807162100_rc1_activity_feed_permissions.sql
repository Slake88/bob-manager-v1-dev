create or replace function public.module_view_permission(p_module text)
returns text language sql immutable as $$
 select case lower(coalesce(p_module,''))
  when 'members' then 'viewMembers' when 'member' then 'viewMembers'
  when 'fees' then 'viewFees' when 'fee' then 'viewFees'
  when 'treasury' then 'viewTreasury' when 'transaction' then 'viewTreasury'
  when 'events' then 'viewEvents' when 'event' then 'viewEvents'
  when 'lottery' then 'viewLottery' when 'euromillions' then 'viewLottery'
  when 'inventory' then 'viewInventory' when 'product' then 'viewInventory'
  when 'documents' then 'viewDocuments' when 'document' then 'viewDocuments'
  when 'communication' then 'viewCommunication' when 'announcement' then 'viewCommunication'
  when 'emergency' then 'viewEmergencyData'
  when 'settings' then 'manageSettings' when 'permission' then 'manageSettings'
  else null end;
$$;

drop policy if exists activity_feed_access on public.activity_feed;
drop policy if exists activity_feed_read on public.activity_feed;
drop policy if exists activity_feed_insert on public.activity_feed;
create policy activity_feed_read on public.activity_feed for select to authenticated
using(
 public.has_club_access(club_id)
 and (
   public.module_view_permission(coalesce(metadata->>'module_code',activity_type)) is null
   or public.has_club_permission(club_id,public.module_view_permission(coalesce(metadata->>'module_code',activity_type)))
 )
);
