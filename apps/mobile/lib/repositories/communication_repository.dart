import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
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
  SupabaseClient get _client => Supabase.instance.client;

  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageCommunication);

  Future<List<Map<String, dynamic>>> listAnnouncements() async {
    _require(AppPermission.viewCommunication);

    if (AppConfig.demoMode) {
      final rows = await _dataService.list('announcements');
      final visible = rows.where(_isVisibleForCurrentRole).toList();
      visible.sort((a, b) => (b['published_at']?.toString() ?? '')
          .compareTo(a['published_at']?.toString() ?? ''));
      return visible;
    }

    final response = await _client
        .from('announcements')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('published_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response);
    final acknowledgements = await _client
        .from('announcement_acknowledgements')
        .select('announcement_id')
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', AppSession.instance.profileId);
    final acknowledgedIds = List<Map<String, dynamic>>.from(acknowledgements)
        .map((row) => row['announcement_id']?.toString())
        .whereType<String>()
        .toSet();

    final now = DateTime.now();
    return rows.where((row) {
      if (!_canManage) {
        final publishedAt = DateTime.tryParse(
          row['published_at']?.toString() ?? '',
        );
        final expiresAt = DateTime.tryParse(
          row['expires_at']?.toString() ?? '',
        );
        if (publishedAt != null && publishedAt.isAfter(now)) return false;
        if (expiresAt != null && !expiresAt.isAfter(now)) return false;
      }
      return _isVisibleForCurrentRole(row);
    }).map((row) {
      return <String, dynamic>{
        ...row,
        'acknowledged': acknowledgedIds.contains(row['id']?.toString()),
      };
    }).toList();
  }

  Future<Map<String, dynamic>> saveAnnouncement(
    Map<String, dynamic> values, {
    String? announcementId,
  }) async {
    _require(AppPermission.manageCommunication);

    if (AppConfig.demoMode) {
      final payload = Map<String, dynamic>.from(values)
        ..['updated_at'] = DateTime.now().toIso8601String();
      if (announcementId == null) {
        payload['created_by'] = AppSession.instance.profileId;
        payload['published_at'] ??= DateTime.now().toIso8601String();
        return _dataService.insert('announcements', payload);
      }
      return _dataService.update('announcements', announcementId, payload);
    }

    final publishedAt = _dateTimeOrNow(values['published_at']);
    final expiresAt = _optionalDateTime(values['expires_at']);
    if (expiresAt != null && !expiresAt.isAfter(publishedAt)) {
      throw ArgumentError('A expiração tem de ser posterior à publicação.');
    }

    final title = values['title']?.toString().trim() ?? '';
    final body = values['body']?.toString().trim() ?? '';
    if (title.isEmpty || body.isEmpty) {
      throw ArgumentError('O título e a mensagem são obrigatórios.');
    }

    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'title': title,
      'body': body,
      'priority': _normalizePriority(values['priority']),
      'audience': _normalizeAudience(values['audience']),
      'published_at': publishedAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'requires_acknowledgement':
          values['requires_acknowledgement'] == true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (announcementId == null) {
      payload['created_by'] = AppSession.instance.profileId;
      final response = await _client
          .from('announcements')
          .insert(payload)
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _client
        .from('announcements')
        .update(payload)
        .eq('id', announcementId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> deleteAnnouncement(String announcementId) async {
    _require(AppPermission.manageCommunication);
    if (AppConfig.demoMode) {
      return _dataService.delete('announcements', announcementId);
    }
    await _client
        .from('announcements')
        .delete()
        .eq('id', announcementId)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<void> acknowledge(String announcementId) async {
    _require(AppPermission.acknowledgeCommunication);

    if (AppConfig.demoMode) {
      final existing = await _dataService.listWhere(
        'announcement_acknowledgements',
        field: 'announcement_id',
        value: announcementId,
      );
      if (existing.any(
        (row) =>
            row['profile_id']?.toString() == AppSession.instance.profileId,
      )) {
        return;
      }
      await _dataService.insert('announcement_acknowledgements', {
        'announcement_id': announcementId,
        'profile_id': AppSession.instance.profileId,
        'acknowledged_at': DateTime.now().toIso8601String(),
      });
      return;
    }

    final announcement = await _client
        .from('announcements')
        .select('id,club_id,requires_acknowledgement')
        .eq('id', announcementId)
        .eq('club_id', AppSession.instance.clubId)
        .maybeSingle();
    if (announcement == null) {
      throw StateError('Comunicado não encontrado.');
    }
    if (announcement['requires_acknowledgement'] != true) return;

    await _client.from('announcement_acknowledgements').upsert({
      'club_id': AppSession.instance.clubId,
      'announcement_id': announcementId,
      'profile_id': AppSession.instance.profileId,
      'acknowledged_at': DateTime.now().toIso8601String(),
    }, onConflict: 'announcement_id,profile_id');
  }

  Future<bool> isAcknowledged(String announcementId) async {
    if (AppConfig.demoMode) {
      final rows = await _dataService.listWhere(
        'announcement_acknowledgements',
        field: 'announcement_id',
        value: announcementId,
      );
      return rows.any(
        (row) =>
            row['profile_id']?.toString() == AppSession.instance.profileId,
      );
    }

    final response = await _client
        .from('announcement_acknowledgements')
        .select('id')
        .eq('announcement_id', announcementId)
        .eq('profile_id', AppSession.instance.profileId)
        .maybeSingle();
    return response != null;
  }

  bool _isVisibleForCurrentRole(Map<String, dynamic> row) {
    if (_canManage) return true;
    final audience = _normalizeAudience(row['audience']);
    return switch (audience) {
      'all' => true,
      'members' => _role != AppRole.prospect && _role != AppRole.unknown,
      'prospects' => _role == AppRole.prospect,
      'leadership' => const {
          AppRole.president,
          AppRole.vicePresident,
          AppRole.administrator,
          AppRole.treasurer,
          AppRole.secretary,
          AppRole.roadCaptain,
        }.contains(_role),
      'treasury' => const {
          AppRole.president,
          AppRole.vicePresident,
          AppRole.administrator,
          AppRole.treasurer,
        }.contains(_role),
      'events' => const {
          AppRole.president,
          AppRole.vicePresident,
          AppRole.administrator,
          AppRole.roadCaptain,
          AppRole.eventsManager,
        }.contains(_role),
      _ => true,
    };
  }

  String _normalizePriority(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? 'normal';
    return const {'informative', 'normal', 'important', 'urgent', 'critical'}
            .contains(normalized)
        ? normalized
        : 'normal';
  }

  String _normalizeAudience(Object? value) {
    final normalized = (value?.toString() ?? 'all')
        .trim()
        .toLowerCase()
        .replaceAll('ã', 'a')
        .replaceAll('ç', 'c')
        .replaceAll('ó', 'o');
    if (normalized.isEmpty ||
        normalized == 'all' ||
        normalized.contains('todos')) {
      return 'all';
    }
    if (normalized == 'members' || normalized.contains('membros')) {
      return 'members';
    }
    if (normalized == 'prospects' || normalized.contains('prospect')) {
      return 'prospects';
    }
    if (normalized == 'leadership' || normalized.contains('direcao')) {
      return 'leadership';
    }
    if (normalized == 'treasury' || normalized.contains('tesour')) {
      return 'treasury';
    }
    if (normalized == 'events' || normalized.contains('evento')) {
      return 'events';
    }
    return 'all';
  }

  DateTime _dateTimeOrNow(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  DateTime? _optionalDateTime(Object? value) {
    final raw = value?.toString().trim() ?? '';
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(_role, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
