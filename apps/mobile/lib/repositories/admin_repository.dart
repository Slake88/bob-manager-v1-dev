import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class AdminRepository {
  AdminRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listSettings() async {
    _require(AppPermission.manageSettings);
    final rows = await _dataService.list('club_settings');
    rows.sort((a, b) => (a['key']?.toString() ?? '')
        .compareTo(b['key']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, dynamic>> saveSetting({
    required String key,
    required String value,
    String? settingId,
  }) {
    _require(AppPermission.manageSettings);
    final values = {
      'key': key.trim(),
      'value': value.trim(),
      'updated_by': AppSession.instance.profileId,
    };
    if (settingId == null) {
      return _dataService.insert('club_settings', values);
    }
    return _dataService.update('club_settings', settingId, values);
  }

  Future<List<Map<String, dynamic>>> listAuditLog({int limit = 100}) async {
    _require(AppPermission.manageSettings);
    final rows = await _dataService.list('audit_log', limit: limit);
    rows.sort((a, b) => (b['created_at']?.toString() ?? '')
        .compareTo(a['created_at']?.toString() ?? ''));
    return rows.take(limit).toList();
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
