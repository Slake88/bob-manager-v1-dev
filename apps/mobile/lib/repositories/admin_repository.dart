import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class AdminRepository {
  AdminRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;
  SupabaseClient get _client => Supabase.instance.client;
  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listSettings() async {
    _require(AppPermission.manageSettings);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('club_settings');
      rows.sort((a, b) => (a['key']?.toString() ?? '')
          .compareTo(b['key']?.toString() ?? ''));
      return rows;
    }
    final response = await _client
        .from('club_settings')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('key');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveSetting({
    required String key,
    required String value,
    String? settingId,
  }) async {
    _require(AppPermission.manageSettings);
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('A chave da configuração é obrigatória.');
    }
    if (AppConfig.demoMode) {
      final values = {
        'key': normalizedKey,
        'value': value.trim(),
        'updated_by': AppSession.instance.profileId,
      };
      if (settingId == null) {
        return _dataService.insert('club_settings', values);
      }
      return _dataService.update('club_settings', settingId, values);
    }

    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'key': normalizedKey,
      'value': value.trim(),
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (settingId == null) {
      final response = await _client
          .from('club_settings')
          .upsert(payload, onConflict: 'club_id,key')
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _client
        .from('club_settings')
        .update(payload)
        .eq('id', settingId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAuditLog({int limit = 100}) async {
    _require(AppPermission.manageSettings);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('audit_log', limit: limit);
      rows.sort((a, b) => (b['created_at']?.toString() ?? '')
          .compareTo(a['created_at']?.toString() ?? ''));
      return rows.take(limit).toList();
    }

    final response = await _client.rpc(
      'list_audit_log_v2',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response as List).map((row) {
      return <String, dynamic>{
        ...row,
        'actor': {
          'full_name': row['actor_name'],
          'email': row['actor_email'],
        },
        'description':
            '${row['action'] ?? 'Alteração'} — ${row['entity_type'] ?? 'registo'}',
      };
    }).toList();
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
