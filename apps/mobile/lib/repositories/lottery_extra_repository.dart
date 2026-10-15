import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class LotteryExtraRepository {
  LotteryExtraRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<void> registerManualPrize({
    required String resultId,
    required String playerId,
    required double amount,
    required String paymentMethod,
    int category = 13,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('O valor do prémio deve ser superior a zero.');
    }
    if (category < 1 || category > 13) {
      throw ArgumentError('A categoria deve estar entre 1 e 13.');
    }
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'register_euromillions_manual_prize_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_result': resultId,
        'p_player': playerId,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_category': category,
      },
    );
  }

  Future<void> reversePrizeReceipt({
    required String prizeId,
    required String reason,
  }) async {
    final cleanReason = _validatedReason(reason);
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'reverse_euromillions_prize_receipt_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_prize': prizeId,
        'p_reason': cleanReason,
      },
    );
  }

  Future<void> payMonthFines({
    required String playerId,
    required int year,
    required int month,
    required String paymentMethod,
  }) async {
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'register_euromillions_month_fine_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_player': playerId,
        'p_year': year,
        'p_month': month,
        'p_payment_method': paymentMethod,
      },
    );
  }

  Future<void> reverseDrawPayment({
    required String chargeId,
    required String reason,
  }) async {
    final cleanReason = _validatedReason(reason);
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'reverse_euromillions_draw_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_charge': chargeId,
        'p_reason': cleanReason,
      },
    );
  }

  Future<void> reverseMonthPayments({
    required String playerId,
    required int year,
    required int month,
    required String reason,
  }) async {
    final cleanReason = _validatedReason(reason);
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'reverse_euromillions_month_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_player': playerId,
        'p_year': year,
        'p_month': month,
        'p_reason': cleanReason,
      },
    );
  }

  Future<void> reverseFinePayment({
    required String transactionId,
    required String reason,
  }) async {
    final cleanReason = _validatedReason(reason);
    if (AppConfig.demoMode) return;

    await _supabase.rpc(
      'reverse_euromillions_fine_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_transaction': transactionId,
        'p_reason': cleanReason,
      },
    );
  }

  String _validatedReason(String reason) {
    final cleanReason = reason.trim();
    if (cleanReason.length < 3) {
      throw ArgumentError('Indica o motivo da reversão.');
    }
    return cleanReason;
  }
}
