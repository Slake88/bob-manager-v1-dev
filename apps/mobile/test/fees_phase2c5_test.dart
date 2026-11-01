import 'dart:convert';
import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/fees_repository.dart';
import 'package:bob_manager_mobile/screens/fees_annual_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeFees extends FeesRepository {
  int writes = 0;
  @override
  Future<List<Map<String, dynamic>>> listObligations({int? year}) async => [];
  @override
  Future<List<Map<String, dynamic>>> listMembers() async => [];
  @override
  Future<Map<String, dynamic>> settings() async => {};
  @override
  Future<void> prepareYear(int year) async {
    writes++;
  }
}

void main() {
  final session = AppSession.instance;
  tearDown(session.clear);
  testWidgets(
      'opening refresh and navigation never prepare; confirmation is required',
      (tester) async {
    session.applyPermissions(['viewFees', 'manageFees']);
    final repo = FakeFees();
    await tester.pumpWidget(MaterialApp(home: FeesScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    await tester.tap(find.byTooltip('Ano anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Preparar ano'), findsNothing);
    await tester.tap(find.byTooltip('Ano seguinte'));
    await tester.pumpAndSettle();
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    await tester.tap(find.text('Preparar ano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.writes, 0);
    await tester.tap(find.text('Preparar ano'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preparar'));
    await tester.pumpAndSettle();
    expect(repo.writes, 1);
  }, skip: AppConfig.demoMode);
  test('preparation uses new RPC; settings never generate', () async {
    session.applyPermissions(['viewFees', 'manageFees']);
    final calls = <http.Request>[];
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((r) async {
      calls.add(r);
      return http.Response('null', 200,
          headers: {'content-type': 'application/json'}, request: r);
    }));
    addTearDown(client.dispose);
    final repo = FeesRepository(client: client);
    await repo.updateSettings(
        dueDay: 8, monthlyAmount: 25, registrationAmount: 10);
    expect(
        calls.map((r) => r.url.pathSegments.last), ['update_fee_settings_v1']);
    calls.clear();
    await repo.prepareYear(2099);
    expect(calls.single.url.pathSegments.last, 'prepare_member_fees_year_v1');
    expect(jsonDecode(calls.single.body),
        {'target_club': session.clubId, 'p_year': 2099});
    session.applyPermissions(['viewFees']);
    await expectLater(repo.prepareYear(2099), throwsStateError);
    expect(calls.length, 1);
  }, skip: AppConfig.demoMode);

  test('obligations use the installed member foreign-key name', () async {
    session.clubId = '22000000-0000-0000-0000-000000000001';
    session.applyPermissions(['viewFees']);
    final calls = <http.Request>[];
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      calls.add(request);
      return http.Response('[]', 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);

    await FeesRepository(client: client).listObligations(year: 2026);

    expect(calls, hasLength(1));
    expect(
      calls.single.url.queryParameters['select'],
      '*,member:members!fk_fee_obligations_member_id(full_name)',
    );
    expect(calls.single.url.queryParameters['club_id'], 'eq.${session.clubId}');
    expect(calls.single.url.queryParameters['reference_year'], 'eq.2026');
  }, skip: AppConfig.demoMode);

  testWidgets('empty annual map shows its explicit empty state',
      (tester) async {
    session.role = 'Administrador';
    session.applyPermissions(['viewFees']);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FeesScreen(repository: FakeFees())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Mapa anual'), findsWidgets);
    expect(find.text('Sem inscrições registadas neste ano.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: AppConfig.demoMode);
}
