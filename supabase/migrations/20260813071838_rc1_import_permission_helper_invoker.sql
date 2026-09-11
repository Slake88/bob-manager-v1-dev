create or replace function public.import_target_allowed_v1(target_club uuid, p_target text)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select auth.uid() is not null
    and (
      public.has_club_role(
        target_club,
        array['president','vice_president','admin','administrator','super_admin']::text[]
      )
      or (
        public.has_club_permission(target_club, 'manageImports')
        and case p_target
          when 'members' then public.has_club_permission(target_club, 'manageMembers')
          when 'inventory_products' then public.has_club_permission(target_club, 'manageInventory')
          when 'events' then public.has_club_permission(target_club, 'manageEvents')
          when 'fee_plans' then public.has_club_permission(target_club, 'manageFees')
          else false
        end
      )
    );
$$;

revoke all on function public.import_target_allowed_v1(uuid,text) from public, anon;
grant execute on function public.import_target_allowed_v1(uuid,text) to authenticated, service_role;
