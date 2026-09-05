do $$
declare
  t text;
  stamp_tables text[] := array[
    'agenda_items',
    'annual_book_items',
    'annual_books',
    'event_bands',
    'event_exhibitors',
    'event_guests',
    'event_incidents',
    'event_octane_configs',
    'event_proposals',
    'event_routes',
    'event_shifts',
    'event_sponsors',
    'event_tasks',
    'weekly_dinners',
    'weekly_officer_absences',
    'weekly_officer_rotation',
    'weekly_officer_swap_requests'
  ];
  capture_only_tables text[] := array[
    'document_approvals',
    'document_links',
    'document_versions',
    'event_program',
    'event_route_stops',
    'event_shift_members',
    'event_task_assignees',
    'exports',
    'imports',
    'notification_preferences',
    'poll_options',
    'polls',
    'stock_breakages',
    'stock_lots',
    'stock_reservations'
  ];
begin
  foreach t in array stamp_tables loop
    execute format('drop trigger if exists trg_audit_stamp_v1 on public.%I', t);
    execute format(
      'create trigger trg_audit_stamp_v1 before insert or update on public.%I for each row execute function public.audit_stamp_row_v1()',
      t
    );
    execute format('drop trigger if exists trg_audit_capture_v1 on public.%I', t);
    execute format(
      'create trigger trg_audit_capture_v1 after insert or update or delete on public.%I for each row execute function public.audit_capture_row_v1()',
      t
    );
  end loop;

  foreach t in array capture_only_tables loop
    execute format('drop trigger if exists trg_audit_capture_v1 on public.%I', t);
    execute format(
      'create trigger trg_audit_capture_v1 after insert or update or delete on public.%I for each row execute function public.audit_capture_row_v1()',
      t
    );
  end loop;
end
$$;
