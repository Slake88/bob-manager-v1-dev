import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class FinancialRequestsRepository {
  static const bucketName = 'financial-documents';

  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool get canManage =>
      AppSession.instance.can(AppPermission.approveExpenseRequests);

  Future<List<Map<String, dynamic>>> listRequests() async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];

    final response = await _client
        .from('financial_requests')
        .select(
          'id,club_id,member_id,request_type,category,batch_id,amount,'
          'description,due_date,status,review_note,payment_method,'
          'treasury_account_id,treasury_transaction_id,requested_by,'
          'reviewed_by,reviewed_at,submitted_at,paid_at,paid_by,created_at,'
          'updated_at,member:members!financial_requests_member_id_fkey('
          'id,full_name,nickname,status,profile_id),'
          'attachments:financial_request_attachments('
          'id,kind,storage_path,original_file_name,mime_type,file_size,created_at)',
        )
        .eq('club_id', _clubId)
        .order('created_at', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> eligibleMembers() async {
    if (AppConfig.demoMode) return const <Map<String, dynamic>>[];

    final response = await _client
        .from('members')
        .select('id,full_name,nickname,status,profile_id')
        .eq('club_id', _clubId)
        .inFilter('status', const ['active', 'prospect', 'full_color', 'honorary'])
        .order('member_number')
        .order('full_name');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<String?> currentMemberId() async {
    if (AppConfig.demoMode) return null;
    final response = await _client.rpc(
      'current_financial_member_v1',
      params: {'target_club': _clubId},
    );
    final value = response?.toString();
    return value == null || value.isEmpty || value == 'null' ? null : value;
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    if (!canManage || AppConfig.demoMode) {
      return const <Map<String, dynamic>>[];
    }

    final response = await _client
        .from('treasury_accounts')
        .select('id,name,icon,account_type')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> createReimbursementDraft({
    String? memberId,
    required double amount,
    required String description,
  }) async {
    final response = await _client.rpc(
      'create_reimbursement_draft_v1',
      params: {
        'target_club': _clubId,
        'p_member': memberId,
        'p_amount': amount,
        'p_description': description,
      },
    );
    return response.toString();
  }

  Future<void> updateReimbursementDraft({
    required String requestId,
    required double amount,
    required String description,
  }) async {
    await _client.rpc(
      'update_reimbursement_draft_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_amount': amount,
        'p_description': description,
      },
    );
  }

  Future<void> submitReimbursement(String requestId) async {
    await _client.rpc(
      'submit_reimbursement_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
      },
    );
  }

  Future<void> reviewReimbursement({
    required String requestId,
    required String action,
    String? note,
  }) async {
    await _client.rpc(
      'review_reimbursement_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_action': action,
        'p_note': note,
      },
    );
  }

  Future<String> payReimbursement({
    required String requestId,
    required String accountId,
    required String paymentMethod,
    String? note,
  }) async {
    final response = await _client.rpc(
      'pay_reimbursement_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_account': accountId,
        'p_payment_method': paymentMethod,
        'p_note': note,
      },
    );
    return response.toString();
  }

  Future<Map<String, dynamic>> createCharges({
    required List<String> memberIds,
    required String category,
    required double amount,
    required String description,
    DateTime? dueDate,
  }) async {
    final response = await _client.rpc(
      'create_member_charges_v1',
      params: {
        'target_club': _clubId,
        'p_member_ids': memberIds,
        'p_category': category,
        'p_amount': amount,
        'p_description': description,
        'p_due_date': dueDate == null ? null : _dateOnly(dueDate),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> submitChargeProof(String requestId) async {
    await _client.rpc(
      'submit_charge_proof_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
      },
    );
  }

  Future<String?> reviewChargePayment({
    required String requestId,
    required String action,
    String? accountId,
    String? paymentMethod,
    String? note,
  }) async {
    final response = await _client.rpc(
      'review_charge_payment_v1',
      params: {
        'target_club': _clubId,
        'p_request': requestId,
        'p_action': action,
        'p_account': accountId,
        'p_payment_method': paymentMethod,
        'p_note': note,
      },
    );
    final value = response?.toString();
    return value == null || value.isEmpty || value == 'null' ? null : value;
  }

  Future<List<Map<String, dynamic>>> uploadAttachments({
    required String requestId,
    required String kind,
    required List<PlatformFile> files,
  }) async {
    final uploaded = <Map<String, dynamic>>[];

    for (final file in files) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'Não foi possível ler ${file.name}. Seleciona novamente o ficheiro.',
        );
      }
      if (bytes.length > 20 * 1024 * 1024) {
        throw StateError('${file.name} ultrapassa o limite de 20 MB.');
      }

      final safeName = _safeFileName(file.name);
      final path = '$_clubId/$requestId/'
          '${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final mimeType = _mimeType(file.extension);

      await _client.storage.from(bucketName).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );

      try {
        final attachmentId = await _client.rpc(
          'add_financial_attachment_v1',
          params: {
            'target_club': _clubId,
            'p_request': requestId,
            'p_kind': kind,
            'p_storage_path': path,
            'p_original_file_name': file.name,
            'p_mime_type': mimeType,
            'p_file_size': bytes.length,
          },
        );
        uploaded.add({
          'id': attachmentId.toString(),
          'kind': kind,
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

  Future<String> signedAttachmentUrl(Map<String, dynamic> attachment) async {
    final path = attachment['storage_path']?.toString();
    if (path == null || path.isEmpty) {
      throw StateError('O anexo não tem caminho de armazenamento.');
    }
    return _client.storage.from(bucketName).createSignedUrl(path, 300);
  }

  static bool isEligibleMemberStatus(String? status) =>
      const {'active', 'prospect', 'full_color', 'honorary'}.contains(status);

  static bool isTerminalStatus(String? status) =>
      const {'paid', 'rejected', 'cancelled'}.contains(status);

  static String statusLabel(String? status) => switch (status) {
        'draft' => 'Rascunho',
        'pending_review' => 'Aguarda análise',
        'needs_info' => 'Precisa de informação',
        'approved' => 'Aprovado',
        'awaiting_payment' => 'Aguarda pagamento',
        'awaiting_validation' => 'Aguarda validação',
        'rejected' => 'Rejeitado',
        'paid' => 'Liquidado',
        'cancelled' => 'Cancelado',
        _ => status ?? '—',
      };

  static String categoryLabel(String? category) => switch (category) {
        'reimbursement' => 'Reembolso',
        'fee' => 'Quota',
        'euromillions' => 'Euromilhões',
        'bar' => 'Cartão Bar',
        'other' => 'Outro',
        _ => category ?? '—',
      };

  static String paymentMethodLabel(String? method) => switch (method) {
        'cash' => 'Numerário',
        'mbway' => 'MB Way',
        'bank_transfer' => 'Transferência',
        'other' => 'Outro',
        _ => method ?? '—',
      };

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _safeFileName(String value) {
    final safe = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.isEmpty ? 'ficheiro' : safe;
  }

  static String _mimeType(String? extension) => switch (
        extension?.toLowerCase()
      ) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        _ => 'application/octet-stream',
      };
}
