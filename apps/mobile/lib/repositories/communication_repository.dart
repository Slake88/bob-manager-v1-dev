import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class CommunicationRepository {
  CommunicationRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listAnnouncements() async {
    _require(AppPermission.viewCommunication);
    final rows = await _dataService.list('announcements');
    rows.sort((a, b) => (b['published_at']?.toString() ?? '')
        .compareTo(a['published_at']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, dynamic>> saveAnnouncement(
    Map<String, dynamic> values, {
    String? announcementId,
  }) {
    _require(AppPermission.manageCommunication);
    final payload = Map<String, dynamic>.from(values)
      ..['updated_at'] = DateTime.now().toIso8601String();
    if (announcementId == null) {
      payload['created_by'] = AppSession.instance.profileId;
      payload['published_at'] ??= DateTime.now().toIso8601String();
      return _dataService.insert('announcements', payload);
    }
    return _dataService.update('announcements', announcementId, payload);
  }

  Future<void> acknowledge(String announcementId) async {
    _require(AppPermission.acknowledgeCommunication);
    final existing = await _dataService.listWhere(
      'announcement_acknowledgements',
      field: 'announcement_id',
      value: announcementId,
    );
    if (existing.any(
      (row) => row['profile_id']?.toString() == AppSession.instance.profileId,
    )) {
      return;
    }
    await _dataService.insert('announcement_acknowledgements', {
      'announcement_id': announcementId,
      'profile_id': AppSession.instance.profileId,
      'acknowledged_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> isAcknowledged(String announcementId) async {
    final rows = await _dataService.listWhere(
      'announcement_acknowledgements',
      field: 'announcement_id',
      value: announcementId,
    );
    return rows.any(
      (row) => row['profile_id']?.toString() == AppSession.instance.profileId,
    );
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(_role, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
