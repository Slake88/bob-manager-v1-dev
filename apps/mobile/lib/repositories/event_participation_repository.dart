import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class EventParticipationRepository {
  EventParticipationRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  SupabaseClient get _client => Supabase.instance.client;
  AppRole get _role => AppRole.fromValue(AppSession.instance.role);

  bool get canManageAll =>
      PermissionPolicy.allows(_role, AppPermission.manageEventParticipants);

  Future<Map<String, dynamic>?> currentMember() async {
    _requireView();

    if (AppConfig.demoMode) {
      final members = await _dataService.list('members');
      for (final member in members) {
        if (member['profile_id']?.toString() == AppSession.instance.profileId) {
          return Map<String, dynamic>.from(member);
        }
      }
      return null;
    }

    final response = await _client
        .from('members')
        .select('id,full_name,nickname,profile_id,status')
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId)
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> registrations(String eventId) async {
    _requireView();

    if (AppConfig.demoMode) {
      final allRows = await _dataService.list('event_participants');
      final rows = allRows
          .where((row) => row['event_id']?.toString() == eventId)
          .toList();
      return rows.map((row) {
        final companion = row['companion_name']?.toString().trim() ?? '';
        return <String, dynamic>{
          ...row,
          'companions': companion.isEmpty
              ? <Map<String, dynamic>>[]
              : <Map<String, dynamic>>[
                  {
                    'id': 'demo:${row['id']}:guest',
                    'guest_name': companion,
                  },
                ],
        };
      }).toList();
    }

    final response = await _client
        .from('event_registrations')
        .select(
          'id,event_id,member_id,status,checked_in_at,notes,created_at,'
          'members(full_name,nickname,profile_id),'
          'event_registration_guests(id,guest_name,created_at)',
        )
        .eq('event_id', eventId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['members'];
      final rawGuests = row['event_registration_guests'];
      final companions = rawGuests is List
          ? List<Map<String, dynamic>>.from(rawGuests)
          : <Map<String, dynamic>>[];
      companions.sort(
        (a, b) => (a['created_at']?.toString() ?? '')
            .compareTo(b['created_at']?.toString() ?? ''),
      );

      String? memberName;
      String? memberProfileId;
      if (member is Map) {
        final nickname = member['nickname']?.toString().trim() ?? '';
        final fullName = member['full_name']?.toString().trim() ?? '';
        memberName = nickname.isNotEmpty
            ? nickname
            : (fullName.isEmpty ? null : fullName);
        memberProfileId = member['profile_id']?.toString();
      }

      return <String, dynamic>{
        ...row,
        'member_name': memberName,
        'member_profile_id': memberProfileId,
        'companions': companions,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> registerSelf({required String eventId}) async {
    _requireView();
    final member = await currentMember();
    if (member == null) {
      throw StateError(
        'A tua conta ainda não está associada a uma ficha de membro.',
      );
    }
    return _insertRegistration(
      eventId: eventId,
      memberId: member['id'].toString(),
      memberName: member['full_name']?.toString() ?? 'Membro',
    );
  }

  Future<Map<String, dynamic>> registerMember({
    required String eventId,
    required String memberId,
    required String memberName,
  }) async {
    if (!canManageAll) {
      throw StateError('Sem permissão para adicionar outros participantes.');
    }
    return _insertRegistration(
      eventId: eventId,
      memberId: memberId,
      memberName: memberName,
    );
  }

  Future<Map<String, dynamic>> _insertRegistration({
    required String eventId,
    required String memberId,
    required String memberName,
  }) async {
    if (AppConfig.demoMode) {
      final allRows = await _dataService.list('event_participants');
      final existing = allRows
          .where((row) => row['event_id']?.toString() == eventId)
          .toList();
      if (existing.any((row) => row['member_id']?.toString() == memberId)) {
        throw StateError('Este membro já está inscrito neste evento.');
      }
      return _dataService.insert('event_participants', {
        'event_id': eventId,
        'member_id': memberId,
        'member_name': memberName,
        'companion_name': null,
        'status': 'confirmed',
        'registered_at': DateTime.now().toIso8601String(),
      });
    }

    try {
      final response = await _client
          .from('event_registrations')
          .insert({
            'event_id': eventId,
            'member_id': memberId,
            'status': 'confirmed',
          })
          .select()
          .single();
      return <String, dynamic>{
        ...Map<String, dynamic>.from(response),
        'member_name': memberName,
        'companions': <Map<String, dynamic>>[],
      };
    } on PostgrestException catch (error) {
      throw StateError(_friendly(error));
    }
  }

  Future<Map<String, dynamic>> addCompanion({
    required String registrationId,
    required String name,
  }) async {
    _requireView();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Indica o nome do acompanhante.');
    }

    if (AppConfig.demoMode) {
      throw StateError(
        'A gestão de vários acompanhantes requer ligação ao servidor.',
      );
    }

    try {
      final response = await _client
          .from('event_registration_guests')
          .insert({
            'registration_id': registrationId,
            'guest_name': normalized,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (error) {
      throw StateError(_friendly(error));
    }
  }

  Future<void> removeCompanion(String companionId) async {
    _requireView();
    if (AppConfig.demoMode) return;
    try {
      await _client
          .from('event_registration_guests')
          .delete()
          .eq('id', companionId);
    } on PostgrestException catch (error) {
      throw StateError(_friendly(error));
    }
  }

  Future<void> cancelRegistration(String registrationId) async {
    _requireView();
    if (AppConfig.demoMode) {
      await _dataService.delete('event_participants', registrationId);
      return;
    }
    try {
      await _client
          .from('event_registrations')
          .delete()
          .eq('id', registrationId);
    } on PostgrestException catch (error) {
      throw StateError(_friendly(error));
    }
  }

  void _requireView() {
    if (!PermissionPolicy.allows(_role, AppPermission.viewEvents)) {
      throw StateError('Sem permissão para consultar eventos.');
    }
  }

  String _friendly(PostgrestException error) {
    final text = '${error.code} ${error.message} ${error.details}'.toLowerCase();
    if (text.contains('23505') || text.contains('duplicate key')) {
      if (text.contains('event_registration_guests')) {
        return 'Este acompanhante já está associado a esta inscrição.';
      }
      return 'Este membro já está inscrito neste evento.';
    }
    if (text.contains('row-level security') ||
        text.contains('permission') ||
        text.contains('42501')) {
      return 'Não tens permissão para alterar esta inscrição.';
    }
    if (text.contains('check constraint')) {
      return 'Confirma os dados do acompanhante.';
    }
    return 'Não foi possível atualizar a inscrição no evento.';
  }
}
