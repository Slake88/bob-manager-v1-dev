import 'dart:convert';

import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/models/dashboard_indicator_detail.dart';
import 'package:bob_manager_mobile/repositories/dashboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _cursor(DashboardIndicator indicator, String id,
        {int? number, String? date, String? time, String? text}) =>
    {
      'v': 1,
      'club_id': AppSession.instance.clubId,
      'indicator': indicator.key,
      'number': number,
      'date': date,
      'time': time,
      'text': text,
      'id': id,
    };

void main() {
  late Map<String, List<Map<String, dynamic>>> tables;
  late List<String> loaded;
  late DashboardRepository repository;
  final today = DateTime(2026, 10, 10);

  setUp(() {
    AppSession.instance.clear();
    tables = {
      'members': [
        {
          'id': 'm1',
          'full_name': 'Ana',
          'member_number': 1,
          'nickname': 'A',
          'status': 'active',
          'profile_id': 'actor'
        },
        {'id': 'm2', 'full_name': 'Prospect', 'status': 'prospect'},
        {'id': 'm3', 'status': 'former'},
        {'id': 'm4', 'status': 'deceased'},
        {'id': 'm5', 'status': 'honorary'},
        {'id': 'm6', 'status': 'full_color'},
      ],
      'financial_accounts': [
        {'id': 'a1', 'name': 'Caixa', 'opening_balance': 100, 'active': true},
        {'id': 'a2', 'name': 'Banco', 'opening_balance': 200, 'active': true},
        {'id': 'a3', 'opening_balance': 9999, 'active': false},
      ],
      'financial_transactions': [
        {
          'id': 't1',
          'kind': 'income',
          'account_id': 'a1',
          'amount': 20,
          'transaction_date': '2026-10-10'
        },
        {
          'id': 't2',
          'kind': 'expense',
          'account_id': 'a2',
          'amount': 5,
          'transaction_date': '2026-10-10'
        },
        {
          'id': 't3',
          'kind': 'transfer',
          'account_id': 'a1',
          'destination_account_id': 'a2',
          'amount': 50
        },
      ],
      'fee_obligations': [
        {
          'id': 'f1',
          'member_id': 'm1',
          'amount': 25,
          'paid_amount': 10,
          'adjustment_amount': 100,
          'exempt_amount': 10,
          'balance': 500,
          'due_date': '2026-10-09'
        },
        {
          'id': 'f2',
          'member_id': 'm1',
          'amount': 25,
          'paid_amount': 0,
          'due_date': '2027-01-01'
        },
        {'id': 'f3', 'amount': 25, 'paid_amount': 25},
        {'id': 'f4', 'amount': 25, 'paid_amount': 30},
      ],
      'events': [
        {
          'id': 'e1',
          'name': 'Antigo aberto',
          'status': 'planning',
          'starts_at': '2020-01-01'
        },
        {'id': 'e2', 'status': 'completed'},
        {'id': 'e3', 'status': 'cancelled'},
        {'id': 'e4', 'status': 'archived'},
        {'id': 'e5', 'status': 'approved'},
      ],
      'products': [
        {
          'id': 'p1',
          'name': 'Reservas',
          'current_stock': 10,
          'reserved_stock': 7,
          'minimum_stock': 3,
          'active': true
        },
        {
          'id': 'p2',
          'name': 'Inativo',
          'current_stock': 0,
          'reserved_stock': 0,
          'minimum_stock': 3,
          'active': false
        },
        {
          'id': 'p3',
          'current_stock': 10,
          'reserved_stock': 0,
          'minimum_stock': 3,
          'active': true
        },
        {
          'id': 'p4',
          'name': 'BAR',
          'inventory_area': 'bar',
          'current_stock': 0,
          'reserved_stock': 0,
          'minimum_stock': 3,
          'active': true
        },
      ],
      'documents': [
        {
          'id': 'd1',
          'name': 'Hoje',
          'expires_at': '2026-10-10',
          'scope': 'club',
          'sensitive': false
        },
        {
          'id': 'd2',
          'name': 'Dia 30',
          'expires_at': '2026-11-09',
          'scope': 'club',
          'sensitive': true
        },
        {'id': 'd3', 'name': 'Dia 31', 'expires_at': '2026-11-10'},
        {'id': 'd4', 'name': 'Ontem', 'expires_at': '2026-10-09'},
      ],
      'financial_requests': [
        {
          'id': 'r1',
          'request_type': 'charge',
          'description': 'Pedido',
          'status': 'pending_review',
          'amount': 20,
          'requested_by': 'actor',
          'member_id': 'm2'
        },
        {'id': 'r2', 'status': 'awaiting_validation'},
        {'id': 'r3', 'status': 'approved'},
        {'id': 'r4', 'status': 'awaiting_payment'},
        {'id': 'r5', 'status': 'needs_info'},
      ],
    };
    loaded = [];
    repository = DashboardRepository(
      now: () => today,
      demoLoader: (table) async {
        loaded.add(table);
        return tables[table] ?? [];
      },
    );
  });
  tearDown(() => AppSession.instance.clear());

  test('ativos excluem prospects, antigos e falecidos; outros estados mantidos',
      () async {
    final summary = await repository.summary();
    final active =
        await repository.indicatorDetails(DashboardIndicator.members);
    final prospects =
        await repository.indicatorDetails(DashboardIndicator.prospects);
    expect(summary['members'], 3);
    expect(summary['prospects'], 1);
    expect(active.rows.map((row) => row['id']), ['m1', 'm5', 'm6']);
    expect(prospects.rows.single['id'], 'm2');
    expect(active.rows.first['nickname'], 'A');
  });

  test('saldos ativos incluem transferencias e somam exatamente o resumo',
      () async {
    final summary = await repository.summary();
    final detail =
        await repository.indicatorDetails(DashboardIndicator.totalBalance);
    expect(detail.rows.map((row) => row['balance']), [245, 70]);
    expect(detail.monetaryTotal, 315);
    expect(
        detail.rows.fold<num>(0, (sum, row) => sum + (row['balance'] as num)),
        summary['total_balance']);
    expect(detail.totalRows, 2);
  });

  test('quotas usam amount-paid, incluem futuras e ignoram ajustes/isenções',
      () async {
    final summary = await repository.summary();
    final detail =
        await repository.indicatorDetails(DashboardIndicator.feeOutstanding);
    expect(detail.rows.map((row) => row['outstanding']), [15, 25]);
    expect(detail.monetaryTotal, summary['fee_outstanding']);
    expect(detail.monetaryTotal, 40);
    expect(detail.rows.first['member_name'], 'Ana');
    expect(summary['overdue_fees'], 1);
  });

  test('eventos abertos excluem exatamente os tres estados sem filtro de data',
      () async {
    final detail =
        await repository.indicatorDetails(DashboardIndicator.openEvents);
    expect(detail.rows.map((row) => row['id']), ['e1', 'e5']);
    expect((await repository.summary())['open_events'], detail.totalRows);
  });

  test('stock considera reservas, igualdade ao minimo e produto ativo',
      () async {
    final detail =
        await repository.indicatorDetails(DashboardIndicator.lowStock);
    expect(detail.rows.map((row) => row['id']), ['p4', 'p1']);
    expect(detail.rows.last['available_stock'], 3);
    expect(detail.rows.first.containsKey('cost'), isFalse);
    expect((await repository.summary())['low_stock'], detail.totalRows);
  });

  test('documentos incluem hoje/+30 e excluem ontem/+31', () async {
    final detail =
        await repository.indicatorDetails(DashboardIndicator.expiringDocuments);
    expect(detail.rows.map((row) => row['id']), ['d1', 'd2']);
    expect(detail.rows.first.containsKey('_scope'), isFalse);
    expect(
        (await repository.summary())['expiring_documents'], detail.totalRows);
  });

  test('aprovações incluem dois estados e usam requested_by, não member_id',
      () async {
    final detail =
        await repository.indicatorDetails(DashboardIndicator.pendingApprovals);
    expect(detail.rows.map((row) => row['id']), ['r1', 'r2']);
    expect(detail.rows.first['requester_name'], 'Ana');
    expect(detail.rows.first['requested_by'], 'actor');
    expect(detail.rows.first['requester_name_missing'], isFalse);
    expect((await repository.summary())['pending_approvals'], detail.totalRows);
  });

  test('member não recebe valores financeiros no summary nem no detalhe',
      () async {
    AppSession.instance.role = 'member';
    final summary = await repository.summary();
    expect(summary['can_view_financial'], isFalse);
    for (final field in [
      'total_balance',
      'fee_outstanding',
      'monthly_income',
      'monthly_expense'
    ]) {
      expect(summary[field], isNull);
    }
    expect(loaded, isNot(contains('financial_accounts')));
    expect(loaded, isNot(contains('financial_transactions')));
    loaded.clear();
    for (final indicator in [
      DashboardIndicator.totalBalance,
      DashboardIndicator.feeOutstanding,
      DashboardIndicator.pendingApprovals,
    ]) {
      final detail = await repository.indicatorDetails(indicator);
      expect(detail.canDisplay, isFalse);
      expect(detail.rows, isEmpty);
      expect(detail.aggregate, isNull);
    }
    expect(loaded, isEmpty);
  });

  test('viewTreasury não permite consultar todas as quotas', () async {
    AppSession.instance.applyPermissions(['viewTreasury']);
    final detail =
        await repository.indicatorDetails(DashboardIndicator.feeOutstanding);
    expect(detail.canDisplay, isFalse);
    expect(detail.rows, isEmpty);
    expect(loaded, isEmpty);
  });

  test('inventário parcial recusa todo o detalhe, incluindo a segunda pagina',
      () async {
    AppSession.instance.applyPermissions(['viewInventory']);
    final detail = await repository.indicatorDetails(
      DashboardIndicator.lowStock,
      limit: 1,
      cursor: _cursor(DashboardIndicator.lowStock, 'p1', text: 'Reservas'),
    );
    expect(detail.canDisplay, isFalse);
    expect(detail.rows, isEmpty);
    expect(detail.totalRows, isNull);
    expect(detail.nextCursor, isNull);
    AppSession.instance.applyPermissions(['viewInventory', 'viewBar']);
    expect(
        (await repository.indicatorDetails(DashboardIndicator.lowStock))
            .canDisplay,
        isTrue);
  });

  test('documento sensível oculto impede devolver lista parcial', () async {
    AppSession.instance.applyPermissions(['viewDocuments']);
    final detail =
        await repository.indicatorDetails(DashboardIndicator.expiringDocuments);
    expect(detail.canDisplay, isFalse);
    expect(detail.rows, isEmpty);
  });

  test('scopes pessoais e direção respeitam proprietário e permissões',
      () async {
    tables['documents'] = [
      {
        'id': 'd1',
        'expires_at': '2026-10-10',
        'scope': 'personal',
        'owner_profile_id': AppSession.instance.profileId
      },
    ];
    AppSession.instance.applyPermissions(['viewDocuments']);
    expect(
        (await repository
                .indicatorDetails(DashboardIndicator.expiringDocuments))
            .canDisplay,
        isTrue);
    tables['documents']!.first['owner_profile_id'] = 'other';
    expect(
        (await repository
                .indicatorDetails(DashboardIndicator.expiringDocuments))
            .canDisplay,
        isFalse);
    AppSession.instance.applyPermissions(['manageDocuments']);
    expect(
        (await repository
                .indicatorDetails(DashboardIndicator.expiringDocuments))
            .canDisplay,
        isTrue);
    tables['documents']!.first['scope'] = 'leadership';
    expect(
        (await repository
                .indicatorDetails(DashboardIndicator.expiringDocuments))
            .canDisplay,
        isFalse);
    AppSession.instance.applyPermissions(['viewSensitiveDocuments']);
    expect(
        (await repository
                .indicatorDetails(DashboardIndicator.expiringDocuments))
            .canDisplay,
        isTrue);
  });

  test('paginação de mais de 500 linhas não duplica nem omite', () async {
    tables['members'] = List.generate(
        503,
        (i) => {
              'id': 'm${i.toString().padLeft(4, '0')}',
              'full_name': 'Grupo ${i % 5}',
              'member_number': i % 7 == 6 ? null : i % 7,
              'status': 'active',
            }).reversed.toList();
    final ids = <String>[];
    Map<String, dynamic>? cursor;
    do {
      final detail = await repository.indicatorDetails(
        DashboardIndicator.members,
        limit: 50,
        cursor: cursor,
      );
      expect(detail.totalRows, 503);
      ids.addAll(detail.rows.map((row) => row['id'] as String));
      cursor = detail.nextCursor;
    } while (cursor != null);
    expect(ids.length, 503);
    expect(ids.toSet().length, 503);
    final expected = <String>[
      for (var number = 0; number < 7; number++)
        for (var name = 0; name < 5; name++)
          for (var i = 0; i < 503; i++)
            if (i % 7 == number && i % 5 == name)
              'm${i.toString().padLeft(4, '0')}',
    ];
    expect(ids, expected);
  });

  test('demo separa os clubes', () async {
    tables['members']!.add({
      'id': 'foreign',
      'status': 'active',
      'club_id': 'other-club',
    });
    final detail =
        await repository.indicatorDetails(DashboardIndicator.members);
    expect(detail.rows.any((row) => row['id'] == 'foreign'), isFalse);
  });

  test(
      'resposta não autorizada nunca expõe linhas, mesmo se servidor as enviar',
      () {
    final detail =
        DashboardIndicatorDetail.fromMap(DashboardIndicator.members, {
      'indicator': 'members',
      'authorized': true,
      'complete': false,
      'rows': [
        {'id': 'secret'}
      ],
      'total_rows': 99,
      'monetary_total': 100,
      'next_cursor': _cursor(DashboardIndicator.members, 'secret'),
    });
    expect(detail.rows, isEmpty);
    expect(detail.totalRows, isNull);
    expect(detail.monetaryTotal, isNull);
    expect(detail.nextCursor, isNull);
  });

  test('producao envia e recebe cursor JSONB como objeto', () async {
    final calls = <Map<String, dynamic>>[];
    final nextCursor = _cursor(
        DashboardIndicator.members, '00000000-0000-0000-0000-000000000010',
        number: 7, text: 'Ana');
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/dashboard_indicator_details_v1');
        calls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'indicator': 'members',
              'authorized': true,
              'complete': true,
              'rows': [],
              'total_rows': 26,
              'monetary_total': null,
              'next_cursor': calls.length == 1 ? nextCursor : null,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request);
      }),
    );
    addTearDown(client.dispose);
    final production = DashboardRepository(client: client);
    final first = await production.indicatorDetails(DashboardIndicator.members,
        limit: 25);
    expect(first.nextCursor, isA<Map<String, dynamic>>());
    expect(first.nextCursor, nextCursor);
    final second = await production.indicatorDetails(DashboardIndicator.members,
        limit: 25, cursor: first.nextCursor);
    expect(second.nextCursor, isNull);
    expect(calls.first, {
      'target_club': AppSession.instance.clubId,
      'p_indicator': 'members',
      'p_limit': 25,
      'p_cursor': null,
    });
    expect(calls.last, {...calls.first, 'p_cursor': nextCursor});
    expect(calls.last['p_cursor'], isA<Map<String, dynamic>>());
  });

  test('fromMap aceita cursor JSONB e null, preservando chaves nulas', () {
    final cursor =
        _cursor(DashboardIndicator.members, 'm1', number: 1, text: 'Ana');
    for (final next in [cursor, null]) {
      final detail =
          DashboardIndicatorDetail.fromMap(DashboardIndicator.members, {
        'indicator': 'members',
        'authorized': true,
        'complete': true,
        'rows': [],
        'total_rows': 2,
        'next_cursor': next,
      });
      expect(detail.nextCursor, next);
    }
  });

  test('demo recusa cursor de outro clube/indicador antes de carregar',
      () async {
    for (final field in ['club_id', 'indicator']) {
      final cursor = _cursor(DashboardIndicator.members, 'm1')
        ..[field] = field == 'club_id' ? 'other-club' : 'prospects';
      await expectLater(
          repository.indicatorDetails(DashboardIndicator.members,
              cursor: cursor),
          throwsFormatException);
    }
    expect(loaded, isEmpty);
  });

  test('demo recusa estrutura, versao e tipos invalidos do cursor', () async {
    final valid = _cursor(DashboardIndicator.members, 'm1');
    for (final cursor in [
      {...valid}..remove('text'),
      {...valid, 'extra': 1},
      {...valid, 'v': 2},
      {...valid, 'number': '1'},
      {...valid, 'number': 1.5},
      {...valid, 'number': 2147483648},
      {...valid, 'text': 1},
      {...valid, 'date': '2026-02-30'},
      {...valid, 'time': 'invalid'},
      {...valid, 'id': null},
      {...valid, 'id': ''},
      {...valid, 'date': '2026-10-10'},
    ]) {
      await expectLater(
          repository.indicatorDetails(DashboardIndicator.members,
              cursor: cursor),
          throwsFormatException);
    }
    expect(loaded, isEmpty);
  });

  Future<void> expectPages(
      DashboardIndicator indicator, List<String> expected) async {
    final actual = <String>[];
    Map<String, dynamic>? cursor;
    var pages = 0;
    do {
      final detail = await repository.indicatorDetails(indicator,
          limit: 1, cursor: cursor);
      expect(detail.canDisplay, isTrue);
      expect(detail.totalRows, expected.length);
      actual.addAll(detail.rows.map((row) => row['id'] as String));
      cursor = detail.nextCursor;
      if (cursor != null) {
        expect(cursor, isA<Map<String, dynamic>>());
        expect(
            cursor.keys,
            unorderedEquals([
              'v',
              'club_id',
              'indicator',
              'number',
              'date',
              'time',
              'text',
              'id'
            ]));
        expect(cursor['id'], detail.rows.single['id']);
        expect(cursor['indicator'], indicator.key);
        expect(cursor['club_id'], AppSession.instance.clubId);
      }
      expect(++pages, lessThanOrEqualTo(expected.length));
    } while (cursor != null);
    expect(actual, expected);
    expect(actual.toSet().length, expected.length);
  }

  for (final indicator in [
    DashboardIndicator.members,
    DashboardIndicator.prospects
  ]) {
    test('${indicator.key}: numero/nome/id com NULLS LAST entre paginas',
        () async {
      tables['members'] = [
        {'id': 'm6', 'member_number': null, 'full_name': 'Ana'},
        {'id': 'm5', 'member_number': 2, 'full_name': 'Ana'},
        {'id': 'm4', 'member_number': 1, 'full_name': 'Bea'},
        {'id': 'm3', 'member_number': 1, 'full_name': 'Ana'},
        {'id': 'm2', 'member_number': 1, 'full_name': 'Ana'},
        {'id': 'm1', 'member_number': 0, 'full_name': 'Zoe'},
        {'id': 'm7', 'member_number': null, 'full_name': null},
      ]
          .map((row) => {
                ...row,
                'status': indicator == DashboardIndicator.members
                    ? 'active'
                    : 'prospect'
              })
          .toList();
      await expectPages(indicator, ['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'm7']);
    });
  }

  test('contas: nome/id com paginacao e nomes iguais', () async {
    tables['financial_accounts'] = [
      {'id': 'a3', 'name': 'Caixa', 'active': true},
      {'id': 'a2', 'name': 'Banco', 'active': true},
      {'id': 'a1', 'name': 'Banco', 'active': true},
    ];
    await expectPages(DashboardIndicator.totalBalance, ['a1', 'a2', 'a3']);
  });

  test('stock: nomes iguais usam id como desempate', () async {
    tables['products'] = [
      {'id': 'p3', 'name': 'Z'},
      {'id': 'p2', 'name': 'A'},
      {'id': 'p1', 'name': 'A'},
      {'id': 'p4', 'name': null},
    ]
        .map((row) => {
              ...row,
              'active': true,
              'current_stock': 0,
              'reserved_stock': 0,
              'minimum_stock': 1
            })
        .toList();
    await expectPages(DashboardIndicator.lowStock, ['p1', 'p2', 'p3', 'p4']);
  });

  test('eventos: starts_at/nome/id, incluindo instantes equivalentes',
      () async {
    tables['events'] = [
      {'id': 'e5', 'starts_at': null, 'name': 'A'},
      {'id': 'e4', 'starts_at': '2026-10-11T00:00:00Z', 'name': 'A'},
      {'id': 'e3', 'starts_at': '2026-10-10T10:00:00Z', 'name': 'B'},
      {'id': 'e2', 'starts_at': '2026-10-10T11:00:00+01:00', 'name': 'A'},
      {'id': 'e1', 'starts_at': '2026-10-10T10:00:00Z', 'name': 'A'},
    ].map((row) => {...row, 'status': 'planning'}).toList();
    await expectPages(
        DashboardIndicator.openEvents, ['e1', 'e2', 'e3', 'e4', 'e5']);
  });

  test('quotas: vencimento/nome/id com vencimento NULL no fim', () async {
    tables['members'] = [
      {'id': 'm1', 'full_name': 'Ana'},
      {'id': 'm2', 'full_name': 'Bea'},
    ];
    tables['fee_obligations'] = [
      {'id': 'f5', 'due_date': null, 'member_id': 'm1'},
      {'id': 'f4', 'due_date': '2026-10-11', 'member_id': 'm1'},
      {'id': 'f3', 'due_date': '2026-10-10', 'member_id': 'm2'},
      {'id': 'f2', 'due_date': '2026-10-10', 'member_id': 'm1'},
      {'id': 'f1', 'due_date': '2026-10-10', 'member_id': 'm1'},
    ].map((row) => {...row, 'amount': 1, 'paid_amount': 0}).toList();
    await expectPages(
        DashboardIndicator.feeOutstanding, ['f1', 'f2', 'f3', 'f4', 'f5']);
  });

  test('documentos: validade/nome/id entre paginas', () async {
    tables['documents'] = [
      {'id': 'd4', 'expires_at': '2026-10-11', 'name': 'A'},
      {'id': 'd3', 'expires_at': '2026-10-10', 'name': 'B'},
      {'id': 'd2', 'expires_at': '2026-10-10', 'name': 'A'},
      {'id': 'd1', 'expires_at': '2026-10-10', 'name': 'A'},
    ];
    await expectPages(
        DashboardIndicator.expiringDocuments, ['d1', 'd2', 'd3', 'd4']);
  });

  test('aprovacoes: created_at/id, sem expor chave interna', () async {
    tables['financial_requests'] = [
      {'id': 'r4', 'created_at': null},
      {'id': 'r3', 'created_at': '2026-10-11T00:00:00Z'},
      {'id': 'r2', 'created_at': '2026-10-10T00:00:00Z'},
      {'id': 'r1', 'created_at': '2026-10-10T00:00:00Z'},
    ].map((row) => {...row, 'status': 'pending_review'}).toList();
    await expectPages(
        DashboardIndicator.pendingApprovals, ['r1', 'r2', 'r3', 'r4']);
    final detail =
        await repository.indicatorDetails(DashboardIndicator.pendingApprovals);
    expect(detail.rows.first.containsKey('_created_at'), isFalse);
  });

  test('requerente usa profile sem member; dados ausentes sao explicitos',
      () async {
    tables['members']!.first.remove('profile_id');
    tables['profiles'] = [
      {'id': 'actor', 'full_name': ' Gestor sem membro '},
      {'id': 'blank', 'full_name': '   '},
    ];
    tables['members']!.add({
      'id': 'blank-member',
      'profile_id': 'blank',
      'full_name': 'Nao substituir perfil sem nome'
    });
    tables['financial_requests'] = [
      {'id': 'r1', 'requested_by': 'actor', 'member_id': 'm2'},
      {'id': 'r2', 'requested_by': 'blank'},
      {'id': 'r3', 'requested_by': 'unknown'},
      {'id': 'r4', 'requested_by': null},
    ].map((row) => {...row, 'status': 'pending_review'}).toList();
    final detail =
        await repository.indicatorDetails(DashboardIndicator.pendingApprovals);
    expect(detail.rows.first['requester_name'], 'Gestor sem membro');
    expect(detail.rows.first['requester_name_missing'], isFalse);
    expect(detail.rows.first['requested_by'], 'actor');
    for (final row in detail.rows.skip(1)) {
      expect(row['requester_name'], isNull);
      expect(row['requester_name_missing'], isTrue);
    }
  });

  test('limites inválidos são recusados', () async {
    for (final limit in [0, 101]) {
      await expectLater(
          repository.indicatorDetails(DashboardIndicator.members, limit: limit),
          throwsArgumentError);
    }
    expect(loaded, isEmpty);
  });
}
