import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class AuditLogFilters {
  const AuditLogFilters({
    this.dateFrom,
    this.dateTo,
    this.entityTypes,
    this.excludeEntityTypes = false,
    this.action,
    this.actorQuery,
    this.search,
    this.entityId,
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String>? entityTypes;
  final bool excludeEntityTypes;
  final String? action;
  final String? actorQuery;
  final String? search;
  final String? entityId;

  Map<String, dynamic> toRpcParams({
    AuditLogCursor? cursor,
    int limit = 50,
  }) {
    final normalizedTypes = entityTypes
        ?.map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return {
      'p_created_from': _auditDateStartUtc(dateFrom)?.toIso8601String(),
      'p_created_before': _auditDayAfterUtc(dateTo)?.toIso8601String(),
      'p_entity_types': normalizedTypes?.isEmpty == true ? null : normalizedTypes,
      'p_exclude_entity_types': excludeEntityTypes,
      'p_action': _auditOptionalText(action),
      'p_actor_query': _auditOptionalText(actorQuery),
      'p_search': _auditOptionalText(search),
      'p_entity_id': _auditOptionalText(entityId),
      'p_cursor_created_at': cursor?.createdAt.toUtc().toIso8601String(),
      'p_cursor_id': cursor?.id,
      'p_limit': limit.clamp(1, 50),
    };
  }
}

class AuditLogCursor {
  const AuditLogCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final int id;

  factory AuditLogCursor.fromRow(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final id = int.tryParse(row['id']?.toString() ?? '');
    if (createdAt == null || id == null) {
      throw const FormatException('Registo de auditoria sem cursor válido.');
    }
    return AuditLogCursor(createdAt: createdAt.toUtc(), id: id);
  }
}

class AuditLogPage {
  const AuditLogPage({
    required this.rows,
    required this.hasMore,
    this.nextCursor,
  });

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
  final AuditLogCursor? nextCursor;

  factory AuditLogPage.fromRows(
    List<Map<String, dynamic>> source, {
    required int limit,
  }) {
    final safeLimit = limit.clamp(1, 50);
    final hasMore = source.length > safeLimit;
    final rows = source.take(safeLimit).map(_withAuditActor).toList();
    return AuditLogPage(
      rows: rows,
      hasMore: hasMore,
      nextCursor: hasMore && rows.isNotEmpty
          ? AuditLogCursor.fromRow(rows.last)
          : null,
    );
  }
}

DateTime? _auditDateStartUtc(DateTime? value) => value == null
    ? null
    : DateTime(value.year, value.month, value.day).toUtc();

DateTime? _auditDayAfterUtc(DateTime? value) => value == null
    ? null
    : DateTime(value.year, value.month, value.day + 1).toUtc();

String? _auditOptionalText(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

Map<String, dynamic> _withAuditActor(Map<String, dynamic> row) => {
      ...row,
      'actor': {
        'full_name': row['actor_name'] ?? (row['actor'] as Map?)?['full_name'],
        'email': row['actor_email'] ?? (row['actor'] as Map?)?['email'],
      },
      'description':
          '${row['action'] ?? 'Alteração'} — ${row['entity_type'] ?? 'registo'}',
    };

class AdminRepository {
  AdminRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;
  SupabaseClient get _client => Supabase.instance.client;
  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listSettings() async {
    _require(AppPermission.manageSettings);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('club_settings');
      rows.sort((a, b) => (a['key']?.toString() ?? '')
          .compareTo(b['key']?.toString() ?? ''));
      return rows;
    }
    final response = await _client
        .from('club_settings')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('key');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveSetting({
    required String key,
    required String value,
    String? settingId,
  }) async {
    _require(AppPermission.manageSettings);
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError('A chave da configuração é obrigatória.');
    }
    if (AppConfig.demoMode) {
      final values = {
        'key': normalizedKey,
        'value': value.trim(),
        'updated_by': AppSession.instance.profileId,
      };
      if (settingId == null) {
        return _dataService.insert('club_settings', values);
      }
      return _dataService.update('club_settings', settingId, values);
    }

    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'key': normalizedKey,
      'value': value.trim(),
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (settingId == null) {
      final response = await _client
          .from('club_settings')
          .upsert(payload, onConflict: 'club_id,key')
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _client
        .from('club_settings')
        .update(payload)
        .eq('id', settingId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAuditLog({int limit = 100}) async {
    _require(AppPermission.manageSettings);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('audit_log', limit: limit);
      rows.sort((a, b) => (b['created_at']?.toString() ?? '')
          .compareTo(a['created_at']?.toString() ?? ''));
      return rows.take(limit).toList();
    }

    final response = await _client.rpc(
      'list_audit_log_v2',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_limit': limit,
      },
    );
    return List<Map<String, dynamic>>.from(response as List).map((row) {
      return <String, dynamic>{
        ...row,
        'actor': {
          'full_name': row['actor_name'],
          'email': row['actor_email'],
        },
        'description':
            '${row['action'] ?? 'Alteração'} — ${row['entity_type'] ?? 'registo'}',
      };
    }).toList();
  }

  Future<AuditLogPage> listAuditLogPage({
    AuditLogFilters filters = const AuditLogFilters(),
    AuditLogCursor? cursor,
    int limit = 50,
  }) async {
    _require(AppPermission.manageSettings);
    final safeLimit = limit.clamp(1, 50);

    if (AppConfig.demoMode) {
      final rows = await _dataService.list('audit_log', limit: 500);
      final sorted = rows.where((row) => _matchesAuditFilters(row, filters))
          .toList()
        ..sort(_compareAuditRowsNewestFirst);
      final afterCursor = cursor == null
          ? sorted
          : sorted.where((row) => _isAfterAuditCursor(row, cursor)).toList();
      return AuditLogPage.fromRows(
        afterCursor.take(safeLimit + 1).toList(),
        limit: safeLimit,
      );
    }

    final response = await _client.rpc(
      'list_audit_log_page_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        ...filters.toRpcParams(cursor: cursor, limit: safeLimit),
      },
    );
    final rows = List<Map<String, dynamic>>.from(response as List);
    return AuditLogPage.fromRows(rows, limit: safeLimit);
  }

  bool _matchesAuditFilters(
    Map<String, dynamic> row,
    AuditLogFilters filters,
  ) {
    final entityType = row['entity_type']?.toString();
    if (filters.entityTypes case final types? when types.isNotEmpty) {
      final contains = entityType != null && types.contains(entityType);
      if (filters.excludeEntityTypes ? contains : !contains) return false;
    }

    final action = _auditOptionalText(filters.action);
    if (action != null && row['action']?.toString() != action) return false;

    final entityId = _auditOptionalText(filters.entityId)?.toLowerCase();
    if (entityId != null &&
        !(row['entity_id']?.toString().toLowerCase() ?? '').contains(entityId)) {
      return false;
    }

    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (filters.dateFrom != null &&
        (createdAt == null ||
            createdAt.isBefore(_auditDateStartUtc(filters.dateFrom)!))) {
      return false;
    }
    if (filters.dateTo != null &&
        (createdAt == null ||
            !createdAt.isBefore(_auditDayAfterUtc(filters.dateTo)!))) {
      return false;
    }

    final actor = row['actor'] as Map?;
    final actorMetadata = [
      row['actor_name'],
      row['actor_email'],
      actor?['full_name'],
      actor?['email'],
      row['actor_id'],
    ].whereType<Object>().join(' ').toLowerCase();
    final metadata = [
      row['actor_name'],
      row['actor_email'],
      actor?['full_name'],
      actor?['email'],
      row['entity_type'],
      row['action'],
      row['entity_id'],
      row['actor_id'],
    ].whereType<Object>().join(' ').toLowerCase();
    final actorQuery = _auditOptionalText(filters.actorQuery)?.toLowerCase();
    final search = _auditOptionalText(filters.search)?.toLowerCase();
    if (actorQuery != null && !actorMetadata.contains(actorQuery)) {
      return false;
    }
    if (search != null && !metadata.contains(search)) return false;
    return true;
  }

  int _compareAuditRowsNewestFirst(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftDate = DateTime.tryParse(left['created_at']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final rightDate =
        DateTime.tryParse(right['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
    final byDate = rightDate.compareTo(leftDate);
    if (byDate != 0) return byDate;
    return (int.tryParse(right['id']?.toString() ?? '') ?? 0)
        .compareTo(int.tryParse(left['id']?.toString() ?? '') ?? 0);
  }

  bool _isAfterAuditCursor(
    Map<String, dynamic> row,
    AuditLogCursor cursor,
  ) {
    final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
    final id = int.tryParse(row['id']?.toString() ?? '');
    if (createdAt == null || id == null) return false;
    return createdAt.isBefore(cursor.createdAt) ||
        (createdAt.isAtSameMomentAs(cursor.createdAt) && id < cursor.id);
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
