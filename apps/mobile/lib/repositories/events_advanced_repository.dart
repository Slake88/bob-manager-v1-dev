import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class EventsAdvancedRepository {
  EventsAdvancedRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  bool get isDemo => AppConfig.demoMode;
  bool get canPropose => AppSession.instance.can(AppPermission.proposeEvents);
  bool get canApprove => AppSession.instance.can(AppPermission.approveEventProposals);
  bool get canManageParticipants =>
      AppSession.instance.can(AppPermission.manageEventParticipants);
  bool get canManageRoadbook =>
      AppSession.instance.can(AppPermission.manageEventRoadbook);
  bool get canManageOperations =>
      AppSession.instance.can(AppPermission.manageEventOperations);
  bool get canManageRockRide =>
      AppSession.instance.can(AppPermission.manageRockRide);
  bool get canManageFinance =>
      AppSession.instance.can(AppPermission.manageEventFinance);

  Future<List<Map<String, dynamic>>> listProposals() async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-proposal-1',
          'club_id': AppSession.instance.clubId,
          'proposed_by': AppSession.instance.profileId,
          'name': 'Passeio Serra da Arrábida',
          'description': 'Proposta de passeio de domingo.',
          'location': 'Setúbal',
          'event_kind': 'ride',
          'status': 'submitted',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    }
    final response = await _supabase
        .from('event_proposals')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('created_at', ascending: false)
        .limit(250);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> submitProposal({
    required String name,
    String description = '',
    String location = '',
    DateTime? startsAt,
    DateTime? endsAt,
    String eventKind = 'general',
  }) async {
    _require(AppPermission.proposeEvents);
    if (name.trim().isEmpty) throw ArgumentError('Indica o nome do evento.');
    if (isDemo) return 'demo-proposal-${DateTime.now().millisecondsSinceEpoch}';
    final response = await _supabase.rpc(
      'submit_event_proposal_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_name': name.trim(),
        'p_description': _nullable(description),
        'p_location': _nullable(location),
        'p_starts_at': startsAt?.toIso8601String(),
        'p_ends_at': endsAt?.toIso8601String(),
        'p_event_kind': eventKind,
      },
    );
    return response.toString();
  }

  Future<String> approveProposal(String proposalId, {String notes = ''}) async {
    _require(AppPermission.approveEventProposals);
    if (isDemo) return 'demo-approved-event';
    final response = await _supabase.rpc(
      'approve_event_proposal_v1',
      params: {'p_proposal': proposalId, 'p_notes': _nullable(notes)},
    );
    return response.toString();
  }

  Future<void> rejectProposal(String proposalId, {String notes = ''}) async {
    _require(AppPermission.approveEventProposals);
    if (isDemo) return;
    await _supabase.rpc(
      'reject_event_proposal_v1',
      params: {'p_proposal': proposalId, 'p_notes': _nullable(notes)},
    );
  }

  Future<void> withdrawProposal(String proposalId) async {
    _require(AppPermission.proposeEvents);
    if (isDemo) return;
    await _supabase.rpc(
      'withdraw_event_proposal_v1',
      params: {'p_proposal': proposalId},
    );
  }

  Future<Map<String, dynamic>> overview(String eventId) async {
    final values = await Future.wait<dynamic>([
      listGuests(eventId),
      listRoutes(eventId),
      listBands(eventId),
      listExhibitors(eventId),
      listSponsors(eventId),
      listTasks(eventId),
      listShifts(eventId),
      listIncidents(eventId),
      listProgram(eventId),
      getOctaneConfig(eventId),
    ]);
    final tasks = values[5] as List<Map<String, dynamic>>;
    final incidents = values[7] as List<Map<String, dynamic>>;
    return <String, dynamic>{
      'guests': (values[0] as List).length,
      'routes': (values[1] as List).length,
      'bands': (values[2] as List).length,
      'exhibitors': (values[3] as List).length,
      'sponsors': (values[4] as List).length,
      'tasks': tasks.length,
      'tasks_open': tasks
          .where((row) => row['status'] != 'done' && row['status'] != 'cancelled')
          .length,
      'shifts': (values[6] as List).length,
      'incidents': incidents.length,
      'incidents_open': incidents
          .where((row) => row['status'] != 'resolved' && row['status'] != 'closed')
          .length,
      'program': (values[8] as List).length,
      'octane_configured': values[9] != null,
    };
  }

  Future<List<Map<String, dynamic>>> listGuests(String eventId) async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-guest',
          'event_id': eventId,
          'host_member_id': 'm1',
          'name': 'Acompanhante',
          'status': 'confirmed',
        },
      ];
    }
    final response = await _supabase
        .from('event_guests')
        .select()
        .eq('event_id', eventId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> addGuest({
    required String eventId,
    required String hostMemberId,
    required String name,
    String? registrationId,
  }) async {
    _require(AppPermission.manageEventParticipants);
    return _saveEventRow(
      'event_guests',
      eventId,
      {
        'host_member_id': hostMemberId,
        'registration_id': registrationId,
        'name': name.trim(),
        'status': 'confirmed',
      },
    );
  }

  Future<List<Map<String, dynamic>>> listRoutes(String eventId) async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-route',
          'event_id': eventId,
          'name': 'Roadbook principal',
          'start_location': 'Club House',
          'end_location': 'Serra da Arrábida',
          'distance_km': 82.5,
          'estimated_minutes': 120,
          'active': true,
        },
      ];
    }
    final response = await _supabase
        .from('event_routes')
        .select()
        .eq('event_id', eventId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveRoute(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventRoadbook);
    return _saveEventRow('event_routes', eventId, values, id: id);
  }

  Future<List<Map<String, dynamic>>> listRouteStops(String routeId) async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-stop-1',
          'route_id': routeId,
          'sequence_no': 1,
          'name': 'Ponto de encontro',
          'location': 'Club House',
        },
        {
          'id': 'demo-stop-2',
          'route_id': routeId,
          'sequence_no': 2,
          'name': 'Paragem',
          'location': 'Portinho da Arrábida',
        },
      ];
    }
    final response = await _supabase
        .from('event_route_stops')
        .select()
        .eq('route_id', routeId)
        .order('sequence_no');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveRouteStop({
    required String eventId,
    required String routeId,
    required Map<String, dynamic> values,
    String? id,
  }) async {
    _require(AppPermission.manageEventRoadbook);
    return _saveEventRow(
      'event_route_stops',
      eventId,
      {...values, 'route_id': routeId},
      id: id,
    );
  }

  Future<List<Map<String, dynamic>>> emergencyContacts(String eventId) async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'm1',
          'full_name': 'Israel Sousa',
          'nickname': 'Israel',
          'phone': '900 000 000',
          'emergency_contact': {
            'name': 'Contacto de emergência',
            'phone': '910 000 000',
          },
        },
      ];
    }
    final response = await _supabase
        .from('event_registrations')
        .select('member_id,members(id,full_name,nickname,phone,emergency_contact)')
        .eq('event_id', eventId)
        .neq('status', 'cancelled')
        .order('created_at');
    return List<Map<String, dynamic>>.from(response)
        .map((row) => row['members'])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listBands(String eventId) =>
      _listEventRows('event_bands', eventId, orderBy: 'slot_start');
  Future<List<Map<String, dynamic>>> listExhibitors(String eventId) =>
      _listEventRows('event_exhibitors', eventId, orderBy: 'name');
  Future<List<Map<String, dynamic>>> listSponsors(String eventId) =>
      _listEventRows('event_sponsors', eventId, orderBy: 'name');

  Future<Map<String, dynamic>> saveBand(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _requireRockRideWrite();
    return _saveEventRow('event_bands', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> saveExhibitor(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _requireRockRideWrite();
    return _saveEventRow('event_exhibitors', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> saveSponsor(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _requireRockRideWrite();
    return _saveEventRow('event_sponsors', eventId, values, id: id);
  }

  Future<Map<String, dynamic>?> getOctaneConfig(String eventId) async {
    if (isDemo) {
      return <String, dynamic>{
        'event_id': eventId,
        'unit_price': 1.5,
        'five_card_units': 5,
        'five_card_price': 7.0,
        'ten_card_units': 10,
        'ten_card_price': 13.0,
        'ten_card_bonus': 1,
        'active': true,
      };
    }
    final response = await _supabase
        .from('event_octane_configs')
        .select()
        .eq('event_id', eventId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> saveOctaneConfig(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _requireRockRideWrite();
    return _saveEventRow('event_octane_configs', eventId, values, id: id);
  }

  Future<List<Map<String, dynamic>>> listTasks(String eventId) =>
      _listEventRows('event_tasks', eventId, orderBy: 'due_at');
  Future<List<Map<String, dynamic>>> listTaskAssignees(String eventId) =>
      _listEventRows('event_task_assignees', eventId, orderBy: 'assigned_at');
  Future<List<Map<String, dynamic>>> listShifts(String eventId) =>
      _listEventRows('event_shifts', eventId, orderBy: 'starts_at');
  Future<List<Map<String, dynamic>>> listShiftMembers(String eventId) =>
      _listEventRows('event_shift_members', eventId);
  Future<List<Map<String, dynamic>>> listProgram(String eventId) =>
      _listEventRows('event_program', eventId, orderBy: 'sequence_no');
  Future<List<Map<String, dynamic>>> listIncidents(String eventId) =>
      _listEventRows(
        'event_incidents',
        eventId,
        orderBy: 'occurred_at',
        ascending: false,
      );

  Future<Map<String, dynamic>> saveTask(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow('event_tasks', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> assignTask({
    required String eventId,
    required String taskId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow(
      'event_task_assignees',
      eventId,
      {'task_id': taskId, 'member_id': memberId},
    );
  }

  Future<void> acknowledgeTask(
    String assignmentId, {
    bool complete = false,
  }) async {
    if (isDemo) return;
    await _supabase.rpc(
      'acknowledge_event_task_v1',
      params: {'p_assignment': assignmentId, 'p_complete': complete},
    );
  }

  Future<Map<String, dynamic>> saveShift(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow('event_shifts', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> assignShift({
    required String eventId,
    required String shiftId,
    required String memberId,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow(
      'event_shift_members',
      eventId,
      {'shift_id': shiftId, 'member_id': memberId, 'status': 'assigned'},
    );
  }

  Future<void> setShiftMemberStatus(
    String assignmentId,
    String status,
  ) async {
    if (isDemo) return;
    await _supabase.rpc(
      'set_event_shift_member_status_v1',
      params: {'p_assignment': assignmentId, 'p_status': status},
    );
  }

  Future<Map<String, dynamic>> saveProgramItem(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageEventOperations);
    return _saveEventRow('event_program', eventId, values, id: id);
  }

  Future<Map<String, dynamic>> saveIncident(
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    if (!canManageOperations &&
        !AppSession.instance.can(AppPermission.viewEvents)) {
      throw StateError('Sem permissão para registar incidentes.');
    }
    return _saveEventRow('event_incidents', eventId, values, id: id);
  }

  Future<List<Map<String, dynamic>>> _listEventRows(
    String table,
    String eventId, {
    String? orderBy,
    bool ascending = true,
  }) async {
    final List<dynamic> response;
    if (isDemo) return _demoRows(table, eventId);
    if (orderBy == null) {
      response = await _supabase
          .from(table)
          .select()
          .eq('event_id', eventId)
          .limit(500);
    } else {
      response = await _supabase
          .from(table)
          .select()
          .eq('event_id', eventId)
          .order(orderBy, ascending: ascending)
          .limit(500);
    }
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> _saveEventRow(
    String table,
    String eventId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    final payload = <String, dynamic>{
      ...values,
      'club_id': AppSession.instance.clubId,
      'event_id': eventId,
    };
    if (isDemo) {
      return <String, dynamic>{
        'id': id ?? 'demo-${DateTime.now().microsecondsSinceEpoch}',
        ...payload,
      };
    }
    if (id == null) {
      final response =
          await _supabase.from(table).insert(payload).select().single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from(table)
        .update(values)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  List<Map<String, dynamic>> _demoRows(String table, String eventId) {
    return switch (table) {
      'event_bands' => [
          {
            'id': 'demo-band',
            'event_id': eventId,
            'name': 'RAD — Rock All Day',
            'status': 'confirmed',
          },
        ],
      'event_exhibitors' => [
          {
            'id': 'demo-exhibitor',
            'event_id': eventId,
            'name': 'Man Cave Motorcycles',
            'status': 'confirmed',
          },
        ],
      'event_sponsors' => [
          {
            'id': 'demo-sponsor',
            'event_id': eventId,
            'name': 'Apoio local',
            'status': 'confirmed',
          },
        ],
      'event_tasks' => [
          {
            'id': 'demo-task',
            'event_id': eventId,
            'title': 'Preparar recinto',
            'status': 'in_progress',
            'priority': 'high',
          },
        ],
      'event_task_assignees' => <Map<String, dynamic>>[],
      'event_shifts' => [
          {
            'id': 'demo-shift',
            'event_id': eventId,
            'name': 'Bar — Turno 1',
            'area': 'Bar',
            'starts_at': DateTime.now().toIso8601String(),
            'ends_at': DateTime.now()
                .add(const Duration(hours: 2))
                .toIso8601String(),
            'status': 'planned',
          },
        ],
      'event_shift_members' => <Map<String, dynamic>>[],
      'event_program' => [
          {
            'id': 'demo-program',
            'event_id': eventId,
            'sequence_no': 1,
            'title': 'Abertura de portas',
            'item_type': 'activity',
          },
        ],
      'event_incidents' => <Map<String, dynamic>>[],
      _ => <Map<String, dynamic>>[],
    };
  }

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  void _requireRockRideWrite() {
    if (!canManageRockRide && !canManageFinance) {
      throw StateError('Sem permissão para gerir o Rock & Ride In.');
    }
  }
}

String eventKindLabel(Object? value) => switch (value?.toString()) {
      'ride' => 'Passeio',
      'rock_ride_in' => 'Rock & Ride In',
      _ => 'Evento',
    };

String proposalStatusLabel(Object? value) => switch (value?.toString()) {
      'submitted' => 'Em aprovação',
      'approved' => 'Aprovada',
      'rejected' => 'Rejeitada',
      'withdrawn' => 'Retirada',
      _ => value?.toString() ?? '—',
    };

int octaneCardTotalUnits(Map<String, dynamic> config) {
  final base = int.tryParse(config['ten_card_units']?.toString() ?? '') ?? 0;
  final bonus = int.tryParse(config['ten_card_bonus']?.toString() ?? '') ?? 0;
  return base + bonus;
}

String? _nullable(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
