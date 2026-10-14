import 'dart:convert';
import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/events_advanced_repository.dart';
import 'package:bob_manager_mobile/repositories/fees_operational_repository.dart';
import 'package:bob_manager_mobile/repositories/weekly_officer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Dummy configuration and in-memory HTTP only. No Supabase endpoint is contacted.
void main() {
  const club = '00000000-0000-0000-0000-000000000001';
  late SupabaseClient client;
  late List<({String rpc, Map<String, dynamic> params})> calls;
  dynamic result;
  var reject = false;
  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.clubId = club;
    calls = [];
    result = null;
    reject = false;
    client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      calls.add((
        rpc: request.url.pathSegments.last,
        params: Map<String, dynamic>.from(jsonDecode(request.body) as Map)
      ));
      return http.Response(
          jsonEncode(reject
              ? {
                  'code': 'P0001',
                  'message': 'Membership required',
                  'details': null,
                  'hint': null
                }
              : result),
          reject ? 400 : 200,
          request: request,
          headers: {'content-type': 'application/json'});
    }));
  });
  tearDown(() async {
    await client.dispose();
    AppSession.instance.clear();
  });
  test('nullable personal helpers preserve transport and existing parsing',
      () async {
    final fees = FeesOperationalRepository(client: client);
    final weekly = WeeklyOfficerRepository(client: client);
    expect(await fees.creditBalance('member'), 0);
    expect(await weekly.currentMemberId(), isNull);
    expect(calls[0].rpc, 'fee_credit_balance_v1');
    expect(calls[0].params, {'target_club': club, 'p_member': 'member'});
    expect(calls[1].rpc, 'current_weekly_officer_member_v1');
    expect(calls[1].params, {'target_club': club});
    result = 25;
    expect(await fees.creditBalance('member'), 25);
    result = 'member';
    expect(await weekly.currentMemberId(), 'member');
  }, skip: AppConfig.demoMode);
  test('personal mutation signatures and void responses remain unchanged',
      () async {
    final events = EventsAdvancedRepository(client: client);
    await events.acknowledgeTask('task', complete: true);
    await events.setShiftMemberStatus('shift', 'present');
    await FeesOperationalRepository(client: client)
        .cancelReportedPayment('report');
    expect(calls.map((c) => c.rpc), [
      'acknowledge_event_task_v1',
      'set_event_shift_member_status_v1',
      'cancel_reported_fee_payment_v1'
    ]);
    expect(calls.map((c) => c.params), [
      {'p_assignment': 'task', 'p_complete': true},
      {'p_assignment': 'shift', 'p_status': 'present'},
      {'target_club': club, 'p_report': 'report'},
    ]);
  }, skip: AppConfig.demoMode);
  test('server rejection propagates with no fallback or second request',
      () async {
    reject = true;
    await expectLater(
        EventsAdvancedRepository(client: client).acknowledgeTask('task'),
        throwsA(
            isA<PostgrestException>().having((e) => e.code, 'code', 'P0001')));
    expect(calls, hasLength(1));
  }, skip: AppConfig.demoMode);
}
