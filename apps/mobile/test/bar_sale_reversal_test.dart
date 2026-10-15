import 'dart:convert';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/bar_sales_repository.dart';
import 'package:bob_manager_mobile/repositories/weekly_dinner_finance_repository.dart';
import 'package:bob_manager_mobile/services/data_service.dart';
import 'package:bob_manager_mobile/widgets/bar_sale_history_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const permissions = [
  'viewBar',
  'manageBar',
  'reverseTreasuryMovement',
  'viewFinancialReports',
  'approveExpenseRequests'
];
Map<String, dynamic> historySale({String status = 'completed'}) => {
      'id': 'sale-1',
      'status': status,
      'total_amount': 17.5,
      'completed_at': '2026-10-11T12:00:00Z',
      'completed_actor_name': 'João',
      'completed_by': 'cashier',
      'reversal_reason': 'Duplicada',
      'reversed_at': '2026-10-11T13:00:00Z',
      'reversed_actor_name': 'Maria',
      'bar_sale_items': [
        {
          'description': 'Cerveja · Copo 0,25 L',
          'item_kind': 'stock',
          'quantity': 1,
          'unit_price': 2.5
        },
        {
          'description': 'Jantar',
          'item_kind': 'preset',
          'quantity': 1,
          'unit_price': 10
        },
        {
          'description': 'Sobremesa',
          'item_kind': 'other',
          'quantity': 2,
          'unit_price': 2.5
        },
      ],
    };

class FakeRepository extends BarSalesRepository {
  bool allowed = true;
  String? saleId;
  String? reason;
  @override
  bool get canReverse => allowed;
  @override
  Future<void> reverseSale(String id, String message) async {
    saleId = id;
    reason = message;
  }
}

void main() {
  int serial = 0;
  late String club;
  late DataService data;
  late BarSalesRepository repository;
  setUp(() async {
    await initializeDateFormatting('pt_PT');
    AppSession.instance.clear();
    club = 'bar-reversal-${serial++}';
    AppSession.instance.clubId = club;
    AppSession.instance.applyPermissions(permissions);
    data = DataService.instance;
    repository = BarSalesRepository();
  });
  tearDown(() {
    AppSession.instance.clear();
  });
  Future<void> showHistory(WidgetTester tester, FakeRepository repo,
      {String status = 'completed', VoidCallback? refreshed}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var rows = [historySale(status: status)];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                    child: BarSaleHistorySection(
                        sales: rows,
                        repository: repo,
                        onChanged: () async {
                          refreshed?.call();
                          setState(() {
                            rows = [historySale(status: 'reversed')];
                          });
                        }))))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'history shows stock, preset and other; confirmation requires reason and refreshes',
      (tester) async {
    final fake = FakeRepository();
    var refreshes = 0;
    await showHistory(tester, fake, refreshed: () {
      refreshes++;
    });
    expect(find.textContaining('Cerveja · Copo 0,25 L'), findsOneWidget);
    expect(find.textContaining('Jantar ·'), findsOneWidget);
    expect(find.textContaining('Sobremesa ·'), findsOneWidget);
    expect(find.text('Concluída'), findsOneWidget);
    await tester.tap(find.text('Anular venda'));
    await tester.pumpAndSettle();
    expect(find.textContaining('preserva o histórico'), findsOneWidget);
    await tester.tap(find.text('Confirmar anulação'));
    await tester.pumpAndSettle();
    expect(find.text('Indica o motivo (mínimo 3 caracteres).'), findsOneWidget);
    expect(fake.saleId, isNull);
    await tester.enterText(find.byType(TextFormField), '  Venda duplicada  ');
    await tester.tap(find.text('Confirmar anulação'));
    await tester.pumpAndSettle();
    expect(fake.saleId, 'sale-1');
    expect(fake.reason, 'Venda duplicada');
    expect(refreshes, 1);
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.text('Anular venda'), findsNothing);
    expect(find.text('Motivo: Duplicada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('without permission the action is absent', (tester) async {
    await showHistory(tester, FakeRepository()..allowed = false);
    expect(find.text('Concluída'), findsOneWidget);
    expect(find.text('Anular venda'), findsNothing);
  });
  testWidgets(
      'reversed sale shows reason, actor and date without another action',
      (tester) async {
    await showHistory(tester, FakeRepository(), status: 'reversed');
    expect(find.text('Anulada'), findsOneWidget);
    expect(find.textContaining('Maria'), findsOneWidget);
    expect(find.textContaining('11/10/2026'), findsNWidgets(2));
    expect(find.text('Anular venda'), findsNothing);
  });
  test(
      'production RPC receives exact club, sale and trimmed reason; history has its own RPC',
      () async {
    final requests = <String>[];
    final client = SupabaseClient('https://example.supabase.co', 'test',
        httpClient: MockClient((request) async {
      requests.add(request.url.path);
      final payload = jsonDecode(request.body) as Map;
      expect(payload['target_club'], club);
      if (request.url.path.endsWith('reverse_bar_sale_v1')) {
        expect(payload['p_sale'], 'sale-1');
        expect(payload['p_reason'], 'Erro de registo');
        return http.Response('"reversal-1"', 200,
            request: request, headers: {'content-type': 'application/json'});
      }
      expect(payload['p_limit'], 100);
      return http.Response(jsonEncode([historySale(status: 'reversed')]), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    final repo = BarSalesRepository(client: client);
    await repo.reverseSale('sale-1', ' Erro de registo ');
    expect((await repo.saleHistory()).single['status'], 'reversed');
    expect(requests.length, 2);
    AppSession.instance.applyPermissions(['viewBar', 'manageBar']);
    await expectLater(repo.reverseSale('sale-1', 'Erro'), throwsStateError);
    expect(requests.length, 2);
  });
  test(
      'demo preset/other appears in history and reverses finance without stock',
      () async {
    final preset = await data.insert('bar_sale_presets',
        {'club_id': club, 'name': 'Jantar', 'unit_price': 10, 'active': true});
    final sale = await repository.createDraft();
    await repository.completeSale(saleId: sale, paymentMethod: 'cash', lines: [
      {'kind': 'preset', 'preset_id': preset['id'], 'quantity': 1},
      {
        'kind': 'other',
        'description': 'Sobremesa',
        'quantity': 1,
        'unit_price': 2
      },
    ]);
    expect((await repository.saleHistory()).single['bar_sale_items'],
        hasLength(2));
    final originals = (await data.list('bar_sale_items'))
        .where((i) => i['sale_id'] == sale)
        .toList();
    await repository.reverseSale(sale, 'Duplicada');
    final rows = await repository.saleHistory();
    expect(rows.single['status'], 'reversed');
    expect(rows.single['reversal_reason'], 'Duplicada');
    final txs = (await data.list('financial_transactions'))
        .where((t) => t['club_id'] == club)
        .toList();
    expect(txs, hasLength(2));
    expect(txs.where((t) => t['kind'] == 'expense').single['amount'], 12);
    expect(
        (await data.list('bar_operations')).where((o) => o['club_id'] == club),
        isEmpty);
    expect(
        (await data.list('bar_sale_items'))
            .where((i) => i['sale_id'] == sale)
            .toList(),
        originals);
    await expectLater(
        repository.reverseSale(sale, 'Novamente'), throwsStateError);
  });
  test(
      'demo mixed dose reversal preserves snapshots, returns exact stock and removes dinner totals',
      () async {
    final dinner = (await data.insert('weekly_dinners', {
      'club_id': club,
      'status': 'planned',
      'dinner_date': '2026-10-15',
      'dish': 'Jantar'
    }))['id']
        .toString();
    final product = await data.insert('products', {
      'club_id': club,
      'name': 'Cerveja',
      'active': true,
      'inventory_area': 'bar',
      'current_stock': 1000,
      'cost': .03,
      'sale_options': [
        {
          'id': 'dose',
          'active': true,
          'name': 'Copo 0,25 L',
          'stock_quantity': 250,
          'public_price': 2.5,
          'member_price': 2
        }
      ]
    });
    final preset = await data.insert('bar_sale_presets', {
      'club_id': club,
      'name': 'Jantar',
      'unit_price': 10,
      'active': true,
      'counts_as_dinner_meal': true
    });
    final sale = await repository.createDraft(weeklyDinnerId: dinner);
    await repository.completeSale(
        saleId: sale,
        paymentMethod: 'cash',
        weeklyDinnerId: dinner,
        lines: [
          {
            'kind': 'stock',
            'product_id': product['id'],
            'sale_option_id': 'dose',
            'quantity': 2
          },
          {'kind': 'preset', 'preset_id': preset['id'], 'quantity': 1},
          {
            'kind': 'other',
            'description': 'Outro',
            'quantity': 1,
            'unit_price': 2
          },
        ]);
    final originalItems = (await data.list('bar_sale_items'))
        .where((i) => i['sale_id'] == sale)
        .toList();
    final finance = WeeklyDinnerFinanceRepository();
    expect((await finance.detail(dinner)).number('meal_revenue'), 10);
    await data.update('products', product['id'].toString(), {'cost': .05});
    final concurrent = await Future.wait([
      repository.reverseSale(sale, 'Erro'),
      repository.reverseSale(sale, 'Erro')
    ].map((f) => f.then((_) => true).catchError((_) => false)));
    expect(concurrent.where((ok) => ok), hasLength(1));
    expect(
        (await data.getById(
            'products', product['id'].toString()))!['current_stock'],
        1000);
    expect((await data.getById('products', product['id'].toString()))!['cost'],
        .05);
    expect(
        (await data.list('bar_sale_items'))
            .where((i) => i['sale_id'] == sale)
            .toList(),
        originalItems);
    expect((await finance.detail(dinner)).number('total_revenue'), 0);
    expect((await finance.choices(dinner))['sales'], isEmpty);
    await expectLater(finance.assignSale(sale, dinner), throwsStateError);
  });
  test(
      'demo closed dinner blocks reversal, wrong club and missing permissions reject',
      () async {
    final dinner = (await data.insert('weekly_dinners', {
      'club_id': club,
      'status': 'planned',
      'dinner_date': '2026-10-15'
    }))['id']
        .toString();
    final sale = await repository.createDraft(weeklyDinnerId: dinner);
    await repository.completeSale(
        saleId: sale,
        paymentMethod: 'cash',
        weeklyDinnerId: dinner,
        lines: [
          {
            'kind': 'other',
            'description': 'Outro',
            'quantity': 1,
            'unit_price': 2
          }
        ]);
    await data.insert('weekly_dinner_finances',
        {'club_id': club, 'dinner_id': dinner, 'financial_status': 'closed'});
    await expectLater(repository.reverseSale(sale, 'Erro'), throwsStateError);
    AppSession.instance.clubId = 'foreign';
    await expectLater(repository.reverseSale(sale, 'Erro'), throwsStateError);
    AppSession.instance.clubId = club;
    for (final keys in [
      ['viewBar', 'manageBar'],
      ['viewBar', 'reverseTreasuryMovement']
    ]) {
      AppSession.instance.applyPermissions(keys);
      expect(repository.canReverse, isFalse);
      await expectLater(repository.reverseSale(sale, 'Erro'), throwsStateError);
    }
  });
}
