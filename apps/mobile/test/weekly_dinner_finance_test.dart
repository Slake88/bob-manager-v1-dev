import 'dart:async';
import 'dart:convert';
import 'package:intl/date_symbol_data_local.dart';
import 'package:bob_manager_mobile/screens/weekly_officer_screen.dart';
import 'package:bob_manager_mobile/screens/bar_sales_advanced_screen.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/models/weekly_dinner_finance.dart';
import 'package:bob_manager_mobile/repositories/bar_sales_repository.dart';
import 'package:bob_manager_mobile/repositories/weekly_dinner_finance_repository.dart';
import 'package:bob_manager_mobile/services/data_service.dart';
import 'package:bob_manager_mobile/widgets/dinner_association_field.dart';
import 'package:bob_manager_mobile/widgets/weekly_dinner_finance_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const permissions = [
  'viewFinancialReports',
  'approveExpenseRequests',
  'viewBar',
  'manageBar',
  'selectBarFinancialAccount'
];
const lines = <Map<String, dynamic>>[
  {'dinner_component_snapshot': 'meal', 'quantity': 10, 'line_total': 100},
  {
    'dinner_component_snapshot': 'bar',
    'quantity': 10,
    'line_total': 20,
    'unit_cost_snapshot': .6,
    'cost_total_snapshot': 6
  },
  {'dinner_component_snapshot': 'excluded', 'quantity': 1, 'line_total': 4},
];
const expenses = <Map<String, dynamic>>[
  {'cost_kind': 'food', 'amount': 30},
  {'cost_kind': 'other', 'amount': 5},
  {'cost_kind': 'food', 'amount': 100, 'reversed': true},
];

class PanelRepo extends WeeklyDinnerFinanceRepository {
  Future<WeeklyDinnerFinance>? response;
  int reads = 0;
  bool allowed = true;
  WeeklyDinnerFinance value = WeeklyDinnerFinance.calculate(
      lines: lines,
      expenses: expenses,
      settings: const {'financial_status': 'open'});
  @override
  bool get canRead => allowed;
  @override
  bool get canManage => allowed;
  @override
  Future<WeeklyDinnerFinance> detail(String id) {
    reads++;
    if (!allowed) {
      return Future.error(StateError('Sem autorização financeira.'));
    }
    return response ?? Future.value(value);
  }
}

Future<void> panel(
    WidgetTester tester, WeeklyDinnerFinanceRepository repository,
    {Size size = const Size(1100, 1600)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: WeeklyDinnerFinanceDialog(
              dinner: const {'id': 'dinner', 'dish': 'Feijoada'},
              repository: repository))));
  await tester.pump();
  await tester.pump();
}

void main() {
  var serial = 0;
  late DataService data;
  late WeeklyDinnerFinanceRepository repo;
  late BarSalesRepository bar;
  late String club;
  setUp(() async {
    await initializeDateFormatting('pt_PT');
    AppSession.instance.clear();
    club = 'dinner-test-${serial++}';
    AppSession.instance.clubId = club;
    AppSession.instance.applyPermissions(permissions);
    data = DataService.instance;
    repo = WeeklyDinnerFinanceRepository();
    bar = BarSalesRepository();
  });
  tearDown(() => AppSession.instance.clear());
  Future<String> dinner({String? inClub}) async =>
      (await data.insert('weekly_dinners', {
        'club_id': inClub ?? club,
        'dinner_date': '2026-10-15',
        'dish': 'Jantar de teste',
        'status': 'planned'
      }))['id']
          .toString();
  Future<Map<String, dynamic>> mixedDinner() async {
    final id = await dinner();
    final product = await data.insert('products', {
      'club_id': club,
      'name': 'Cerveja',
      'inventory_area': 'bar',
      'active': true,
      'current_stock': 100,
      'cost': .6,
      'sale_options': [
        {
          'id': 'beer',
          'name': 'Unidade',
          'stock_quantity': 1,
          'public_price': 2,
          'member_price': 1.5
        }
      ]
    });
    final preset = await data.insert('bar_sale_presets', {
      'club_id': club,
      'name': 'Jantar',
      'active': true,
      'unit_price': 10,
      'counts_as_dinner_meal': true
    });
    final sale = await bar.createDraft(weeklyDinnerId: id);
    await bar.completeSale(
        saleId: sale,
        weeklyDinnerId: id,
        paymentMethod: 'cash',
        lines: [
          {
            'kind': 'stock',
            'product_id': product['id'],
            'sale_option_id': 'beer',
            'quantity': 10
          },
          {'kind': 'preset', 'preset_id': preset['id'], 'quantity': 2},
          {
            'kind': 'other',
            'description': 'Sobremesa',
            'quantity': 2,
            'unit_price': 2.5
          },
        ]);
    final item = (await data.list('bar_sale_items'))
        .singleWhere((r) => r['sale_id'] == sale && r['item_kind'] == 'other');
    return {'dinner': id, 'sale': sale, 'item': item};
  }

  Future<String> expense(num amount,
          {String? inClub, String? source, String? reversal}) async =>
      (await data.insert('financial_transactions', {
        'club_id': inClub ?? club,
        'kind': 'expense',
        'amount': amount,
        'source_type': source,
        'reversal_of': reversal
      }))['id']
          .toString();
  Future<void> settings(String id, {double food = 0}) => repo.save(id,
      mode: 'automatic', quantity: 0, revenue: 0, food: food, other: 0);
  test(
      'automatic separates meals, historical BAR cost, reversed costs and excluded revenue',
      () {
    final v = WeeklyDinnerFinance.calculate(lines: lines, expenses: expenses);
    expect(v.number('meal_quantity'), 10);
    expect(v.number('meal_profit'), 70);
    expect(v.number('beverage_cost'), 6);
    expect(v.number('beverage_profit'), 14);
    expect(v.number('total_revenue'), 120);
    expect(v.number('total_cost'), 41);
    expect(v.number('result'), 79);
    expect(v.number('margin_percent'), closeTo(79 / 120 * 100, 1e-8));
    expect(v.number('excluded_revenue'), 4);
    expect(v.number('excluded_line_count'), 1);
    expect(v.hasUnclassifiedRevenue, isTrue);
  });
  test(
      'legacy manual settings cannot override BAR meals; costs remain additional',
      () {
    final v = WeeklyDinnerFinance.calculate(
        lines: lines,
        expenses: expenses,
        settings: const {
          'meal_mode': 'manual',
          'manual_meal_quantity': 12,
          'manual_meal_revenue': 150,
          'food_cost_manual': 2,
          'other_cost_manual': 3
        });
    expect(v.number('meal_quantity'), 10);
    expect(v.number('bar_meal_revenue'), 100);
    expect(v.number('total_revenue'), 120);
    expect(v.number('total_cost'), 46);
    expect(v.number('result'), 74);
  });
  test('missing historical cost is unknown; zero revenue has zero margin', () {
    final v = WeeklyDinnerFinance.calculate(lines: const [
      {'dinner_component_snapshot': 'bar', 'line_total': 20}
    ], expenses: const []);
    expect(v.hasCosts, isFalse);
    expect(v.data['result'], isNull);
    expect(v.data['margin_percent'], isNull);
    expect(
        WeeklyDinnerFinance.calculate(lines: const [], expenses: const [])
            .number('margin_percent'),
        0);
  });
  test('annual totals include closed only and weighted global margin', () {
    final v = WeeklyDinnerFinance.annual([
      {
        'financial_status': 'closed',
        'summary': {'total_revenue': 100, 'total_cost': 50, 'result': 50}
      },
      {
        'financial_status': 'closed',
        'summary': {'total_revenue': 300, 'total_cost': 270, 'result': 30}
      },
      {
        'financial_status': 'open',
        'summary': {'total_revenue': 9999}
      },
      {'financial_status': 'none'},
    ]);
    expect(v['closed_count'], 2);
    expect(v['total_revenue'], 400);
    expect(v['total_cost'], 320);
    expect(v['result'], 80);
    expect(v['margin_percent'], 20);
  });
  test('concurrent demo seed creates exactly one coherent dinner', () async {
    await Future.wait(
        List.generate(3, (_) => WeeklyDinnerFinanceRepository.seedDemo()));
    final rows =
        (await data.list('weekly_dinners')).where((r) => r['club_id'] == club);
    expect(rows.length, 1);
    final v = await repo.detail(rows.single['id'].toString());
    expect(v.number('total_revenue'), 120);
    expect(v.number('beverage_cost'), 6);
  });
  test(
      'dose stock, member price, event, immutable cost, close/reopen and archived revisions',
      () async {
    final id = await dinner();
    final event = (await data
            .insert('events', {'club_id': club, 'name': 'Encontro'}))['id']
        .toString();
    final product = (await data.insert('products', {
      'club_id': club,
      'name': 'Dose',
      'inventory_area': 'bar',
      'active': true,
      'current_stock': 1000,
      'cost': .03,
      'sale_options': [
        {
          'id': 'dose',
          'name': '50 ml',
          'stock_quantity': 50,
          'public_price': 4,
          'member_price': 3
        }
      ]
    }))['id']
        .toString();
    final preset = (await data.insert('bar_sale_presets', {
      'club_id': club,
      'name': 'Refeição',
      'unit_price': 10,
      'counts_as_dinner_meal': true
    }))['id']
        .toString();
    final sale = await bar.createDraft(eventId: event, weeklyDinnerId: id);
    await bar.completeSale(
        saleId: sale,
        paymentMethod: 'cash',
        customerType: 'member',
        customerLabel: 'Grupo',
        weeklyDinnerId: id,
        lines: [
          {
            'kind': 'stock',
            'product_id': product,
            'sale_option_id': 'dose',
            'quantity': 2
          },
          {'kind': 'preset', 'preset_id': preset, 'quantity': 2}
        ]);
    expect((await data.getById('products', product))!['current_stock'], 900);
    final stock = (await data.list('bar_sale_items'))
        .where((r) => r['sale_id'] == sale && r['item_kind'] == 'stock')
        .single;
    expect(stock['unit_cost_snapshot'], .03);
    expect(stock['cost_total_snapshot'], 3);
    expect(stock['line_total'], 6);
    expect((await data.getById('bar_sales', sale))!['event_id'], event);
    expect(
        (await data.list('stock_movements'))
            .where((r) => r['club_id'] == club)
            .single['event_id'],
        event);
    await settings(id, food: 10);
    expect((await repo.setClosed(id, true)).number('result'), 13);
    await data
        .update('products', product, {'cost': 100, 'current_stock': 10000});
    await bar.savePreset(
        id: preset, name: 'Renamed', price: 1000, countsAsDinnerMeal: false);
    expect((await repo.detail(id)).number('result'), 13);
    await repo.setClosed(id, false);
    expect((await repo.detail(id)).number('beverage_cost'), 3);
    expect((await repo.detail(id)).number('meal_revenue'), 20);
    await settings(id, food: 12);
    expect((await repo.detail(id)).number('result'), 11);
    final second = await repo.setClosed(id, true);
    expect(second.data['revision'], 2);
    expect(second.rows('previous_snapshots').length, 2);
    expect(
        (second.rows('previous_snapshots').first['snapshot'] as Map)['result'],
        13);
    expect((await repo.history(2026))['result'], 11);
  });
  test(
      'expenses reject duplicates/stock/cross-club; reversal changes live, not closed snapshot',
      () async {
    final id = await dinner();
    final tx = await expense(30);
    await repo.linkExpense(id, tx, 'food');
    await expectLater(repo.linkExpense(id, tx, 'other'), throwsStateError);
    await expectLater(
        repo.linkExpense(id, await expense(9, inClub: 'foreign'), 'food'),
        throwsStateError);
    await expectLater(
        repo.linkExpense(id, await expense(9, source: 'bar'), 'food'),
        throwsStateError);
    expect((await repo.detail(id)).number('food_cost'), 30);
    await repo.setClosed(id, true);
    await expense(30, reversal: tx);
    expect((await repo.detail(id)).number('food_cost'), 30);
    await repo.setClosed(id, false);
    expect((await repo.detail(id)).number('food_cost'), 0);
  });
  test(
      'closed immutable; associated drafts and missing historical costs prevent close',
      () async {
    final id = await dinner();
    await repo.setClosed(id, true);
    await expectLater(settings(id, food: 1), throwsStateError);
    await expectLater(bar.createDraft(weeklyDinnerId: id), throwsStateError);
    await repo.setClosed(id, false);
    final sale = await bar.createDraft(weeklyDinnerId: id);
    await expectLater(repo.setClosed(id, true), throwsStateError);
    await bar.cancelDraft(sale);
    final historic = (await data.insert('bar_sales', {
      'club_id': club,
      'weekly_dinner_id': id,
      'status': 'completed'
    }))['id'];
    await data.insert('bar_sale_items',
        {'club_id': club, 'sale_id': historic, 'line_total': 4});
    await expectLater(repo.setClosed(id, true), throwsStateError);
  });
  test(
      'optional association clears draft choice and supports explicit historical linking',
      () async {
    final id = await dinner();
    await expectLater(
        bar.createDraft(weeklyDinnerId: await dinner(inClub: 'foreign')),
        throwsStateError);
    final sale = await bar.createDraft(weeklyDinnerId: id);
    await bar.completeSale(
        saleId: sale,
        lines: const [
          {
            'kind': 'other',
            'quantity': 1,
            'unit_price': 5,
            'description': 'Diversos'
          }
        ],
        paymentMethod: 'cash');
    expect(
        (await data.getById('bar_sales', sale))!['weekly_dinner_id'], isNull);
    await repo.assignSale(id, sale);
    expect((await data.getById('bar_sales', sale))!['weekly_dinner_id'], id);
    await repo.assignSale(id, sale, remove: true);
    expect(
        (await data.getById('bar_sales', sale))!['weekly_dinner_id'], isNull);
  });
  test('member cannot read or mutate finance through repository', () async {
    AppSession.instance.applyPermissions(['viewBar']);
    await expectLater(repo.detail('id'), throwsStateError);
    await expectLater(repo.history(2026), throwsStateError);
    await expectLater(repo.setClosed('id', true), throwsStateError);
  });
  test(
      'production uses V3 and forwards event/dinner independently; financial mutations gated',
      () async {
    final calls = <String, Map<String, dynamic>>{};
    final client = SupabaseClient('https://example.supabase.co', 'test-key',
        httpClient: MockClient((request) async {
      final name = request.url.pathSegments.last;
      calls[name] = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(name == 'create_bar_sale_v3' ? '"sale"' : '{}', 200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(() => client.dispose());
    final production = BarSalesRepository(client: client);
    await production.createDraft(eventId: 'event', weeklyDinnerId: 'dinner');
    await production.completeSale(
        saleId: 'sale',
        paymentMethod: 'cash',
        eventId: 'event',
        weeklyDinnerId: 'dinner',
        lines: const [
          {
            'kind': 'other',
            'quantity': 1,
            'unit_price': 1,
            'description': 'Test'
          }
        ]);
    expect(calls['create_bar_sale_v3']!['p_event'], 'event');
    expect(calls['complete_bar_sale_v3']!['p_weekly_dinner'], 'dinner');
    final financial = WeeklyDinnerFinanceRepository(client: client);
    await financial.detail('dinner');
    expect(calls['weekly_dinner_finance_v1'],
        {'target_club': club, 'p_dinner': 'dinner'});
    AppSession.instance.applyPermissions(['viewFinancialReports']);
    await expectLater(financial.setClosed('dinner', true), throwsStateError);
    expect(calls.containsKey('set_weekly_dinner_financial_closed_v1'), isFalse);
  });
  test(
      'today suggestion needs exactly one valid dinner and rejects ambiguity/cancelled',
      () {
    final today = DateTime(2026, 10, 15);
    final rows = [
      {'id': 'one', 'dinner_date': '2026-10-15', 'status': 'planned'}
    ];
    expect(suggestedDinnerForToday(rows, today), 'one');
    expect(
        suggestedDinnerForToday([
          ...rows,
          {'id': 'two', 'dinner_date': '2026-10-15'}
        ], today),
        isNull);
    expect(
        suggestedDinnerForToday([
          {'id': 'one', 'dinner_date': '2026-10-15', 'status': 'cancelled'}
        ], today),
        isNull);
  });
  testWidgets('BAR selector select/clear on mobile', (tester) async {
    String? value;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => DinnerAssociationField(
                        dinners: const [
                          {
                            'id': 'one',
                            'dinner_date': '2026-10-15',
                            'dish': 'Feijoada'
                          }
                        ],
                        value: value,
                        onChanged: (v) => setState(() => value = v))))));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15/10/2026 · Feijoada').last);
    await tester.pumpAndSettle();
    expect(value, 'one');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem jantar associado').last);
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('authorized mobile panel renders closed historic snapshot',
      (tester) async {
    final repository = PanelRepo()
      ..value = const WeeklyDinnerFinance({
        'financial_status': 'closed',
        'meal_mode': 'automatic',
        'meal_quantity': 10,
        'meal_revenue': 100,
        'beverage_revenue': 20,
        'beverage_cost': 6,
        'result': 79,
        'total_revenue': 120,
        'total_cost': 41,
        'margin_percent': 65.83,
        'closed_at': '2026-10-15',
        'revision': 1
      });
    await panel(tester, repository, size: const Size(390, 844));
    expect(find.text('Fechado · snapshot histórico'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Resultado do jantar'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Resultado do jantar'), findsOneWidget);
    expect(find.textContaining('79,00'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unauthorized panel reveals no monetary data', (tester) async {
    await panel(tester, PanelRepo()..allowed = false);
    expect(find.text('Resultado do jantar'), findsNothing);
    expect(find.textContaining('79,00'), findsNothing);
  });
  testWidgets('loading, failure, retry, empty dinner', (tester) async {
    final completer = Completer<WeeklyDinnerFinance>();
    final repository = PanelRepo()..response = completer.future;
    await panel(tester, repository);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.completeError(StateError('Teste de falha'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar o fecho financeiro.'),
        findsOneWidget);
    repository.response = Future.value(WeeklyDinnerFinance.calculate(
        lines: const [],
        expenses: const [],
        settings: const {'financial_status': 'none'}));
    await tester.tap(find.text('Repetir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sem fecho financeiro'), findsWidgets);
    expect(repository.reads, 2);
  });
  testWidgets(
      'Oficial member retains operational dinner but has no financial actions/history',
      (tester) async {
    AppSession.instance.role = 'member';
    AppSession.instance.applyPermissions(['viewBar']);
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: WeeklyOfficerScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Feijoada (Demo)'), findsWidgets);
    expect(find.text('Fecho financeiro'), findsNothing);
    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.byType(WeeklyDinnerFinancialHistory), findsNothing);
    expect(find.textContaining('Receita'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real demo dialog closes and reopens, with preserved archive',
      (tester) async {
    final id = await dinner();
    await repo.save(id,
        mode: 'automatic', quantity: 0, revenue: 0, food: 5, other: 1);
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WeeklyDinnerFinanceDialog(
                dinner: {'id': id, 'dish': 'Jantar'}, repository: repo))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fechar financeiramente'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Fechar financeiramente'));
    await tester.pumpAndSettle();
    expect((await repo.detail(id)).closed, isTrue);
    await tester.scrollUntilVisible(find.text('Reabrir fecho financeiro'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Reabrir fecho financeiro'));
    await tester.pumpAndSettle();
    expect((await repo.detail(id)).closed, isFalse);
    expect((await repo.detail(id)).rows('previous_snapshots').length, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'BAR preset editor saves explicit meal flag without controller lifecycle error',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BarSalesAdvancedScreen(repository: bar))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Criar preset'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Criar preset'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final fields =
        find.descendant(of: dialog, matching: find.byType(TextField));
    await tester.enterText(fields.first, 'Jantar criança');
    await tester.enterText(fields.last, '5');
    await tester.tap(find.text('Conta como refeição de jantar'));
    await tester
        .tap(find.descendant(of: dialog, matching: find.text('Guardar')));
    await tester.pumpAndSettle();
    final preset =
        (await bar.presets()).singleWhere((p) => p['name'] == 'Jantar criança');
    expect(preset['counts_as_dinner_meal'], isTrue);
    expect(preset['unit_price'], 5);
    expect(tester.takeException(), isNull);
  });
  test('excluded positive revenue blocks demo close until explicitly corrected',
      () async {
    final id = await dinner();
    final sale = await bar.createDraft(weeklyDinnerId: id);
    await bar.completeSale(
        saleId: sale,
        weeklyDinnerId: id,
        paymentMethod: 'cash',
        lines: const [
          {
            'kind': 'other',
            'description': 'Receita sem classificação',
            'quantity': 1,
            'unit_price': 5
          }
        ]);
    final value = await repo.detail(id);
    expect(value.number('excluded_revenue'), 5);
    expect(value.number('excluded_line_count'), 1);
    expect(value.number('total_revenue'), 0);
    await expectLater(
        repo.setClosed(id, true),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('vendas do BAR por classificar'))));
    expect((await repo.detail(id)).rows('previous_snapshots'), isEmpty);
    // Explicitly correcting the association is allowed; no arbitrary relabeling.
    await repo.assignSale(id, sale, remove: true);
    expect((await repo.detail(id)).number('excluded_revenue'), 0);
    expect((await repo.setClosed(id, true)).closed, isTrue);
  });
  test(
      'zero-valued excluded lines are counted but do not represent missing revenue',
      () {
    final value = WeeklyDinnerFinance.calculate(lines: const [
      {'dinner_component_snapshot': 'excluded', 'line_total': 0}
    ], expenses: const []);
    expect(value.number('excluded_line_count'), 1);
    expect(value.hasUnclassifiedRevenue, isFalse);
  });
  testWidgets('unclassified revenue is visible and financial close is disabled',
      (tester) async {
    final repository = PanelRepo();
    await panel(tester, repository);
    expect(find.text('Receita por classificar'), findsOneWidget);
    final line = find.ancestor(
        of: find.text('Receita por classificar'),
        matching: find.byType(ListTile));
    expect(find.descendant(of: line, matching: find.textContaining('4,00')),
        findsOneWidget);
    expect(
        find.text(
            'Existem vendas do BAR por classificar neste jantar. Classifica ou corrige essas vendas antes de fechar financeiramente.'),
        findsOneWidget);
    await tester.scrollUntilVisible(find.text('Fechar financeiramente'), 400,
        scrollable: find.byType(Scrollable).first);
    final button = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Fechar financeiramente'),
        matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
    expect(repository.value.number('total_revenue'), 120);
    expect(repository.value.number('result'), 79);
    expect(tester.takeException(), isNull);
  });
  test(
      'line override leaves original sale untouched, supports undo and rejects invalid contexts',
      () async {
    final mixed = await mixedDinner();
    final id = mixed['dinner'] as String;
    final original = Map<String, dynamic>.from(mixed['item'] as Map);
    final itemId = original['id'].toString();
    await expectLater(repo.setClosed(id, true), throwsStateError);
    await expectLater(
        repo.classifySaleItem(id, itemId, component: 'bar'), throwsStateError);
    await expectLater(
        repo.classifySaleItem(await dinner(inClub: 'foreign'), itemId,
            component: 'meal'),
        throwsStateError);
    await expectLater(
        repo.classifySaleItem(await dinner(), itemId, component: 'meal'),
        throwsStateError);
    await repo.classifySaleItem(id, itemId, component: 'meal');
    var result = await repo.detail(id);
    expect(result.number('meal_quantity'), 4);
    expect(result.number('meal_revenue'), 25);
    expect(result.number('beverage_revenue'), 20);
    expect(result.number('beverage_cost'), 6);
    expect(result.number('excluded_revenue'), 0);
    expect(result.number('total_revenue'), 45);
    expect(await data.getById('bar_sale_items', itemId), original);
    await repo.classifySaleItem(id, itemId);
    result = await repo.detail(id);
    expect(result.hasUnclassifiedRevenue, isTrue);
    expect(result.number('meal_revenue'), 20);
    await expectLater(repo.setClosed(id, true), throwsStateError);
    await repo.classifySaleItem(id, itemId, component: 'meal');
    final closed = await repo.setClosed(id, true);
    expect(closed.number('result'), 39);
    await expectLater(repo.classifySaleItem(id, itemId), throwsStateError);
    expect((await repo.detail(id)).number('result'), 39);
    AppSession.instance.applyPermissions(['viewFinancialReports']);
    await expectLater(
        repo.classifySaleItem(id, itemId, component: 'meal'), throwsStateError);
  });
  testWidgets(
      'mixed sale line can be classified and undone with immediate totals and closing state',
      (tester) async {
    final mixed = await mixedDinner();
    final id = mixed['dinner'] as String;
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WeeklyDinnerFinanceDialog(
                dinner: {'id': id, 'dish': 'Jantar'}, repository: repo))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sobremesa · 2 ×'), findsOneWidget);
    expect(find.textContaining('2,50'), findsWidgets);
    expect(find.text('Receita por classificar'), findsOneWidget);
    await tester.tap(find.text('Classificar como refeição'));
    await tester.pumpAndSettle();
    expect(find.text('Receita por classificar'), findsNothing);
    expect(find.text('Desfazer classificação'), findsOneWidget);
    expect((await repo.detail(id)).number('meal_revenue'), 25);
    expect((await repo.detail(id)).number('excluded_revenue'), 0);
    await tester.scrollUntilVisible(find.text('Fechar financeiramente'), 400,
        scrollable: find.byType(Scrollable).first);
    FilledButton closeButton() => tester.widget<FilledButton>(find.ancestor(
        of: find.text('Fechar financeiramente'),
        matching: find.byType(FilledButton)));
    expect(closeButton().onPressed, isNotNull);
    await tester.scrollUntilVisible(find.text('Desfazer classificação'), -400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Desfazer classificação'));
    await tester.pumpAndSettle();
    expect(find.text('Receita por classificar'), findsOneWidget);
    expect((await repo.detail(id)).number('meal_revenue'), 20);
    await tester.scrollUntilVisible(find.text('Fechar financeiramente'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(closeButton().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'read-only financial user sees lines but no classification actions',
      (tester) async {
    final mixed = await mixedDinner();
    final id = mixed['dinner'] as String;
    AppSession.instance.applyPermissions(['viewFinancialReports']);
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WeeklyDinnerFinanceDialog(
                dinner: {'id': id}, repository: repo))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sobremesa · 2 ×'), findsOneWidget);
    expect(find.text('Classificar como refeição'), findsNothing);
    expect(find.text('Desfazer classificação'), findsNothing);
    expect(find.text('Fechar financeiramente'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'closed panel uses Portuguese cost labels, sale value/date and formatted history',
      (tester) async {
    final repository = PanelRepo()
      ..value = const WeeklyDinnerFinance({
        'financial_status': 'closed',
        'closed_at': '2026-10-15T20:30:00',
        'revision': 1,
        'meal_mode': 'automatic',
        'meal_revenue': 25,
        'total_revenue': 45,
        'result': 39,
        'expense_links': [
          {
            'description': 'Compra de comida',
            'cost_kind': 'food',
            'amount': 10
          },
          {'description': 'Transportes', 'cost_kind': 'other', 'amount': 2},
        ],
        'sales': [
          {
            'customer_label': 'Venda mista',
            'total_amount': 45,
            'completed_at': '2026-10-15T20:30:00'
          }
        ],
        'classification_lines': [
          {
            'sale_item_id': 'dessert',
            'description': 'Sobremesa',
            'quantity': 2,
            'unit_price': 2.5,
            'line_total': 5,
            'component_override': 'meal',
            'effective_component': 'meal'
          }
        ],
        'previous_snapshots': [
          {
            'revision': 1,
            'closed_at': '2026-10-15T20:30:00',
            'snapshot': {'result': 39}
          }
        ],
      });
    await panel(tester, repository, size: const Size(1100, 1800));
    expect(
        find.text('Fechado em 15/10/2026 20:30 · Revisão 1'), findsOneWidget);
    expect(find.textContaining('Comida/preparação ·'), findsOneWidget);
    expect(find.textContaining('Outros custos ·'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Venda mista'), 400,
        scrollable: find.byType(Scrollable).first);
    final sale = find.ancestor(
        of: find.text('Venda mista'), matching: find.byType(ListTile));
    expect(find.descendant(of: sale, matching: find.textContaining('45,00')),
        findsOneWidget);
    expect(
        find.descendant(
            of: sale, matching: find.textContaining('15/10/2026 20:30')),
        findsOneWidget);
    expect(find.text('Classificar como refeição'), findsNothing);
    expect(find.text('Desfazer classificação'), findsNothing);
    await tester.scrollUntilVisible(
        find.text('Histórico de fechos preservados'), 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Histórico de fechos preservados'));
    await tester.pumpAndSettle();
    expect(find.text('Revisão 1 · 15/10/2026 20:30'), findsOneWidget);
    expect(find.textContaining('2026-10-15T'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
      'manual writes rejected; historical snapshot survives reopen and BAR-only reclose',
      () async {
    final id = await dinner();
    const historic = <String, dynamic>{
      'meal_quantity': 10,
      'meal_revenue': 100,
      'total_revenue': 100,
      'food_cost': 40,
      'other_costs': 10,
      'total_cost': 50,
      'result': 50,
      'margin_percent': 50
    };
    await data.insert('weekly_dinner_finances', {
      'club_id': club,
      'dinner_id': id,
      'financial_status': 'closed',
      'meal_mode': 'manual',
      'manual_meal_quantity': 10,
      'manual_meal_revenue': 100,
      'food_cost_manual': 40,
      'other_cost_manual': 10,
      'revision': 1,
      'snapshot': historic
    });
    await data.insert('weekly_dinner_financial_snapshots', {
      'club_id': club,
      'dinner_id': id,
      'revision': 1,
      'snapshot': historic
    });
    expect((await repo.detail(id)).number('meal_revenue'), 100);
    await repo.setClosed(id, false);
    expect((await repo.detail(id)).number('meal_revenue'), 0);
    expect((await repo.detail(id)).number('result'), -50);
    for (final args in [
      ('manual', 0.0, 0.0),
      ('automatic', 1.0, 0.0),
      ('automatic', 0.0, 100.0)
    ]) {
      await expectLater(
          repo.save(id,
              mode: args.$1,
              quantity: args.$2,
              revenue: args.$3,
              food: 40,
              other: 10),
          throwsArgumentError);
    }
    final preset = await data.insert('bar_sale_presets', {
      'club_id': club,
      'name': 'Jantar',
      'active': true,
      'unit_price': 10,
      'counts_as_dinner_meal': true
    });
    for (final actor in ['one', 'two']) {
      AppSession.instance.profileId = actor;
      final sale = await bar.createDraft(weeklyDinnerId: id);
      await bar.completeSale(
          saleId: sale,
          paymentMethod: 'cash',
          weeklyDinnerId: id,
          lines: [
            {'kind': 'preset', 'preset_id': preset['id'], 'quantity': 2}
          ]);
    }
    expect((await repo.detail(id)).number('meal_quantity'), 4);
    expect((await repo.detail(id)).number('meal_revenue'), 40);
    await repo.setClosed(id, true);
    final revisionOne = (await repo.detail(id))
        .rows('previous_snapshots')
        .firstWhere((r) => r['revision'] == 1);
    expect(revisionOne['snapshot'], historic);
  });
  testWidgets(
      'financial panel explains BAR-only meals and has no manual revenue controls',
      (tester) async {
    await panel(tester, PanelRepo());
    await tester.scrollUntilVisible(
        find.textContaining('calculadas exclusivamente'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('calculadas exclusivamente'), findsOneWidget);
    expect(find.text('Automático pelo BAR'), findsNothing);
    expect(find.text('Manual (substitui o automático)'), findsNothing);
    expect(find.widgetWithText(TextField, 'Quantidade de refeições'),
        findsNothing);
    expect(
        find.widgetWithText(TextField, 'Receita das refeições'), findsNothing);
    expect(
        find.widgetWithText(
            TextField, 'Comida/preparação — ajuste manual adicional'),
        findsOneWidget);
  });
}
