import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/global_search.dart';

class GlobalSearchRepository {
  GlobalSearchRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<GlobalSearchResult>> search(
    String query, {
    int limit = 30,
  }) async {
    final value = query.trim();
    if (value.length < 2) return const [];
    if (AppConfig.demoMode) return const [];

    final response = await _supabase.rpc(
      'global_search_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'search_text': value,
        'result_limit': limit.clamp(1, 50),
      },
    );

    final rows = List<Map<String, dynamic>>.from(response as List);
    return rows.map(GlobalSearchResult.fromMap).toList(growable: false);
  }
}
