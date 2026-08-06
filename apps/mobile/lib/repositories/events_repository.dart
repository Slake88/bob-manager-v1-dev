import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class EventsRepository {
  EventsRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listEvents() async {
    _require(AppPermission.viewEvents);
    final rows = await _dataService.list('events');
    rows.sort((a, b) => (a['starts_at']?.toString() ?? '')
        .compareTo(b['starts_at']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, dynamic>> saveEvent(
    Map<String, dynamic> values, {
    String? eventId,
  }) {
    _require(AppPermission.manageEvents);
    if (eventId == null) return _dataService.insert('events', values);
    return _dataService.update('events', eventId, values);
  }

  Future<void> deleteEvent(String eventId) {
    _require(AppPermission.manageEvents);
    return _dataService.delete('events', eventId);
  }

  Future<List<Map<String, dynamic>>> participants(String eventId) {
    _require(AppPermission.viewEvents);
    return _dataService.listWhere(
      'event_participants',
      field: 'event_id',
      value: eventId,
    );
  }

  Future<Map<String, dynamic>> addParticipant({
    required String eventId,
    required String memberId,
    required String memberName,
    String? companionName,
  }) {
    _require(AppPermission.manageEventParticipants);
    return _dataService.insert('event_participants', {
      'event_id': eventId,
      'member_id': memberId,
      'member_name': memberName,
      'companion_name': companionName,
      'status': 'confirmed',
      'registered_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> volunteers(String eventId) {
    _require(AppPermission.viewEvents);
    return _dataService.listWhere(
      'event_volunteers',
      field: 'event_id',
      value: eventId,
    );
  }

  Future<Map<String, dynamic>> addVolunteer({
    required String eventId,
    required String memberId,
    required String memberName,
    required String functionName,
  }) {
    _require(AppPermission.manageEventParticipants);
    return _dataService.insert('event_volunteers', {
      'event_id': eventId,
      'member_id': memberId,
      'member_name': memberName,
      'function_name': functionName,
      'status': 'confirmed',
    });
  }

  Future<Map<String, dynamic>> financialSummary(String eventId) async {
    _require(AppPermission.viewEvents);
    final movements = await _dataService.listWhere(
      'financial_transactions',
      field: 'event_id',
      value: eventId,
    );
    var income = 0.0;
    var expense = 0.0;
    for (final movement in movements) {
      final amount = _asDouble(movement['amount']);
      if (movement['kind'] == 'income') income += amount;
      if (movement['kind'] == 'expense') expense += amount;
    }
    return {
      'income': income,
      'expense': expense,
      'result': income - expense,
      'movements': movements,
    };
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
