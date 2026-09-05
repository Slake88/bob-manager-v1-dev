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

  Future<List<Map<String, dynamic>>> listMonth(int year, int month) async {
    _require(AppPermission.viewEvents);
    final first = DateTime(year, month, 1);
    final next = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);

    final rows = <Map<String, dynamic>>[];

    if (AppConfig.demoMode) {
      final events = await _dataService.list('events');
      for (final event in events) {
        final date = _parseDate(event['starts_at']);
        if (date != null && date.year == year && date.month == month) {
          rows.add({...event, 'calendar_type': 'event'});
        }
      }
      final members = await _dataService.list('members');
      rows.addAll(_anniversariesForMonth(members, year, month));
    } else {
      final result = await Future.wait([
        _client
            .from('events')
            .select()
            .eq('club_id', AppSession.instance.clubId)
            .gte('starts_at', first.toIso8601String())
            .lt('starts_at', next.toIso8601String())
            .order('starts_at'),
        _client
            .from('members')
            .select(
              'id,full_name,nickname,birth_date,prospect_joined_at,full_colors_at,status',
            )
            .eq('club_id', AppSession.instance.clubId)
            .order('full_name'),
      ]);

      rows.addAll(
        List<Map<String, dynamic>>.from(result[0] as List)
            .map((event) => {...event, 'calendar_type': 'event'}),
      );
      rows.addAll(
        _anniversariesForMonth(
          List<Map<String, dynamic>>.from(result[1] as List),
          year,
          month,
        ),
      );
    }

    rows.sort((a, b) {
      final da = _parseDate(a['starts_at']) ?? DateTime(9999);
      final db = _parseDate(b['starts_at']) ?? DateTime(9999);
      final byDate = da.compareTo(db);
      if (byDate != 0) return byDate;
      return (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? '');
    });
    return rows;
  }

  List<Map<String, dynamic>> _anniversariesForMonth(
    List<Map<String, dynamic>> members,
    int year,
    int month,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final member in members) {
      final name = member['nickname']?.toString().trim().isNotEmpty == true
          ? member['nickname'].toString().trim()
          : member['full_name']?.toString() ?? 'Membro';

      void addAnniversary(
        String field,
        String type,
        String label,
      ) {
        final original = _parseDate(member[field]);
        if (original == null || original.month != month) return;
        final years = year - original.year;
        if (years < 0) return;
        final date = DateTime(year, month, original.day);
        rows.add({
          'id': 'anniversary:${member['id']}:$type:$year',
          'member_id': member['id'],
          'name': '$label — $name',
          'starts_at': _dateOnly(date),
          'location': null,
          'status': 'anniversary',
          'calendar_type': type,
          'anniversary_years': years,
          'original_date': _dateOnly(original),
          'is_virtual': true,
        });
      }

      addAnniversary('birth_date', 'birthday', 'Aniversário');
      addAnniversary(
        'prospect_joined_at',
        'prospect_anniversary',
        'Aniversário de Prospect',
      );
      addAnniversary(
        'full_colors_at',
        'full_color_anniversary',
        'Aniversário de Full Color',
      );
    }
    return rows;
  }

  Future<Map<String, dynamic>> saveEvent(
    Map<String, dynamic> values, {
    String? eventId,
  }) async {
    _require(AppPermission.manageEvents);
    final name = values['name']?.toString().trim() ?? '';
    if (name.isEmpty) throw ArgumentError('Indica o nome do evento.');

    final startsAt = _parseDate(values['starts_at']);
    if (startsAt == null) throw ArgumentError('Seleciona a data do evento.');

    final status = values['status']?.toString() ?? 'draft';
    const allowedStatuses = {
      'draft',
      'published',
      'active',
      'completed',
      'cancelled',
    };
    if (!allowedStatuses.contains(status)) {
      throw ArgumentError('Estado do evento inválido.');
    }

    final normalized = <String, dynamic>{
      ...values,
      'name': name,
      'starts_at': startsAt.toIso8601String(),
      'status': status,
      'budget': _asDouble(values['budget']),
    };

    if (AppConfig.demoMode) {
      if (eventId == null) return _dataService.insert('events', normalized);
      return _dataService.update('events', eventId, normalized);
    }

    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'name': normalized['name'],
      'description': normalized['description'],
      'location': normalized['location'],
      'starts_at': normalized['starts_at'],
      'ends_at': normalized['ends_at'],
      'status': normalized['status'],
      'capacity': normalized['capacity'] ?? normalized['expected_attendance'],
      'budget': normalized['budget'],
      'banner_path': normalized['banner_path'],
      'event_mode_enabled': normalized['event_mode_enabled'] == true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
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
    } on PostgrestException catch (error) {
      throw StateError(_friendlyEventError(error));
    }
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
        .select(
          'id,event_id,member_id,guest_name,status,checked_in_at,notes,created_at,members(full_name)',
        )
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
        .select(
          'id,event_id,member_id,function_name,status,created_at,members(full_name)',
        )
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

DateTime? _parseDate(Object? value) {
  if (value is DateTime) return value;
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _friendlyEventError(PostgrestException error) {
  final message = error.message.toLowerCase();
  if (message.contains('event_status') || message.contains('invalid input value')) {
    return 'O estado selecionado para o evento não é válido.';
  }
  if (message.contains('row-level security') || message.contains('permission')) {
    return 'Não tens permissão para guardar este evento.';
  }
  return 'Não foi possível guardar o evento. Confirma os dados e tenta novamente.';
}
