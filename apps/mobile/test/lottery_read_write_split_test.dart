import 'dart:convert';
import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/lottery_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Dummy defines only. Every request is intercepted in memory.
void main() {
  const club = '00000000-0000-0000-0000-000000000001';
  late SupabaseClient client;
  late List<http.Request> calls;
  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.clubId = club;
    AppSession.instance.applyPermissions(['viewLottery', 'manageLottery']);
    calls = [];
    client = SupabaseClient('https://example.supabase.co', 'test-key',
      httpClient: MockClient((request) async {
        calls.add(request);
        final table = request.url.pathSegments.last;
        final dynamic data = switch (table) {
          'members' => [
            {'id': 'member-a', 'full_name': 'A'},
            {'id': 'member-b', 'full_name': 'B'},
          ],
          'euromillions_players' => [{
            'id': 'player-a', 'member_id': 'member-a', 'status': 'active',
            'numbers': [1,2,3,4,5], 'stars': [1,2],
            'member': {'id': 'member-a', 'full_name': 'A'},
          }],
          'prepare_euromillions_month_v1' => null,
          _ => [],
        };
        return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'}, request: request);
      }));
  });
  tearDown(() async { await client.dispose(); AppSession.instance.clear(); });
  test('opening, refresh and month navigation use GET only', () async {
    final repo = LotteryRepository(client: client);
    for (final month in [DateTime(2020, 1), DateTime.now(), DateTime(2030, 1)]) {
      final data = await repo.loadMonth(month.year, month.month);
      await repo.loadMonth(month.year, month.month);
      final players = data['players'] as List;
      expect(players.length, 2);
      expect(players.last['status'], 'non_player');
      expect(players.last['player_id'], isNull);
    }
    expect(calls, isNotEmpty);
    expect(calls.every((r) => r.method == 'GET'), isTrue);
    expect(calls.any((r) => r.url.path.contains('/rpc/') ||
        r.url.path.contains('/functions/')), isFalse);
  }, skip: AppConfig.demoMode);
  test('preparation is a separate explicit management RPC', () async {
    final now = DateTime.now();
    await LotteryRepository(client: client).prepareMonth(now.year, now.month);
    expect(calls.single.method, 'POST');
    expect(calls.single.url.pathSegments.last, 'prepare_euromillions_month_v1');
    expect(jsonDecode(calls.single.body), {
      'target_club': club, 'p_year': now.year, 'p_month': now.month,
    });
  }, skip: AppConfig.demoMode);
  test('past preparation, import and processing fail before HTTP', () async {
    final repo = LotteryRepository(client: client);
    AppSession.instance.role = 'treasurer';
    await expectLater(repo.prepareMonth(2020,1), throwsStateError);
    await expectLater(repo.importOfficial(year:2020,month:1), throwsStateError);
    await expectLater(repo.processResult(drawDate:DateTime(2020,1,3),
        numbers:'1,2,3,4,5', stars:'1,2'), throwsStateError);
    expect(calls, isEmpty);
  });
  test('viewLottery cannot prepare, import or configure a player', () async {
    AppSession.instance.applyPermissions(['viewLottery']);
    final repo = LotteryRepository(client: client);
    final now = DateTime.now();
    await expectLater(repo.prepareMonth(now.year,now.month), throwsStateError);
    await expectLater(repo.importOfficial(year:now.year,month:now.month), throwsStateError);
    await expectLater(repo.updatePlayer(memberId:'member-b',status:'active',
        numbers:'1,2,3,4,5',stars:'1,2'), throwsStateError);
    expect(calls, isEmpty);
  });
  test('configuring an absent player upserts only the selected member', () async {
    await LotteryRepository(client: client).updatePlayer(memberId:'member-b',
        status:'active',numbers:'1,2,3,4,5',stars:'1,2');
    expect(calls.length, 1);
    expect(calls.single.url.pathSegments.last, 'euromillions_players');
    expect(calls.single.method, 'POST');
    expect(calls.single.url.queryParameters['on_conflict'], 'club_id,member_id');
    final body = jsonDecode(calls.single.body) as Map;
    expect(body['member_id'], 'member-b');
    expect(body['club_id'], club);
  }, skip: AppConfig.demoMode);
  test('monthly payment remains an explicit payment RPC', () async {
    AppSession.instance.role = 'treasurer';
    await LotteryRepository(client:client).payMonth(playerId:'player-a',
        year:2020,month:1,paymentMethod:'Dinheiro');
    expect(calls.single.url.pathSegments.last, 'register_euromillions_month_payment_v1');
  }, skip: AppConfig.demoMode);
}
