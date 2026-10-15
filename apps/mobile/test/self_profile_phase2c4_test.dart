import 'dart:convert';
import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/member_repository.dart';
import 'package:bob_manager_mobile/screens/member_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final session = AppSession.instance;
  const member = {
    'id': 'member-a',
    'profile_id': 'demo-profile',
    'full_name': 'A'
  };
  tearDown(session.clear);

  testWidgets('own profile edit follows dynamic permission', (tester) async {
    session.clear();
    session.role = 'member';
    for (final allowed in [false, true, false]) {
      session.applyPermissions(allowed ? ['editOwnMemberProfile'] : []);
      await tester.pumpWidget(MaterialApp(
          home: MemberDetailScreen(key: UniqueKey(), member: member)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Editar membro'),
          allowed ? findsOneWidget : findsNothing);
    }
  }, skip: !AppConfig.demoMode);

  testWidgets('own permission does not allow editing another profile',
      (tester) async {
    session.clear();
    session.applyPermissions(['editOwnMemberProfile']);
    await tester.pumpWidget(const MaterialApp(
        home: MemberDetailScreen(member: {
      'id': 'member-b',
      'profile_id': 'other',
      'full_name': 'B'
    })));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Editar membro'), findsNothing);
  }, skip: !AppConfig.demoMode);

  test('repository uses v2 with NIF and all self-service fields', () async {
    session.clear();
    final calls = <http.Request>[];
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      calls.add(request);
      final dynamic data = request.url.path.contains('/rpc/')
          ? 'member-a'
          : request.url.pathSegments.last == 'members'
              ? member
              : [];
      return http.Response(jsonEncode(data), 200,
          headers: {'content-type': 'application/json'}, request: request);
    }));
    addTearDown(client.dispose);
    final fields = {
      'email': 'a@example.invalid',
      'phone': 'phone',
      'address': 'address',
      'postal_code': 'postal',
      'locality': 'locality',
      'tax_number': '123456789',
      'emergency_name': 'name',
      'emergency_relation': 'relation',
      'emergency_phone': 'emergency',
      'blood_type': 'O+',
      'allergies': 'allergy',
      'medical_notes': 'note',
    };
    final result =
        await MemberRepository(client: client).updateOwnMemberProfile(fields);
    expect(result['id'], 'member-a');
    final writes = calls.where((r) => r.method != 'GET').toList();
    expect(writes.length, 1);
    expect(writes.single.url.pathSegments.last, 'update_own_member_profile_v2');
    expect(jsonDecode(writes.single.body), {
      'target_club': session.clubId,
      for (final entry in fields.entries) 'p_${entry.key}': entry.value,
    });
  }, skip: AppConfig.demoMode);
}
