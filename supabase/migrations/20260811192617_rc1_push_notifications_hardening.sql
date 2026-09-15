-- Commit 10 hardening: restringe RPCs de notificacoes ao papel esperado.

revoke all on function public.register_push_device_v1(uuid,text,text,text,text) from public;
revoke all on function public.register_push_device_v1(uuid,text,text,text,text) from anon;
grant execute on function public.register_push_device_v1(uuid,text,text,text,text) to authenticated;

revoke all on function public.deactivate_push_device_v1(uuid,text) from public;
revoke all on function public.deactivate_push_device_v1(uuid,text) from anon;
grant execute on function public.deactivate_push_device_v1(uuid,text) to authenticated;

revoke all on function public.set_notification_preference_v1(uuid,text,boolean,boolean) from public;
revoke all on function public.set_notification_preference_v1(uuid,text,boolean,boolean) from anon;
grant execute on function public.set_notification_preference_v1(uuid,text,boolean,boolean) to authenticated;

revoke all on function public.archive_notification_v1(uuid,boolean) from public;
revoke all on function public.archive_notification_v1(uuid,boolean) from anon;
grant execute on function public.archive_notification_v1(uuid,boolean) to authenticated;

revoke all on function public.mark_notification_read_v1(uuid,boolean) from public;
revoke all on function public.mark_notification_read_v1(uuid,boolean) from anon;
grant execute on function public.mark_notification_read_v1(uuid,boolean) to authenticated;

revoke all on function public.mark_all_notifications_read_v1(uuid) from public;
revoke all on function public.mark_all_notifications_read_v1(uuid) from anon;
grant execute on function public.mark_all_notifications_read_v1(uuid) to authenticated;

alter function public.notification_module_code(text) set search_path=public;
alter function public.notification_module_permission(text) set search_path=public;
