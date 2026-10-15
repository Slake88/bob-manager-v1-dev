import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/club_export.dart';

part 'club_export_specs_members_finance.dart';
part 'club_export_specs_operations.dart';
part 'club_export_specs_support.dart';

class ClubExportRepository {
  ClubExportRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  Future<String> begin({
    required Set<ClubExportSection> sections,
    required bool includeSensitive,
    required bool includeFiles,
  }) async {
    _ensureProduction();
    if (!ClubExportPolicy.canExport(AppSession.instance)) {
      throw const ClubExportFailure(
        'permission_denied',
        'Sem permissão para exportação integral.',
      );
    }
    final response = await _client.rpc(
      'begin_club_export_v1',
      params: {
        'target_club': _clubId,
        'p_modules': sections.map((section) => section.key).toList(),
        'p_include_sensitive': includeSensitive,
        'p_include_files': includeFiles,
        'p_manifest_version': 'bob-export-v1',
      },
    );
    return response.toString();
  }

  Future<void> complete({
    required String exportId,
    required int datasetCount,
    required int rowCount,
    required int fileCount,
    required int byteSize,
  }) async {
    _ensureProduction();
    await _client.rpc(
      'complete_club_export_v1',
      params: {
        'target_club': _clubId,
        'p_export': exportId,
        'p_dataset_count': datasetCount,
        'p_row_count': rowCount,
        'p_file_count': fileCount,
        'p_byte_size': byteSize,
      },
    );
  }

  Future<void> fail({
    required String exportId,
    required String errorCode,
  }) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'fail_club_export_v1',
      params: {
        'target_club': _clubId,
        'p_export': exportId,
        'p_error_code': errorCode,
      },
    );
  }

  Future<List<Map<String, dynamic>>> history({int limit = 20}) async {
    _ensureProduction();
    final response = await _client
        .from('exports')
        .select(
          'id,status,modules,include_sensitive,include_files,manifest_version,'
          'dataset_count,row_count,file_count,byte_size,error_code,'
          'requested_at,completed_at',
        )
        .eq('club_id', _clubId)
        .order('requested_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<ClubExportBundle> loadBundle({
    required String exportId,
    required Set<ClubExportSection> sections,
    required bool includeSensitive,
    required bool includeFiles,
  }) async {
    _ensureProduction();
    if (!ClubExportPolicy.canExport(AppSession.instance)) {
      throw const ClubExportFailure(
        'permission_denied',
        'Sem permissão para exportação integral.',
      );
    }
    if (includeSensitive &&
        !ClubExportPolicy.canIncludeSensitive(AppSession.instance)) {
      throw const ClubExportFailure(
        'sensitive_permission_denied',
        'Sem permissão para incluir dados altamente sensíveis.',
      );
    }

    final clubResponse = await _client
        .from('clubs')
        .select('id,name,legal_name,currency,timezone')
        .eq('id', _clubId)
        .maybeSingle();
    final club = clubResponse == null
        ? <String, dynamic>{'id': _clubId, 'name': 'BLUE ON BLACK'}
        : Map<String, dynamic>.from(clubResponse);

    final datasets = <ClubExportDataset>[];
    final filesByKey = <String, ClubExportFileRef>{};
    for (final spec in _allExportSpecs) {
      if (!sections.contains(spec.section)) continue;
      if (spec.sensitive && !includeSensitive) continue;

      final rows = await _rows(spec, exportId);
      datasets.add(
        ClubExportDataset(
          path: spec.path,
          columns: spec.exportColumns,
          rows: rows,
          sensitive: spec.sensitive,
        ),
      );

      if (includeFiles && spec.fileBucket != null && spec.filePathColumn != null) {
        for (final row in rows) {
          _addFile(filesByKey, spec, row);
        }
      }
    }

    return ClubExportBundle(
      club: club,
      datasets: datasets,
      files: filesByKey.values.toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _rows(
    _DatasetSpec spec,
    String exportId,
  ) async {
    final result = <Map<String, dynamic>>[];
    const pageSize = 1000;
    var offset = 0;

    while (true) {
      final response = await _client.rpc(
        'club_export_dataset_v1',
        params: {
          'target_club': _clubId,
          'p_export': exportId,
          'p_dataset': spec.path,
          'p_offset': offset,
          'p_limit': pageSize,
        },
      );
      final page = List<Map<String, dynamic>>.from(response as List);
      result.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return result;
  }

  void _addFile(
    Map<String, ClubExportFileRef> filesByKey,
    _DatasetSpec spec,
    Map<String, dynamic> row,
  ) {
    final storagePath = row[spec.filePathColumn]?.toString().trim() ?? '';
    if (storagePath.isEmpty) return;
    final original = spec.fileNameColumn == null
        ? null
        : row[spec.fileNameColumn]?.toString().trim();
    final fallback = storagePath.split('/').last;
    final archiveName = safeArchiveName(
      original == null || original.isEmpty ? fallback : original,
    );
    final entityId = safeArchiveName(row['id']?.toString() ?? 'registo');
    final key = '${spec.fileBucket}:$storagePath';
    filesByKey.putIfAbsent(
      key,
      () => ClubExportFileRef(
        bucket: spec.fileBucket!,
        storagePath: storagePath,
        archivePath: '${spec.fileArchiveFolder}/'
            '${entityId}_$archiveName',
        knownSize: _intOrNull(
          spec.fileSizeColumn == null ? null : row[spec.fileSizeColumn],
        ),
      ),
    );
  }

  int? _intOrNull(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  void _ensureProduction() {
    if (AppConfig.demoMode) {
      throw const ClubExportFailure(
        'demo_not_supported',
        'A exportação integral não está disponível no modo de demonstração.',
      );
    }
  }
}

class _DatasetSpec {
  const _DatasetSpec({
    required this.section,
    required this.path,
    required this.table,
    required this.queryColumns,
    required this.exportColumns,
    this.collectIds = true,
    this.directClubId = false,
    this.parentSource,
    this.parentColumn,
    this.orderBy,
    this.sensitive = false,
    this.sensitiveFilter,
    this.fileBucket,
    this.filePathColumn,
    this.fileNameColumn,
    this.fileSizeColumn,
    this.fileArchiveFolder = 'ficheiros',
  });

  final ClubExportSection section;
  final String path;
  final String table;
  final String queryColumns;
  final List<String> exportColumns;
  final bool collectIds;
  final bool directClubId;
  final String? parentSource;
  final String? parentColumn;
  final String? orderBy;
  final bool sensitive;
  final bool? sensitiveFilter;
  final String? fileBucket;
  final String? filePathColumn;
  final String? fileNameColumn;
  final String? fileSizeColumn;
  final String fileArchiveFolder;

  String get sourceKey => table;
}

List<_DatasetSpec> get _allExportSpecs => [
      ..._memberFinanceSpecs,
      ..._operationSpecs,
      ..._supportSpecs,
    ];
