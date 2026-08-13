import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/fees_economics.dart';
import '../core/permissions.dart';
import 'fees_repository.dart';

class FeesOperationalRepository {
  FeesOperationalRepository({SupabaseClient? client}) : _client = client;

  static const String proofBucket = 'fee-payment-proofs';

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  FeesRepository get _fees => FeesRepository(client: _client);

  bool get isDemo => AppConfig.demoMode;
  bool get canManage => AppSession.instance.can(AppPermission.manageFees);

  Future<List<Map<String, dynamic>>> listMembers() => _fees.listMembers();

  Future<List<Map<String, dynamic>>> listObligations({
    String? memberId,
    int? year,
  }) async {
    final rows = await _fees.listObligations(year: year);
    final filtered = memberId == null
        ? rows
        : rows.where((row) => row['member_id']?.toString() == memberId).toList();
    return filtered.map((row) {
      return <String, dynamic>{
        ...row,
        'total_due': feeObligationTotal(row),
        'outstanding': feeObligationOutstanding(row),
        'overdue': feeObligationOverdue(row),
      };
    }).toList();
  }

  Future<FeeAllocationPreview> previewPayment({
    required String memberId,
    required double amount,
  }) async {
    if (amount <= 0) throw ArgumentError('Indica um valor superior a zero.');
    if (isDemo) {
      final rows = await listObligations(memberId: memberId);
      return previewFeeAllocation(rows, amount);
    }
    final response = await _supabase.rpc(
      'preview_fee_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_member': memberId,
        'p_amount': amount,
      },
    );
    return FeeAllocationPreview.fromMap(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<String> registerPayment({
    required String memberId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String notes = '',
    List<Map<String, dynamic>>? allocations,
  }) async {
    _requireManage();
    _ensureRealWrite();
    final response = await _supabase.rpc(
      'register_fee_payment_batch_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_member': memberId,
        'p_amount': amount,
        'p_payment_method': paymentMethod.trim(),
        'p_payment_date': _dateOnly(paymentDate),
        'p_notes': _nullable(notes),
        'p_allocations': allocations,
        'p_reported_payment': null,
      },
    );
    return response.toString();
  }

  Future<List<Map<String, dynamic>>> listPayments({String? memberId}) async {
    if (isDemo) return const [];
    var query = _supabase
        .from('fee_payments')
        .select()
        .eq('club_id', AppSession.instance.clubId);
    if (memberId != null) query = query.eq('member_id', memberId);
    final response = await query.order('payment_date', ascending: false).limit(200);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAllocations(String paymentId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('fee_payment_allocations')
        .select('*, obligation:fee_obligations(reference_year,reference_month,obligation_type,due_date)')
        .eq('club_id', AppSession.instance.clubId)
        .eq('payment_id', paymentId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<double> creditBalance(String memberId) async {
    if (isDemo) return 0;
    final response = await _supabase.rpc(
      'fee_credit_balance_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_member': memberId,
      },
    );
    return feeNumber(response);
  }

  Future<List<Map<String, dynamic>>> listCredits(String memberId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('fee_credits')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> applyCredit({
    required String memberId,
    required String obligationId,
    required double amount,
    String reason = '',
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('apply_fee_credit_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_member': memberId,
      'p_obligation': obligationId,
      'p_amount': amount,
      'p_reason': _nullable(reason),
    });
  }

  Future<void> addCreditAdjustment({
    required String memberId,
    required double amount,
    required String reason,
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('add_fee_credit_adjustment_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_member': memberId,
      'p_amount': amount,
      'p_reason': reason.trim(),
    });
  }

  Future<void> reversePayment({
    required String paymentId,
    required String reason,
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('reverse_fee_payment_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_payment': paymentId,
      'p_reason': reason.trim(),
    });
  }

  Future<void> applyExemption({
    required String obligationId,
    required double amount,
    required String reason,
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('apply_fee_exemption_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_obligation': obligationId,
      'p_amount': amount,
      'p_reason': reason.trim(),
    });
  }

  Future<void> applyAdjustment({
    required String obligationId,
    required double amount,
    required String reason,
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('apply_fee_adjustment_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_obligation': obligationId,
      'p_amount': amount,
      'p_reason': reason.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> listExemptions(String memberId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('fee_exemptions')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listAdjustments(String memberId) async {
    if (isDemo) return const [];
    final response = await _supabase
        .from('fee_adjustments')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('member_id', memberId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> listReportedPayments() async {
    if (isDemo) return const [];
    final rows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('reported_payments')
          .select()
          .eq('club_id', AppSession.instance.clubId)
          .order('created_at', ascending: false)
          .limit(200),
    );
    final members = await listMembers();
    final names = <String, String>{
      for (final member in members)
        if (member['id'] != null)
          member['id'].toString(): member['full_name']?.toString() ?? 'Membro',
    };
    return rows.map((row) => <String, dynamic>{
      ...row,
      'member_name': names[row['member_id']?.toString()] ?? 'Membro',
    }).toList();
  }

  Future<String> submitReportedPayment({
    required double amount,
    required DateTime paidOn,
    required String paymentMethod,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String notes = '',
  }) async {
    _ensureRealWrite();
    if (bytes.isEmpty) throw ArgumentError('O comprovativo está vazio.');
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('Sessão inválida.');
    final safeName = _safeFileName(fileName);
    final path = '${AppSession.instance.clubId}/$userId/'
        '${DateTime.now().microsecondsSinceEpoch}_$safeName';
    await _supabase.storage.from(proofBucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: false),
    );
    try {
      final response = await _supabase.rpc(
        'create_reported_fee_payment_v1',
        params: {
          'target_club': AppSession.instance.clubId,
          'p_amount': amount,
          'p_paid_on': _dateOnly(paidOn),
          'p_payment_method': paymentMethod.trim(),
          'p_notes': _nullable(notes),
          'p_proof_path': path,
          'p_proof_name': fileName,
          'p_proof_mime_type': mimeType,
          'p_proof_size': bytes.length,
        },
      );
      return response.toString();
    } catch (_) {
      await _supabase.storage.from(proofBucket).remove([path]);
      rethrow;
    }
  }

  Future<String> proofSignedUrl(String path) async {
    if (isDemo) throw StateError('Indisponível em Demo.');
    return _supabase.storage.from(proofBucket).createSignedUrl(path, 300);
  }

  Future<void> reviewReportedPayment({
    required String reportId,
    required bool approve,
    String notes = '',
  }) async {
    _requireManage();
    _ensureRealWrite();
    await _supabase.rpc('review_reported_fee_payment_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_report': reportId,
      'p_action': approve ? 'approve' : 'reject',
      'p_notes': _nullable(notes),
    });
  }

  Future<void> cancelReportedPayment(String reportId) async {
    _ensureRealWrite();
    await _supabase.rpc('cancel_reported_fee_payment_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_report': reportId,
    });
  }

  Future<Map<String, dynamic>> settings() => _fees.settings();

  Future<void> updateSettings({
    required int dueDay,
    required double monthlyAmount,
    required double registrationAmount,
  }) => _fees.updateSettings(
    dueDay: dueDay,
    monthlyAmount: monthlyAmount,
    registrationAmount: registrationAmount,
  );

  void _requireManage() {
    if (!canManage) throw StateError('Sem permissão para gerir quotas.');
  }

  void _ensureRealWrite() {
    if (isDemo) throw StateError('Operação indisponível no modo Demo.');
  }

  String? _nullable(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _safeFileName(String value) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return normalized.isEmpty ? 'comprovativo' : normalized;
  }

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
