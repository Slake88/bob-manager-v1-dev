import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/weekly_officer_rules.dart';

class WeeklyOfficerRepository {
  WeeklyOfficerRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool get canManage => WeeklyOfficerRules.canManageRole(
        AppSession.instance.role,
        superAdmin: AppSession.instance.superAdmin,
      );

  Future<void> ensureYear(int year) async {
    if (AppConfig.demoMode) return;
    await _supabase.rpc(
      'ensure_weekly_officer_schedule_v1',
      params: {'target_club': _clubId, 'p_year': year},
    );
  }

  Future<String?> currentMemberId() async {
    if (AppConfig.demoMode) return null;
    final response = await _supabase.rpc(
      'current_weekly_officer_member_v1',
      params: {'target_club': _clubId},
    );
    final value = response?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<List<Map<String, dynamic>>> members() async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final response = await _supabase
        .from('members')
        .select('id,member_number,full_name,nickname,status,primary_role,profile_id')
        .eq('club_id', _clubId)
        .limit(1000);
    final rows = List<Map<String, dynamic>>.from(response);
    rows.sort((a, b) {
      final an = _int(a['member_number']) ?? 999999;
      final bn = _int(b['member_number']) ?? 999999;
      final byNumber = an.compareTo(bn);
      if (byNumber != 0) return byNumber;
      return (a['full_name']?.toString() ?? '')
          .compareTo(b['full_name']?.toString() ?? '');
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> listRotation() async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final response = await _supabase
        .from('weekly_officer_rotation')
        .select()
        .eq('club_id', _clubId)
        .order('rotation_order');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listDinners(int year) async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final start = '$year-01-01';
    final end = '$year-12-31';
    final response = await _supabase
        .from('weekly_dinners')
        .select()
        .eq('club_id', _clubId)
        .gte('dinner_date', start)
        .lte('dinner_date', end)
        .order('dinner_date');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAbsences(int year) async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final start = '$year-01-01';
    final end = '$year-12-31';
    final response = await _supabase
        .from('weekly_officer_absences')
        .select()
        .eq('club_id', _clubId)
        .lte('starts_on', end)
        .gte('ends_on', start)
        .order('starts_on');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listSwaps() async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final response = await _supabase
        .from('weekly_officer_swap_requests')
        .select()
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(250);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> setMemberSettings({
    required String memberId,
    required bool enabled,
    required String availabilityStatus,
    required bool forceIncluded,
    String? notes,
  }) async {
    await _supabase.rpc(
      'set_weekly_officer_member_v1',
      params: {
        'target_club': _clubId,
        'p_member': memberId,
        'p_enabled': enabled,
        'p_availability_status': availabilityStatus,
        'p_force_included': forceIncluded,
        'p_notes': _emptyToNull(notes),
      },
    );
  }

  Future<void> reorder(List<String> memberIds) async {
    await _supabase.rpc(
      'reorder_weekly_officer_v1',
      params: {'target_club': _clubId, 'p_member_ids': memberIds},
    );
  }

  Future<String> saveAbsence({
    String? absenceId,
    required String memberId,
    required String kind,
    required DateTime startsOn,
    required DateTime endsOn,
    String? notes,
  }) async {
    final response = await _supabase.rpc(
      'save_weekly_officer_absence_v1',
      params: {
        'target_club': _clubId,
        'p_absence': absenceId,
        'p_member': memberId,
        'p_absence_kind': kind,
        'p_starts_on': _date(startsOn),
        'p_ends_on': _date(endsOn),
        'p_notes': _emptyToNull(notes),
      },
    );
    return response.toString();
  }

  Future<void> deleteAbsence(String absenceId) async {
    await _supabase.rpc(
      'delete_weekly_officer_absence_v1',
      params: {'target_club': _clubId, 'p_absence': absenceId},
    );
  }

  Future<String> saveDinner({
    String? dinnerId,
    required DateTime date,
    String? memberId,
    String? externalName,
    String? dish,
    String? notes,
    String status = 'planned',
  }) async {
    final response = await _supabase.rpc(
      'save_weekly_dinner_v1',
      params: {
        'target_club': _clubId,
        'p_dinner': dinnerId,
        'p_date': _date(date),
        'p_assigned_member': _emptyToNull(memberId),
        'p_external_name': _emptyToNull(externalName),
        'p_dish': _emptyToNull(dish),
        'p_notes': _emptyToNull(notes),
        'p_status': status,
      },
    );
    return response.toString();
  }

  Future<void> setClosed({
    required String dinnerId,
    required bool closed,
    String? notes,
  }) async {
    await _supabase.rpc(
      'set_weekly_dinner_closed_v1',
      params: {
        'target_club': _clubId,
        'p_dinner': dinnerId,
        'p_closed': closed,
        'p_notes': _emptyToNull(notes),
      },
    );
  }

  Future<String> requestSwap({
    required String dinnerId,
    required String requestedMemberId,
    String? note,
  }) async {
    final response = await _supabase.rpc(
      'request_weekly_officer_swap_v1',
      params: {
        'target_club': _clubId,
        'p_dinner': dinnerId,
        'p_requested_member': requestedMemberId,
        'p_note': _emptyToNull(note),
      },
    );
    return response.toString();
  }

  Future<void> respondSwap({
    required String requestId,
    required bool accept,
    String? note,
  }) async {
    await _supabase.rpc(
      'respond_weekly_officer_swap_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_accept': accept,
        'p_note': _emptyToNull(note),
      },
    );
  }

  Future<void> markSwapApplied({
    required String requestId,
    String? note,
  }) async {
    await _supabase.rpc(
      'mark_weekly_officer_swap_applied_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_note': _emptyToNull(note),
      },
    );
  }

  Future<void> cancelSwap(String requestId) async {
    await _supabase.rpc(
      'cancel_weekly_officer_swap_v1',
      params: {'target_club': _clubId, 'p_request': requestId},
    );
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
