import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class AgendaRepository {
  AgendaRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  Future<bool> canManage() async {
    if (AppConfig.demoMode) return AppSession.instance.superAdmin;
    final response = await _supabase.rpc(
      'can_manage_agenda_v1',
      params: {'target_club': _clubId},
    );
    return response == true || response?.toString().toLowerCase() == 'true';
  }

  Future<void> ensureDinnerYears(DateTime from, DateTime to) async {
    if (AppConfig.demoMode) return;
    for (var year = from.year; year <= to.year; year++) {
      await _supabase.rpc(
        'ensure_weekly_officer_schedule_v1',
        params: {'target_club': _clubId, 'p_year': year},
      );
    }
  }

  Future<List<Map<String, dynamic>>> calendar(
    DateTime from,
    DateTime to,
  ) async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];
    final response = await _supabase.rpc(
      'agenda_calendar_v1',
      params: {
        'target_club': _clubId,
        'p_from': _date(from),
        'p_to': _date(to),
      },
    );
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<Map<String, dynamic>?> manualItem(String itemId) async {
    if (AppConfig.demoMode) return null;
    final response = await _supabase
        .from('agenda_items')
        .select()
        .eq('club_id', _clubId)
        .eq('id', itemId)
        .maybeSingle();
    return response;
  }

  Future<String> saveManualItem({
    String? itemId,
    required String itemType,
    required String title,
    String? description,
    required DateTime startsAt,
    DateTime? endsAt,
    required bool allDay,
    String? location,
    required String audience,
    required String priority,
    required String status,
    bool notifyNow = false,
  }) async {
    final response = await _supabase.rpc(
      'save_agenda_item_v1',
      params: {
        'target_club': _clubId,
        'p_item': _emptyToNull(itemId),
        'p_item_type': itemType,
        'p_title': title.trim(),
        'p_description': _emptyToNull(description),
        'p_starts_at': startsAt.toUtc().toIso8601String(),
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
        'p_all_day': allDay,
        'p_location': _emptyToNull(location),
        'p_audience': audience,
        'p_priority': priority,
        'p_status': status,
        'p_notify_now': notifyNow,
      },
    );
    return response.toString();
  }

  Future<void> cancelManualItem(String itemId, {String? reason}) async {
    await _supabase.rpc(
      'cancel_agenda_item_v1',
      params: {
        'target_club': _clubId,
        'p_item': itemId,
        'p_reason': _emptyToNull(reason),
      },
    );
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
