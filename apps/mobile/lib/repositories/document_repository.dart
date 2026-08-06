import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class DocumentRepository {
  DocumentRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  static const String bucketName = 'club-documents';

  final DataService _dataService;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> listDocuments() async {
    _require(AppPermission.viewDocuments);

    final List<Map<String, dynamic>> rows;
    if (AppConfig.demoMode) {
      rows = await _dataService.list('documents');
    } else {
      final response = await _client
          .from('documents')
          .select()
          .eq('club_id', AppSession.instance.clubId)
          .order('document_date', ascending: false)
          .order('created_at', ascending: false);
      rows = List<Map<String, dynamic>>.from(response);
    }

    return rows.where((row) {
      if (row['sensitive'] != true) return true;
      return PermissionPolicy.allows(
        _role,
        AppPermission.viewSensitiveDocuments,
      );
    }).map(Map<String, dynamic>.from).toList();
  }

  Future<Map<String, dynamic>> saveDocument(
    Map<String, dynamic> values, {
    String? documentId,
  }) async {
    _require(AppPermission.manageDocuments);

    if (AppConfig.demoMode) {
      final payload = Map<String, dynamic>.from(values)
        ..['updated_at'] = DateTime.now().toIso8601String();
      if (documentId == null) {
        payload['created_by'] = AppSession.instance.profileId;
        return _dataService.insert('documents', payload);
      }
      return _dataService.update('documents', documentId, payload);
    }

    final payload = _databasePayload(values)
      ..['club_id'] = AppSession.instance.clubId
      ..['updated_at'] = DateTime.now().toIso8601String();

    if (documentId == null) {
      payload['created_by'] = _client.auth.currentUser?.id;
      final response =
          await _client.from('documents').insert(payload).select().single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _client
        .from('documents')
        .update(payload)
        .eq('id', documentId)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> uploadDocument({
    required Map<String, dynamic> values,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    _require(AppPermission.manageDocuments);
    if (bytes.isEmpty) throw ArgumentError('O ficheiro está vazio.');

    if (AppConfig.demoMode) {
      return saveDocument({
        ...values,
        'storage_path': 'demo/$fileName',
        'original_file_name': fileName,
        'mime_type': mimeType,
        'file_size': bytes.length,
      });
    }

    final safeName = _safeFileName(fileName);
    final path = '${AppSession.instance.clubId}/'
        '${DateTime.now().microsecondsSinceEpoch}_$safeName';

    await _client.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: mimeType,
            upsert: false,
          ),
        );

    try {
      return await saveDocument({
        ...values,
        'storage_path': path,
        'original_file_name': fileName,
        'mime_type': mimeType,
        'file_size': bytes.length,
      });
    } catch (_) {
      await _client.storage.from(bucketName).remove([path]);
      rethrow;
    }
  }

  Future<String> signedUrl(Map<String, dynamic> document) async {
    _require(AppPermission.viewDocuments);
    final path = document['storage_path']?.toString();
    if (path == null || path.isEmpty) {
      throw StateError('Este registo não tem ficheiro associado.');
    }
    if (AppConfig.demoMode) {
      throw StateError('A abertura de ficheiros não está disponível em Demo.');
    }
    return _client.storage.from(bucketName).createSignedUrl(path, 300);
  }

  Future<void> deleteDocument(Map<String, dynamic> document) async {
    _require(AppPermission.manageDocuments);
    final id = document['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Documento sem identificador.');
    }

    if (AppConfig.demoMode) {
      return _dataService.delete('documents', id);
    }

    final path = document['storage_path']?.toString();
    await _client
        .from('documents')
        .delete()
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId);
    if (path != null && path.isNotEmpty) {
      await _client.storage.from(bucketName).remove([path]);
    }
  }

  Map<String, dynamic> _databasePayload(Map<String, dynamic> values) {
    const allowed = <String>{
      'name',
      'category',
      'description',
      'document_date',
      'version',
      'status',
      'expires_at',
      'sensitive',
      'tags',
      'storage_path',
      'original_file_name',
      'mime_type',
      'file_size',
      'linked_entity_type',
      'linked_entity_id',
    };
    return <String, dynamic>{
      for (final entry in values.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }

  String _safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'documento' : normalized;
  }

  static bool isExpired(Map<String, dynamic> document, {DateTime? now}) {
    final value = document['expires_at']?.toString();
    if (value == null || value.isEmpty) return false;
    final expiry = DateTime.tryParse(value);
    if (expiry == null) return false;
    final reference = now ?? DateTime.now();
    return expiry.isBefore(
      DateTime(reference.year, reference.month, reference.day),
    );
  }

  static bool expiresSoon(
    Map<String, dynamic> document, {
    DateTime? now,
    int days = 30,
  }) {
    final value = document['expires_at']?.toString();
    if (value == null || value.isEmpty) return false;
    final expiry = DateTime.tryParse(value);
    if (expiry == null) return false;
    final reference = now ?? DateTime.now();
    final difference = expiry.difference(reference).inDays;
    return difference >= 0 && difference <= days;
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(_role, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
