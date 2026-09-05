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
}
