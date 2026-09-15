create or replace function public.activity_user_permission_trigger_v1()
returns trigger language plpgsql security definer set search_path='public' as $$
declare v_club uuid; v_profile uuid;
begin
  if tg_op='DELETE' then
    v_club:=old.club_id; v_profile:=old.profile_id;
  else
    v_club:=new.club_id; v_profile:=new.profile_id;
  end if;
  perform public.emit_domain_event(v_club,'UserPermissionOverrideUpdated','permission',null,
    jsonb_build_object('title','Permissão individual atualizada','description','Foi alterada uma exceção individual de acesso.','route','settings','priority','low','profile_id',v_profile));
  if tg_op='DELETE' then return old; end if;
  return new;
end; $$;
