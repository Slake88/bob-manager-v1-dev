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

  Future<List<Map<String, dynamic>>> entityHistory({
    required String entityType,
    required String entityId,
    int limit = 100,
  }) async {
    if (AppConfig.demoMode) return const [];
    final response = await _client.rpc(
      'audit_entity_history_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_entity_type': entityType,
        'p_entity_id': entityId,
        'p_limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> notifications({
    int limit = 200,
    bool archived = false,
  }) async {
    if (AppConfig.demoMode) return const [];
    var query = _client
        .from('notifications')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId);

    query = archived
        ? query.not('archived_at', 'is', null)
        : query.isFilter('archived_at', null);

    final response = await query
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

  Future<void> archive(String notificationId, {bool archived = true}) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'archive_notification_v1',
      params: {
        'p_notification': notificationId,
        'p_archived': archived,
      },
    );
  }

  Future<Map<String, Map<String, bool>>> notificationPreferences() async {
    if (AppConfig.demoMode) return const {};
    final response = await _client
        .from('notification_preferences')
        .select('module_code,in_app_enabled,push_enabled')
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId);
    final result = <String, Map<String, bool>>{};
    for (final raw in List<Map<String, dynamic>>.from(response)) {
      final module = raw['module_code']?.toString() ?? '';
      if (module.isEmpty) continue;
      result[module] = {
        'in_app': raw['in_app_enabled'] != false,
        'push': raw['push_enabled'] != false,
      };
    }
    return result;
  }

  Future<void> setNotificationPreference({
    required String moduleCode,
    required bool inAppEnabled,
    required bool pushEnabled,
  }) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'set_notification_preference_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_module_code': moduleCode,
        'p_in_app_enabled': inAppEnabled,
        'p_push_enabled': pushEnabled,
      },
    );
  }

  Future<String?> registerPushDevice({
    required String platform,
    required String deviceId,
    required String pushToken,
    String? appVersion,
  }) async {
    if (AppConfig.demoMode) return null;
    final response = await _client.rpc(
      'register_push_device_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_platform': platform,
        'p_device_id': deviceId,
        'p_push_token': pushToken,
        'p_app_version': appVersion,
      },
    );
    return response?.toString();
  }

  Future<void> deactivatePushDevice(String deviceId) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'deactivate_push_device_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_device_id': deviceId,
      },
    );
  }
}
