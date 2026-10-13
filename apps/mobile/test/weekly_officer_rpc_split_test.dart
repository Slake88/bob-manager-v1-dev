import 'dart:convert';
import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/agenda_repository.dart';
import 'package:bob_manager_mobile/repositories/weekly_officer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Run with dummy SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY defines.
// Every HTTP request is handled in memory; none reach a server.
void main() {
  const club = '00000000-0000-0000-0000-000000000001';
  late List<({String rpc, Map<String, dynamic> params})> calls;
  late SupabaseClient client;
  var manage = false;
  setUp(() {
    calls = [];
    manage = false;
    AppSession.instance.clear();
    AppSession.instance.clubId = club;
    client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      final rpc = request.url.pathSegments.last;
      calls.add((
        rpc: rpc,
        params: Map<String, dynamic>.from(jsonDecode(request.body) as Map)
      ));
      final dynamic result = switch (rpc) {
        'can_manage_weekly_officer_v1' => manage,
        'rebuild_weekly_officer_schedule_v1' => {
            'eligible': 52,
            'assigned': 52
          },
        _ => 0,
      };
      return http.Response(jsonEncode(result), 200,
          request: request,
          headers: {'content-type': 'application/json'});
    }));
  });
  tearDown(() async {
    await client.dispose();
  });
  test('ensureYear calls only calendar RPC with the existing contract',
      () async {
    await WeeklyOfficerRepository(client: client).ensureYear(2027);
    expect(calls.single.rpc, 'ensure_weekly_officer_schedule_v1');
    expect(calls.single.params, {'target_club': club, 'p_year': 2027});
  }, skip: AppConfig.demoMode);
  test('Agenda grid crossing year boundary only ensures both calendars',
      () async {
    await AgendaRepository(client: client)
        .ensureDinnerYears(DateTime(2026, 12, 28), DateTime(2027, 1, 8));
    expect(calls.map((c) => c.rpc), [
      'ensure_weekly_officer_schedule_v1',
      'ensure_weekly_officer_schedule_v1'
    ]);
    expect(calls.map((c) => c.params['p_year']), [2026, 2027]);
  }, skip: AppConfig.demoMode);
  test('server capability takes precedence over local superadmin label',
      () async {
    AppSession.instance.superAdmin = true;
    final repo = WeeklyOfficerRepository(client: client);
    expect(await repo.canManageSchedule(), false);
    manage = true;
    expect(await repo.canManageSchedule(), true);
  }, skip: AppConfig.demoMode);
  test('explicit rebuild uses separate RPC and parses result', () async {
    final result =
        await WeeklyOfficerRepository(client: client).rebuildYear(2027);
    expect(calls.single.rpc, 'rebuild_weekly_officer_schedule_v1');
    expect(calls.single.params, {'target_club': club, 'p_year': 2027});
    expect(result['assigned'], 52);
  }, skip: AppConfig.demoMode);
}
