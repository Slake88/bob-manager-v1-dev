import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import 'financial_documents_repository.dart';

class BarSalesRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool get canManage => AppSession.instance.can(AppPermission.manageBar);
  bool get canSelectAccount =>
      AppSession.instance.can(AppPermission.selectBarFinancialAccount);

  void _requireView() {
    if (!AppSession.instance.can(AppPermission.viewBar)) {
      throw StateError('Sem permissão para ver o Bar.');
    }
  }

  void _requireManage() {
    if (!canManage) {
      throw StateError('Sem permissão para registar vendas no Bar.');
    }
  }

  Future<List<Map<String, dynamic>>> products() async {
    _requireView();
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('products')
        .select(
          'id,name,category,consumption_unit,current_stock,sale_price,minimum_stock,active',
        )
        .eq('club_id', _clubId)
        .eq('inventory_area', 'bar')
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> presets() async {
    _requireView();
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('bar_sale_presets')
        .select('id,name,unit_price,active,sort_order')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('sort_order')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updatePresetPrice({
    required String presetId,
    required double price,
  }) async {
    _requireManage();
    if (price < 0) throw ArgumentError('O preço não pode ser negativo.');
    if (AppConfig.demoMode) return;
    await _client
        .from('bar_sale_presets')
        .update({
          'unit_price': price,
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('club_id', _clubId)
        .eq('id', presetId);
  }

  Future<List<Map<String, dynamic>>> events() async {
    _requireView();
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('events')
        .select('id,name,starts_at,status')
        .eq('club_id', _clubId)
        .order('starts_at', ascending: false)
        .limit(40);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> treasuryAccounts() async {
    if (!canSelectAccount || AppConfig.demoMode) return const [];
    final response = await _client
        .from('treasury_accounts')
        .select('id,name,account_type')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> recentSales({int limit = 40}) async {
    _requireView();
    if (AppConfig.demoMode) return const [];
    final response = await _client
        .from('bar_sales')
        .select(
          'id,source_mode,status,customer_label,payment_method,total_amount,notes,created_at,completed_at,event_id,events(name),'
          'bar_sale_items(id,item_kind,description,quantity,unit_price,line_total),'
          'bar_sale_attachments(id,original_file_name,mime_type,file_size,ocr_status,ocr_confidence)',
        )
        .eq('club_id', _clubId)
        .eq('status', 'completed')
        .order('completed_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> createDraft({
    String sourceMode = 'manual',
    String? customerLabel,
    String? eventId,
    String? notes,
  }) async {
    _requireManage();
    if (AppConfig.demoMode) {
      throw StateError('As vendas reais não estão disponíveis em Demo.');
    }
    final response = await _client.rpc(
      'create_bar_sale_v1',
      params: {
        'target_club': _clubId,
        'p_customer_label': _emptyToNull(customerLabel),
        'p_source_mode': sourceMode,
        'p_event': eventId,
        'p_notes': _emptyToNull(notes),
      },
    );
    return response.toString();
  }

  Future<void> cancelDraft(String saleId) async {
    _requireManage();
    if (AppConfig.demoMode) return;
    await _client
        .from('bar_sales')
        .update({
          'status': 'cancelled',
          'updated_by': _client.auth.currentUser?.id,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('club_id', _clubId)
        .eq('id', saleId)
        .eq('status', 'draft');
  }

  Future<List<Map<String, dynamic>>> uploadConsumptionCards({
    required String saleId,
    required List<PlatformFile> files,
    required bool runOcr,
  }) async {
    _requireManage();
    if (AppConfig.demoMode) {
      throw StateError('Os anexos do Bar não estão disponíveis em Demo.');
    }
    if (files.isEmpty) return const [];

    final uploaded = <Map<String, dynamic>>[];
    for (final file in files) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Não foi possível ler ${file.name}. Seleciona novamente a fotografia.',
        );
      }
      if (bytes.length > FinancialDocumentsRepository.maxFileBytes) {
        throw StateError('${file.name} ultrapassa o limite de 20 MB.');
      }
      final mime = FinancialDocumentsRepository.mimeTypeForExtension(
        file.extension,
      );
      if (mime == null || !mime.startsWith('image/')) {
        throw StateError(
          '${file.name}: usa uma fotografia JPG, PNG ou WEBP para o cartão de consumo.',
        );
      }

      final safeName = _safeFileName(file.name);
      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final path = '$_clubId/bar-sales/$saleId/${timestamp}_$safeName';

      await _client.storage
          .from(FinancialDocumentsRepository.bucketName)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );

      try {
        final row = Map<String, dynamic>.from(
          await _client
              .from('bar_sale_attachments')
              .insert({
                'club_id': _clubId,
                'sale_id': saleId,
                'storage_path': path,
                'original_file_name': file.name,
                'mime_type': mime,
                'file_size': bytes.length,
                'attachment_kind': 'consumption_card',
                'ocr_status': runOcr ? 'pending' : 'skipped',
                'created_by': _client.auth.currentUser?.id,
              })
              .select()
              .single(),
        );

        if (runOcr) {
          await _runOcr(row['id'].toString());
          final refreshed = Map<String, dynamic>.from(
            await _client
                .from('bar_sale_attachments')
                .select()
                .eq('club_id', _clubId)
                .eq('id', row['id'])
                .single(),
          );
          uploaded.add(refreshed);
        } else {
          uploaded.add(row);
        }
      } catch (_) {
        await _client.storage
            .from(FinancialDocumentsRepository.bucketName)
            .remove([path]);
        rethrow;
      }
    }
    return uploaded;
  }

  Future<void> _runOcr(String attachmentId) async {
    final response = await _client.functions.invoke(
      'bar-sale-ocr',
      body: {'attachment_id': attachmentId},
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      throw StateError(data['error'].toString());
    }
  }

  Future<Map<String, dynamic>> completeSale({
    required String saleId,
    required List<Map<String, dynamic>> lines,
    required String paymentMethod,
    String? accountId,
    String? customerLabel,
    String? eventId,
    String? notes,
  }) async {
    _requireManage();
    if (lines.isEmpty) throw ArgumentError('Adiciona artigos à venda.');
    if (AppConfig.demoMode) {
      throw StateError('As vendas reais não estão disponíveis em Demo.');
    }
    if (accountId != null && !canSelectAccount) {
      throw StateError('Sem permissão para escolher a conta financeira.');
    }
    final response = await _client.rpc(
      'complete_bar_sale_v1',
      params: {
        'target_club': _clubId,
        'p_sale': saleId,
        'p_lines': lines,
        'p_payment_method': paymentMethod,
        'p_account': accountId,
        'p_customer_label': _emptyToNull(customerLabel),
        'p_event': eventId,
        'p_notes': _emptyToNull(notes),
      },
    );
    if (response is Map) return Map<String, dynamic>.from(response);
    throw StateError('Resposta inválida ao concluir a venda.');
  }

  static List<Map<String, dynamic>> suggestions(
    Map<String, dynamic> attachment,
  ) {
    final raw = attachment['ocr_suggestions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}

String? _emptyToNull(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}

String _safeFileName(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return normalized.isEmpty ? 'cartao.jpg' : normalized;
}
