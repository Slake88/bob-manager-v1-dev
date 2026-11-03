import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/importing.dart';

class ImportRepository {
  ImportRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  Future<String> begin({
    required ImportDefinition definition,
    required ParsedImportFile file,
    required Map<String, String?> mapping,
  }) async {
    _ensureAvailable(definition);
    final response = await _client.rpc(
      'begin_import_v1',
      params: {
        'target_club': _clubId,
        'p_target': definition.key,
        'p_source_filename': file.filename,
        'p_source_format': file.format,
        'p_mapping': mapping,
      },
    );
    return response.toString();
  }

  Future<Map<String, dynamic>> stage({
    required String importId,
    required ImportDefinition definition,
    required ParsedImportFile file,
    required Map<String, String?> mapping,
  }) async {
    _ensureAvailable(definition);

    final rows = <Map<String, dynamic>>[];
    for (var index = 0; index < file.rows.length; index++) {
      final source = file.rows[index];
      rows.add({
        'row_number': index + 2,
        'source_data': source,
        'mapped_data': definition.mapSourceRow(source, mapping),
      });
    }

    final response = await _client.rpc(
      'stage_import_rows_v1',
      params: {
        'target_club': _clubId,
        'p_import': importId,
        'p_rows': rows,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<ImportRowPreview>> rows(String importId) async {
    final response = await _client
        .from('import_rows')
        .select('id,row_number,mapped_data,validation_errors')
        .eq('import_id', importId)
        .order('row_number');
    return List<Map<String, dynamic>>.from(response)
        .map(ImportRowPreview.fromMap)
        .toList();
  }

  Future<Map<String, dynamic>> updateRow({
    required String importId,
    required String rowId,
    required Map<String, dynamic> mappedData,
  }) async {
    final response = await _client.rpc(
      'update_import_row_v1',
      params: {
        'target_club': _clubId,
        'p_import': importId,
        'p_row': rowId,
        'p_mapped_data': mappedData,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> apply(String importId) async {
    final response = await _client.rpc(
      'apply_import_v1',
      params: {
        'target_club': _clubId,
        'p_import': importId,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> rollback(String importId) async {
    final response = await _client.rpc(
      'rollback_import_v1',
      params: {
        'target_club': _clubId,
        'p_import': importId,
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<List<ImportHistoryEntry>> history({int limit = 30}) async {
    final response = await _client
        .from('imports')
        .select(
          'id,target,source_filename,status,total_rows,valid_rows,invalid_rows,'
          'applied_rows,created_at',
        )
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response)
        .map(ImportHistoryEntry.fromMap)
        .toList();
  }

  void _ensureAvailable(ImportDefinition definition) {
    if (AppConfig.demoMode) {
      throw const ImportRepositoryException(
        'A importação não está disponível no modo de demonstração.',
      );
    }

    final session = AppSession.instance;
    final visible = ImportCatalog.visible(session);
    if (!visible.any((item) => item.key == definition.key)) {
      throw const ImportRepositoryException(
        'Sem permissão para este destino de importação.',
      );
    }
  }
}

class ImportRepositoryException implements Exception {
  const ImportRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
