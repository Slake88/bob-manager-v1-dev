import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
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
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listEvents() async {
    _require(AppPermission.viewEvents);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('events');
      rows.sort((a, b) => (a['starts_at']?.toString() ?? '')
          .compareTo(b['starts_at']?.toString() ?? ''));
      return rows;
    }

    final response = await _client
        .from('events')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('starts_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveEvent(
    Map<String, dynamic> values, {
    String? eventId,
  }) async {
    _require(AppPermission.manageEvents);
    if (AppConfig.demoMode) {
      if (eventId == null) return _dataService.insert('events', values);
      return _dataService.update('events', eventId, values);
    }

    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'name': values['name'],
      'description': values['description'],
      'location': values['location'],
      'starts_at': values['starts_at'],
      'ends_at': values['ends_at'],
      'status': values['status'] ?? 'draft',
      'capacity': values['capacity'] ?? values['expected_attendance'],
      'budget': _asDouble(values['budget']),
      'banner_path': values['banner_path'],
      'event_mode_enabled': values['event_mode_enabled'] == true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (eventId == null) {
      final response = await _client
          .from('events')
          .insert(payload)
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _client
        .from('events')
        .update(payload)
        .eq('id', eventId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> deleteEvent(String eventId) async {
    _require(AppPermission.manageEvents);
    if (AppConfig.demoMode) {
      return _dataService.delete('events', eventId);
    }
    await _client
        .from('events')
        .delete()
        .eq('id', eventId)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<List<Map<String, dynamic>>> participants(String eventId) async {
    _require(AppPermission.viewEvents);
    if (AppConfig.demoMode) {
      return _dataService.listWhere(
        'event_participants',
        field: 'event_id',
        value: eventId,
      );
    }

    final response = await _client
        .from('event_registrations')
        .select('id,event_id,member_id,guest_name,status,checked_in_at,notes,created_at,members(full_name)')
        .eq('event_id', eventId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['members'];
      return <String, dynamic>{
        ...row,
        'member_name': member is Map ? member['full_name'] : null,
        'companion_name': row['guest_name'],
        'registered_at': row['created_at'],
      };
    }).toList();
  }

  Future<Map<String, dynamic>> addParticipant({
    required String eventId,
    required String memberId,
    required String memberName,
    String? companionName,
  }) async {
    _require(AppPermission.manageEventParticipants);
    if (AppConfig.demoMode) {
      return _dataService.insert('event_participants', {
        'event_id': eventId,
        'member_id': memberId,
        'member_name': memberName,
        'companion_name': companionName,
        'status': 'confirmed',
        'registered_at': DateTime.now().toIso8601String(),
      });
    }

    final response = await _client
        .from('event_registrations')
        .insert({
          'event_id': eventId,
          'member_id': memberId,
          'guest_name': companionName?.trim().isEmpty == true
              ? null
              : companionName?.trim(),
          'status': 'confirmed',
        })
        .select()
        .single();
    return <String, dynamic>{
      ...Map<String, dynamic>.from(response),
      'member_name': memberName,
      'companion_name': companionName,
    };
  }

  Future<List<Map<String, dynamic>>> volunteers(String eventId) async {
    _require(AppPermission.viewEvents);
    if (AppConfig.demoMode) {
      return _dataService.listWhere(
        'event_volunteers',
        field: 'event_id',
        value: eventId,
      );
    }

    final response = await _client
        .from('event_volunteers')
        .select('id,event_id,member_id,function_name,status,created_at,members(full_name)')
        .eq('event_id', eventId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['members'];
      return <String, dynamic>{
        ...row,
        'member_name': member is Map ? member['full_name'] : null,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> addVolunteer({
    required String eventId,
    required String memberId,
    required String memberName,
    required String functionName,
  }) async {
    _require(AppPermission.manageEventParticipants);
    if (functionName.trim().isEmpty) {
      throw ArgumentError('Indica a função do voluntário.');
    }
    if (AppConfig.demoMode) {
      return _dataService.insert('event_volunteers', {
        'event_id': eventId,
        'member_id': memberId,
        'member_name': memberName,
        'function_name': functionName,
        'status': 'confirmed',
      });
    }

    final response = await _client
        .from('event_volunteers')
        .insert({
          'club_id': AppSession.instance.clubId,
          'event_id': eventId,
          'member_id': memberId,
          'function_name': functionName.trim(),
          'status': 'confirmed',
        })
        .select()
        .single();
    return <String, dynamic>{
      ...Map<String, dynamic>.from(response),
      'member_name': memberName,
    };
  }

  Future<Map<String, dynamic>> financialSummary(String eventId) async {
    _require(AppPermission.viewEvents);
    final List<Map<String, dynamic>> movements;
    if (AppConfig.demoMode) {
      movements = await _dataService.listWhere(
        'financial_transactions',
        field: 'event_id',
        value: eventId,
      );
    } else {
      final response = await _client
          .from('treasury_transactions')
          .select()
          .eq('club_id', AppSession.instance.clubId)
          .eq('event_id', eventId)
          .order('transaction_date', ascending: false);
      movements = List<Map<String, dynamic>>.from(response);
    }

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
