import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class LotteryRankingRepository {
  LotteryRankingRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> loadAllTime() async {
    if (AppConfig.demoMode) return const [];

    final clubId = AppSession.instance.clubId;
    final results = await Future.wait([
      _supabase
          .from('euromillions_players')
          .select('id,status,member:members!inner(id,full_name,nickname)')
          .eq('club_id', clubId),
      _supabase
          .from('euromillions_fines')
          .select('player_id,result_id,missed_numbers,missed_stars,fine_amount')
          .eq('club_id', clubId),
      _supabase
          .from('euromillions_prizes')
          .select('player_id,result_id,prize_amount')
          .eq('club_id', clubId),
    ]);

    final players = List<Map<String, dynamic>>.from(results[0] as List);
    final fines = List<Map<String, dynamic>>.from(results[1] as List);
    final prizes = List<Map<String, dynamic>>.from(results[2] as List);

    final byPlayer = <String, Map<String, dynamic>>{};
    for (final player in players) {
      final id = player['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final member = player['member'];
      byPlayer[id] = <String, dynamic>{
        'player_id': id,
        'name': member is Map ? member['full_name'] : null,
        'nickname': member is Map ? member['nickname'] : null,
        'status': player['status'],
        'draw_ids': <String>{},
        'misses': 0,
        'fine_total': 0.0,
        'prize_draw_ids': <String>{},
        'prize_total': 0.0,
      };
    }

    for (final fine in fines) {
      final id = fine['player_id']?.toString();
      final row = id == null ? null : byPlayer[id];
      if (row == null) continue;
      final resultId = fine['result_id']?.toString();
      if (resultId != null && resultId.isNotEmpty) {
        (row['draw_ids'] as Set<String>).add(resultId);
      }
      row['misses'] = (row['misses'] as int) +
          _asInt(fine['missed_numbers']) +
          _asInt(fine['missed_stars']);
      row['fine_total'] =
          (row['fine_total'] as double) + _asDouble(fine['fine_amount']);
    }

    for (final prize in prizes) {
      final id = prize['player_id']?.toString();
      final row = id == null ? null : byPlayer[id];
      if (row == null) continue;
      final resultId = prize['result_id']?.toString();
      if (resultId != null && resultId.isNotEmpty) {
        (row['prize_draw_ids'] as Set<String>).add(resultId);
      }
      row['prize_total'] =
          (row['prize_total'] as double) + _asDouble(prize['prize_amount']);
    }

    final ranking = <Map<String, dynamic>>[];
    for (final row in byPlayer.values) {
      final draws = (row['draw_ids'] as Set<String>).length;
      final prizeDraws = (row['prize_draw_ids'] as Set<String>).length;
      if (draws == 0 && prizeDraws == 0) continue;
      final misses = row['misses'] as int;
      ranking.add({
        'player_id': row['player_id'],
        'name': row['name'],
        'nickname': row['nickname'],
        'status': row['status'],
        'draws': draws,
        'misses': misses,
        'average_misses': draws == 0 ? 0.0 : misses / draws,
        'fine_total': row['fine_total'],
        'prize_draws': prizeDraws,
        'prize_total': row['prize_total'],
      });
    }

    ranking.sort(
      (a, b) => (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? ''),
    );
    return ranking;
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
