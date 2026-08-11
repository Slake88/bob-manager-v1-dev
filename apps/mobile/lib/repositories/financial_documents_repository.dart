import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class FinancialDocumentsRepository {
  static const String bucketName = 'financial-documents';
  static const int maxFileBytes = 20 * 1024 * 1024;

  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool get canView =>
      AppSession.instance.can(AppPermission.viewTreasury) ||
      AppSession.instance.can(AppPermission.approveExpenseRequests);

  bool get canManage =>
      AppSession.instance.can(AppPermission.createTreasuryMovement) ||
      AppSession.instance.can(AppPermission.approveExpenseRequests);

  Future<List<Map<String, dynamic>>> listForTransaction(
    String transactionId,
  ) async {
    _requireView();
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];

    final response = await _client
        .from('financial_transaction_documents')
        .select(
          'id,club_id,transaction_id,source_attachment_id,document_type,'
          'origin,storage_path,original_file_name,mime_type,file_size,'
          'is_primary,created_at,created_by,updated_at,updated_by',
        )
        .eq('club_id', _clubId)
        .eq('transaction_id', transactionId)
        .order('is_primary', ascending: false)
        .order('created_at')
        .order('id');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> uploadFiles({
    required String transactionId,
    required String documentType,
    required List<PlatformFile> files,
  }) async {
    _requireManage();
    if (AppConfig.demoMode) {
      throw StateError('O carregamento de documentos não está disponível em Demo.');
    }
    if (!documentTypes.contains(documentType)) {
      throw ArgumentError('Categoria de documento inválida.');
    }
    if (files.isEmpty) return const <Map<String, dynamic>>[];

    final uploaded = <Map<String, dynamic>>[];
    for (final file in files) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Não foi possível ler ${file.name}. Seleciona novamente o ficheiro.',
        );
      }
      if (bytes.length > maxFileBytes) {
        throw StateError('${file.name} ultrapassa o limite de 20 MB.');
      }

      final safeName = _safeFileName(file.name);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final path = '$_clubId/transactions/$transactionId/'
          '${timestamp}_$safeName';
      final mimeType = mimeTypeForExtension(file.extension);

      await _client.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );

      try {
        final id = await _client.rpc(
          'add_financial_transaction_document_v1',
          params: {
            'target_club': _clubId,
            'p_transaction': transactionId,
            'p_document_type': documentType,
            'p_storage_path': path,
            'p_original_file_name': file.name,
            'p_mime_type': mimeType,
            'p_file_size': bytes.length,
          },
        );
        uploaded.add({
          'id': id.toString(),
          'transaction_id': transactionId,
          'document_type': documentType,
          'origin': 'direct',
          'storage_path': path,
          'original_file_name': file.name,
          'mime_type': mimeType,
          'file_size': bytes.length,
        });
      } catch (_) {
        await _client.storage.from(bucketName).remove([path]);
        rethrow;
      }
    }
    return uploaded;
  }

  Future<String> signedUrl(Map<String, dynamic> document) async {
    _requireView();
    final path = document['storage_path']?.toString();
    if (path == null || path.isEmpty) {
      throw StateError('Documento sem ficheiro associado.');
    }
    if (AppConfig.demoMode) {
      throw StateError('A abertura de ficheiros não está disponível em Demo.');
    }
    return _client.storage.from(bucketName).createSignedUrl(path, 300);
  }

  Future<void> setPrimary({
    required String transactionId,
    required String documentId,
  }) async {
    _requireManage();
    if (AppConfig.demoMode) return;

    await _client.rpc(
      'set_primary_financial_transaction_document_v1',
      params: {
        'target_club': _clubId,
        'p_transaction': transactionId,
        'p_document': documentId,
      },
    );
  }

  Future<void> deleteDocument({
    required String transactionId,
    required Map<String, dynamic> document,
  }) async {
    _requireManage();
    if (!isDeletable(document)) {
      throw StateError(
        'Este documento pertence ao processo financeiro original e não pode ser eliminado aqui.',
      );
    }
    if (AppConfig.demoMode) return;

    final response = await _client.rpc(
      'delete_financial_transaction_document_v1',
      params: {
        'target_club': _clubId,
        'p_transaction': transactionId,
        'p_document': document['id'].toString(),
      },
    );
    final path = response?.toString();
    if (path != null && path.isNotEmpty && path != 'null') {
      try {
        await _client.storage.from(bucketName).remove([path]);
      } catch (_) {
        // O registo já foi removido com sucesso. Um objeto órfão privado no
        // Storage pode ser limpo posteriormente sem comprometer a contabilidade.
      }
    }
  }

  static const Set<String> documentTypes = {
    'receipt',
    'payment_proof',
    'invoice_other',
  };

  static String documentTypeLabel(String? value) => switch (value) {
        'receipt' => 'Talão / recibo',
        'payment_proof' => 'Comprovativo de pagamento',
        'invoice_other' => 'Fatura / PDF / outro',
        _ => 'Documento',
      };

  static bool isImage(Map<String, dynamic> document) {
    final mime = document['mime_type']?.toString().toLowerCase() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = document['original_file_name']?.toString().toLowerCase() ?? '';
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  static bool isPdf(Map<String, dynamic> document) {
    final mime = document['mime_type']?.toString().toLowerCase() ?? '';
    if (mime == 'application/pdf') return true;
    final name = document['original_file_name']?.toString().toLowerCase() ?? '';
    return name.endsWith('.pdf');
  }

  static bool isDeletable(Map<String, dynamic> document) =>
      document['source_attachment_id'] == null &&
      document['origin']?.toString() != 'request';

  static String? mimeTypeForExtension(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  String _safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'documento' : normalized;
  }

  void _requireView() {
    if (!canView) {
      throw StateError('Sem permissão para ver documentos financeiros.');
    }
  }

  void _requireManage() {
    if (!canManage) {
      throw StateError('Sem permissão para gerir documentos financeiros.');
    }
  }
}
