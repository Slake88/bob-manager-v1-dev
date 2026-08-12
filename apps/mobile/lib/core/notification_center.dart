enum NotificationViewFilter { all, unread, urgent }

bool notificationIsUrgent(Map<String, dynamic> row) {
  final priority = row['priority']?.toString().toLowerCase() ?? 'normal';
  return priority == 'high' || priority == 'urgent';
}

bool notificationMatchesFilter(
  Map<String, dynamic> row,
  NotificationViewFilter filter,
) {
  return switch (filter) {
    NotificationViewFilter.all => true,
    NotificationViewFilter.unread => row['read_at'] == null,
    NotificationViewFilter.urgent => notificationIsUrgent(row),
  };
}

String? notificationModuleFromRoute(String? rawRoute) {
  final route = rawRoute?.trim() ?? '';
  if (route.isEmpty) return null;
  final normalized = route.startsWith('/') ? route.substring(1) : route;
  final first = normalized.split('/').first.toLowerCase();
  return switch (first) {
    'dashboard' => 'dashboard',
    'activity' || 'notifications' => 'activity',
    'members' || 'member' => 'members',
    'treasury' => 'treasury',
    'financial' || 'payments' || 'requests' => 'financial',
    'fees' => 'fees',
    'lottery' || 'euromillions' => 'lottery',
    'events' => 'events',
    'weekly_officer' || 'dinners' => 'weekly_officer',
    'inventory' || 'assets' || 'shop' || 'bar' => 'inventory',
    'documents' => 'documents',
    'communication' => 'communication',
    'reports' => 'reports',
    'settings' => 'settings',
    'emergency' => 'emergency',
    _ => null,
  };
}
