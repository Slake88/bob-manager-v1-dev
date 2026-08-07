import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class ActivityRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> activity({
    String? module,
    int limit = 100,
  }) async {
    if (AppConfig.demoMode) return const [];

    var query = _client
        .from('activity_feed')
        .select('id,activity_type,title,description,entity_type,entity_id,metadata,created_at,actor:profiles(full_name)')
        .eq('club_id', AppSession.instance.clubId);

    if (module != null && module.isNotEmpty && module != 'all') {
      query = query.eq('metadata->>module_code', module);
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> notifications({int limit = 100}) async {
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('notifications')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId)
        .isFilter('archived_at', null)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<int> unreadCount() async {
    if (AppConfig.demoMode) return 0;
    final response = await _client
        .from('notifications')
        .select('id')
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId)
        .isFilter('read_at', null)
        .isFilter('archived_at', null);
    return (response as List).length;
  }

  Future<void> markRead(String notificationId, {bool read = true}) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'mark_notification_read_v1',
      params: {
        'p_notification': notificationId,
        'p_read': read,
      },
    );
  }

  Future<int> markAllRead() async {
    if (AppConfig.demoMode) return 0;
    final response = await _client.rpc(
      'mark_all_notifications_read_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    if (response is num) return response.toInt();
    return int.tryParse(response?.toString() ?? '') ?? 0;
  }

  Future<void> archive(String notificationId) async {
    if (AppConfig.demoMode) return;
    await _client
        .from('notifications')
        .update({'archived_at': DateTime.now().toIso8601String()})
        .eq('id', notificationId)
        .eq('profile_id', AppSession.instance.profileId);
  }
}
