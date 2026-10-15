import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import 'financial_documents_repository.dart';

class FinancialOcrRepository {
  static const String bucketName = FinancialDocumentsRepository.bucketName;
  static const int maxFileBytes = FinancialDocumentsRepository.maxFileBytes;

  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool get canRunFinancialOcr =>
      AppSession.instance.can(AppPermission.createTreasuryMovement) ||
      AppSession.instance.can(AppPermission.approveExpenseRequests);

  bool get canRunBarOcr => AppSession.instance.can(AppPermission.manageBar);

  Future<List<Map<String, dynamic>>> jobsForTransaction(
    String transactionId,
  ) async {
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('financial_ocr_jobs')
        .select()
        .eq('club_id', _clubId)
        .eq('transaction_id', transactionId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> job(String jobId) async {
    if (AppConfig.demoMode) {
      throw StateError('OCR não disponível em Demo.');
    }
    final response = await _client
        .from('financial_ocr_jobs')
        .select()
        .eq('club_id', _clubId)
        .eq('id', jobId)
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<String> startForDocument(String documentId) async {
    if (!canRunFinancialOcr) {
      throw StateError('Sem permissão para executar OCR financeiro.');
    }
    if (AppConfig.demoMode) {
      throw StateError('OCR não disponível em Demo.');
    }
    final response = await _client.rpc(
      'start_financial_document_ocr_v1',
      params: {
        'target_club': _clubId,
        'p_document': documentId,
      },
    );
    return response.toString();
  }

  Future<String> createBarJob() async {
    if (!canRunBarOcr) {
      throw StateError('Sem permissão para usar OCR no Bar.');
    }
    if (AppConfig.demoMode) {
      throw StateError('OCR não disponível em Demo.');
    }
    final response = await _client.rpc(
      'create_bar_ocr_job_v1',
      params: {'target_club': _clubId},
    );
    return response.toString();
  }

  Future<Map<String, dynamic>> uploadBarSource({
    required String jobId,
    required PlatformFile file,
  }) async {
    if (!canRunBarOcr) {
      throw StateError('Sem permissão para usar OCR no Bar.');
    }
    final Uint8List? bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Não foi possível ler ${file.name}. Seleciona novamente o ficheiro.',
      );
    }
    if (bytes.length > maxFileBytes) {
      throw StateError('${file.name} ultrapassa o limite de 20 MB.');
    }
    final mimeType =
        FinancialDocumentsRepository.mimeTypeForExtension(file.extension);
    if (!isSupportedMime(mimeType)) {
      throw StateError('Formato não suportado. Usa JPG, PNG, WEBP ou PDF.');
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final safeName = safeFileName(file.name);
    final path = '$_clubId/ocr/$jobId/${timestamp}_$safeName';

    await _client.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );
    try {
      await _client.rpc(
        'attach_bar_ocr_source_v1',
        params: {
          'target_club': _clubId,
          'p_job': jobId,
          'p_storage_path': path,
          'p_original_file_name': file.name,
          'p_mime_type': mimeType,
          'p_file_size': bytes.length,
        },
      );
    } catch (_) {
      await _client.storage.from(bucketName).remove([path]);
      rethrow;
    }
    return job(jobId);
  }

  Future<Map<String, dynamic>> runOcr(String jobId) async {
    if (AppConfig.demoMode) {
      throw StateError('OCR não disponível em Demo.');
    }
    try {
      await _client.functions.invoke(
        'financial-ocr',
        body: {'job_id': jobId},
      );
    } catch (_) {
      final latest = await job(jobId);
      final status = latest['status']?.toString();
      if (status == 'unconfigured' || status == 'failed') return latest;
      rethrow;
    }
    return job(jobId);
  }

  Future<Map<String, dynamic>> retry(String jobId) async {
    if (AppConfig.demoMode) {
      throw StateError('OCR não disponível em Demo.');
    }
    await _client.rpc(
      'retry_financial_ocr_job_v1',
      params: {'target_club': _clubId, 'p_job': jobId},
    );
    return runOcr(jobId);
  }

  Future<void> saveReview({
    required Map<String, dynamic> job,
    required String supplierName,
    required String supplierTaxId,
    required String documentNumber,
    required DateTime? documentDate,
    required String currency,
    required double? subtotal,
    required double? taxTotal,
    required double? total,
    required String paymentMethod,
    required List<Map<String, dynamic>> lineItems,
    required List<String> warnings,
  }) async {
    if (AppConfig.demoMode) return;
    await _client.rpc(
      'save_financial_ocr_review_v1',
      params: {
        'target_club': _clubId,
        'p_job': job['id'].toString(),
        'p_supplier_name': supplierName.trim(),
        'p_supplier_tax_id': supplierTaxId.trim(),
        'p_document_number': documentNumber.trim(),
        'p_document_date': documentDate?.toIso8601String().split('T').first,
        'p_currency': currency.trim(),
        'p_subtotal': subtotal,
        'p_tax_total': taxTotal,
        'p_total': total,
        'p_payment_method': paymentMethod.trim(),
        'p_confidence': number(job['confidence']),
        'p_line_items': lineItems,
        'p_warnings': warnings,
      },
    );
  }

  Future<Map<String, dynamic>> confirmBarPurchase({
    required String jobId,
    required List<Map<String, dynamic>> lines,
    required String? eventId,
    required String? accountId,
    required String paymentMethod,
    required double total,
    required String notes,
  }) async {
    if (!canRunBarOcr) {
      throw StateError('Sem permissão para confirmar compras OCR no Bar.');
    }
    if (lines.isEmpty) {
      throw ArgumentError('Seleciona pelo menos uma linha para entrada em stock.');
    }
    if (total <= 0) throw ArgumentError('O total deve ser superior a zero.');
    final response = await _client.rpc(
      'confirm_bar_ocr_purchase_v1',
      params: {
        'target_club': _clubId,
        'p_job': jobId,
        'p_lines': lines,
        'p_event': eventId,
        'p_account': accountId,
        'p_payment_method': paymentMethod,
        'p_total': total,
        'p_notes': notes.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  static bool isSupportedMime(String? mime) => const {
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf',
      }.contains(mime?.toLowerCase());

  static String statusLabel(String? status) => switch (status) {
        'draft' => 'A preparar',
        'pending' => 'A aguardar leitura',
        'processing' => 'A analisar',
        'ready' => 'Pronto para revisão',
        'reviewed' => 'Revisto',
        'unconfigured' => 'OCR por configurar',
        'failed' => 'Falhou',
        'confirmed' => 'Confirmado',
        'cancelled' => 'Cancelado',
        _ => 'OCR',
      };

  static List<Map<String, dynamic>> lineItems(Map<String, dynamic> job) {
    final value = job['line_items'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static List<String> warnings(Map<String, dynamic> job) {
    final value = job['warnings'];
    if (value is! List) return const [];
    return value.map((item) => item.toString()).toList();
  }

  static double? number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  }

  static bool hasAmountDiscrepancy(
    Object? transactionAmount,
    Object? detectedAmount, {
    double tolerance = 0.01,
  }) {
    final expected = number(transactionAmount);
    final detected = number(detectedAmount);
    if (expected == null || detected == null) return false;
    return (expected - detected).abs() > tolerance;
  }

  static String? suggestProductId(
    String description,
    List<Map<String, dynamic>> products,
  ) {
    final source = normalize(description);
    if (source.isEmpty) return null;
    String? bestId;
    double bestScore = 0;
    final sourceTokens = _tokens(source);

    for (final product in products) {
      final id = product['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final candidate = normalize(
        '${product['name'] ?? ''} ${product['sku'] ?? ''} ${product['supplier'] ?? ''}',
      );
      if (candidate.isEmpty) continue;
      var score = 0.0;
      final name = normalize(product['name']?.toString() ?? '');
      if (name.isNotEmpty && (source.contains(name) || name.contains(source))) {
        score += 4;
      }
      final candidateTokens = _tokens(candidate);
      if (sourceTokens.isNotEmpty) {
        final shared = sourceTokens.where(candidateTokens.contains).length;
        score += shared / sourceTokens.length * 3;
      }
      if (score > bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestScore >= 1.2 ? bestId : null;
  }

  static String normalize(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c',
    };
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    return result
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static Set<String> _tokens(String value) => value
      .split(' ')
      .where((token) => token.length >= 3)
      .toSet();

  static String safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'documento' : normalized;
  }
}
