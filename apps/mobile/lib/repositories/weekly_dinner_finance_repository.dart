import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../models/weekly_dinner_finance.dart';
import '../services/data_service.dart';

class WeeklyDinnerFinanceRepository {
  WeeklyDinnerFinanceRepository(
      {SupabaseClient? client, DataService? dataService})
      : _client = client,
        _data = dataService ?? DataService.instance;
  final SupabaseClient? _client;
  final DataService _data;
  bool get demo => _client == null && AppConfig.demoMode;
  String get club => AppSession.instance.clubId;
  SupabaseClient get client => _client ?? Supabase.instance.client;
  bool get canRead =>
      AppSession.instance.can(AppPermission.viewFinancialReports);
  bool get canManage =>
      canRead && AppSession.instance.can(AppPermission.approveExpenseRequests);
  void require({bool write = false}) {
    if (!canRead || (write && !canManage)) {
      throw StateError('Sem autorização financeira.');
    }
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) =>
      client.rpc(name, params: {'target_club': club, ...params});
  Future<List<Map<String, dynamic>>> _list(String table) async =>
      (await _data.list(table)).where((row) => row['club_id'] == club).toList();
  Future<void> _dinner(String id) async {
    if (!(await _list('weekly_dinners')).any((row) => row['id'] == id)) {
      throw StateError('Jantar não encontrado neste clube.');
    }
  }

  /// Demo shares the existing DataService store with the roster and BAR.
  static final Map<String, Future<void>> _seeding = {};
  static Future<void> seedDemo() {
    if (!AppConfig.demoMode) return Future.value();
    final club = AppSession.instance.clubId;
    return _seeding.putIfAbsent(club, () => _seedDemo(club));
  }

  static Future<void> _seedDemo(String club) async {
    if (!AppConfig.demoMode) return;
    final data = DataService.instance;
    if ((await data.list('weekly_dinners'))
        .any((row) => row['club_id'] == club)) {
      return;
    }
    final now = DateTime.now();
    final id = await data.insert('weekly_dinners', {
      'club_id': club,
      'dinner_date':
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'dinner_kind':
          now.weekday == DateTime.thursday ? 'regular' : 'extraordinary',
      'status': 'planned',
      'dish': 'Feijoada (Demo)',
      'external_name': 'Oficial Demo',
    });
    final preset = await data.insert('bar_sale_presets', {
      'club_id': club,
      'name': 'Jantar membro',
      'unit_price': 10,
      'active': true,
      'counts_as_dinner_meal': true
    });
    final product = await data.insert('products', {
      'club_id': club,
      'name': 'Cerveja Demo',
      'inventory_area': 'bar',
      'cost': .6,
      'current_stock': 40,
      'reserved_stock': 0,
      'minimum_stock': 5,
      'active': true,
      'consumption_unit': 'unid.',
      'sale_options': [
        {
          'id': 'demo-beer-unit',
          'name': 'Unidade',
          'stock_quantity': 1,
          'public_price': 2,
          'member_price': 1.5
        }
      ]
    });
    final account = await data.insert('financial_accounts', {
      'club_id': club,
      'name': 'Caixa BAR Demo',
      'active': true,
      'opening_balance': 0,
    });
    final tx = await data.insert('financial_transactions', {
      'club_id': club,
      'kind': 'income',
      'amount': 120,
      'account_id': account['id'],
      'description': 'Venda de jantar Demo',
      'source_type': 'bar_sale',
      'transaction_date': now.toIso8601String(),
    });
    final sale = await data.insert('bar_sales', {
      'club_id': club,
      'weekly_dinner_id': id['id'],
      'status': 'completed',
      'customer_label': 'Venda Demo',
      'treasury_transaction_id': tx['id'],
      'completed_at': now.toUtc().toIso8601String(),
      'total_amount': 120
    });
    await data.insert('bar_sale_items', {
      'club_id': club,
      'sale_id': sale['id'],
      'item_kind': 'preset',
      'preset_id': preset['id'],
      'quantity': 10,
      'line_total': 100,
      'dinner_component_snapshot': 'meal'
    });
    await data.insert('bar_sale_items', {
      'club_id': club,
      'sale_id': sale['id'],
      'item_kind': 'stock',
      'product_id': product['id'],
      'quantity': 10,
      'stock_quantity_per_unit': 1,
      'line_total': 20,
      'dinner_component_snapshot': 'bar',
      'unit_cost_snapshot': .6,
      'cost_total_snapshot': 6
    });
    await data.insert('stock_movements', {
      'club_id': club,
      'product_id': product['id'],
      'kind': 'sale',
      'quantity': -10,
      'unit_cost': .6,
    });
    await data.insert('bar_operations', {
      'club_id': club,
      'product_id': product['id'],
      'products': product,
      'operation_type': 'sale',
      'consumption_quantity': 10,
      'total_amount': 20,
      'sale_id': sale['id'],
      'treasury_transaction_id': tx['id'],
    });
  }

  Future<WeeklyDinnerFinance> detail(String dinnerId) async {
    require();
    if (!demo) {
      return WeeklyDinnerFinance(Map<String, dynamic>.from(
          await _rpc('weekly_dinner_finance_v1', {'p_dinner': dinnerId})
              as Map));
    }
    await _dinner(dinnerId);
    final finances = (await _list('weekly_dinner_finances'))
        .where((row) => row['dinner_id'] == dinnerId);
    final settings = finances.isEmpty
        ? <String, dynamic>{
            'financial_status': 'none',
            'meal_mode': 'automatic'
          }
        : finances.first;
    final revisions = (await _list('weekly_dinner_financial_snapshots'))
        .where((row) => row['dinner_id'] == dinnerId)
        .toList();
    if (settings['financial_status'] == 'closed') {
      return WeeklyDinnerFinance({
        ...Map<String, dynamic>.from(settings['snapshot'] as Map),
        ...settings,
        'previous_snapshots': revisions
      });
    }
    final sales = (await _list('bar_sales'))
        .where((row) =>
            row['weekly_dinner_id'] == dinnerId && row['status'] == 'completed')
        .toList();
    final saleIds = sales.map((row) => row['id']).toSet();
    final overrides = (await _list('weekly_dinner_sale_item_classifications'))
        .where((c) => c['dinner_id'] == dinnerId);
    final lines = (await _list('bar_sale_items'))
        .where((row) => saleIds.contains(row['sale_id']))
        .map((row) {
      final matches = overrides.where((c) => c['sale_item_id'] == row['id']);
      return <String, dynamic>{
        ...row,
        if (matches.isNotEmpty)
          'component_override': matches.first['component_override']
      };
    }).toList();
    final transactions = await _data.list('financial_transactions');
    final links = (await _list('weekly_dinner_expenses'))
        .where((row) => row['dinner_id'] == dinnerId);
    final expenses = <Map<String, dynamic>>[];
    for (final link in links) {
      final tx = transactions.where((row) =>
          row['id'] == link['transaction_id'] && row['club_id'] == club);
      if (tx.isEmpty) continue;
      expenses.add({
        ...tx.first,
        ...link,
        'reversed': transactions.any((row) =>
            row['club_id'] == club && row['reversal_of'] == tx.first['id'])
      });
    }
    final result = WeeklyDinnerFinance.calculate(
        lines: lines, expenses: expenses, settings: settings);
    return WeeklyDinnerFinance({
      ...result.data,
      'dinner_id': dinnerId,
      'sales': sales,
      'previous_snapshots': revisions
    });
  }

  Future<void> save(String id,
      {required String mode,
      required double quantity,
      required double revenue,
      required double food,
      required double other,
      String notes = ''}) async {
    require(write: true);
    if (!['automatic', 'manual'].contains(mode) ||
        [quantity, revenue, food, other].any((v) => !v.isFinite || v < 0)) {
      throw ArgumentError('Valores financeiros inválidos.');
    }
    if (!demo) {
      await _rpc('save_weekly_dinner_finance_v1', {
        'p_dinner': id,
        'p_meal_mode': mode,
        'p_meal_quantity': quantity,
        'p_meal_revenue': revenue,
        'p_food_cost': food,
        'p_other_cost': other,
        'p_notes': notes
      });
      return;
    }
    final current = await detail(id);
    if (current.closed) throw StateError('Reabre o fecho financeiro.');
    final existing = (await _list('weekly_dinner_finances'))
        .where((r) => r['dinner_id'] == id);
    final values = {
      'club_id': club,
      'dinner_id': id,
      'financial_status': 'open',
      'meal_mode': mode,
      'manual_meal_quantity': quantity,
      'manual_meal_revenue': revenue,
      'food_cost_manual': food,
      'other_cost_manual': other,
      'notes': notes,
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toIso8601String()
    };
    if (existing.isEmpty) {
      await _data.insert('weekly_dinner_finances', values);
    } else {
      await _data.update(
          'weekly_dinner_finances', existing.first['id'].toString(), values);
    }
  }

  Future<WeeklyDinnerFinance> setClosed(String id, bool closed) async {
    require(write: true);
    if (!demo) {
      return WeeklyDinnerFinance(Map<String, dynamic>.from(await _rpc(
          'set_weekly_dinner_financial_closed_v1',
          {'p_dinner': id, 'p_closed': closed}) as Map));
    }
    final current = await detail(id);
    if (closed == current.closed) return current;
    if (closed && current.hasUnclassifiedRevenue) {
      throw StateError(
          'Existem vendas do BAR por classificar neste jantar. Classifica ou corrige essas vendas antes de fechar financeiramente.');
    }
    if (closed && !current.hasCosts) {
      throw StateError('Custos históricos em falta.');
    }
    if (closed &&
        (await _list('bar_sales')).any(
            (s) => s['weekly_dinner_id'] == id && s['status'] == 'draft')) {
      throw StateError('Existem vendas em rascunho.');
    }
    var records = (await _list('weekly_dinner_finances'))
        .where((r) => r['dinner_id'] == id);
    if (records.isEmpty) {
      await save(id,
          mode: 'automatic', quantity: 0, revenue: 0, food: 0, other: 0);
      records = (await _list('weekly_dinner_finances'))
          .where((r) => r['dinner_id'] == id);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final revision = (records.first['revision'] as num? ?? 0).toInt() + 1;
    if (closed) {
      await _data.insert('weekly_dinner_financial_snapshots', {
        'club_id': club,
        'dinner_id': id,
        'revision': revision,
        'snapshot': Map<String, dynamic>.from(current.data),
        'closed_at': now,
        'closed_by': AppSession.instance.profileId
      });
    }
    await _data
        .update('weekly_dinner_finances', records.first['id'].toString(), {
      'financial_status': closed ? 'closed' : 'open',
      'updated_at': now,
      'updated_by': AppSession.instance.profileId,
      if (closed) ...{
        'snapshot': Map<String, dynamic>.from(current.data),
        'closed_at': now,
        'closed_by': AppSession.instance.profileId,
        'revision': revision
      }
    });
    return detail(id);
  }

  Future<Map<String, dynamic>> history(int year) async {
    require();
    if (!demo) {
      return Map<String, dynamic>.from(
          await _rpc('weekly_dinner_financial_history_v1', {'p_year': year})
              as Map);
    }
    final dinners = (await _list('weekly_dinners'))
        .where((r) => DateTime.parse(r['dinner_date'].toString()).year == year);
    final rows = <Map<String, dynamic>>[];
    for (final dinner in dinners) {
      final finance = await detail(dinner['id'].toString());
      rows.add({
        ...dinner,
        'financial_status': finance.data['financial_status'],
        'summary': finance.closed ? finance.data : null
      });
    }
    return WeeklyDinnerFinance.annual(rows);
  }

  Future<Map<String, dynamic>> choices(String id) async {
    require(write: true);
    if (!demo) {
      return Map<String, dynamic>.from(
          await _rpc('weekly_dinner_finance_choices_v1', {'p_dinner': id})
              as Map);
    }
    await _dinner(id);
    final links = await _list('weekly_dinner_expenses');
    final transactions = await _list('financial_transactions');
    return {
      'expenses': transactions
          .where((t) =>
              t['kind'] == 'expense' &&
              t['reversal_of'] == null &&
              !transactions.any((r) => r['reversal_of'] == t['id']) &&
              !links.any((r) => r['transaction_id'] == t['id']) &&
              !dinnerStockPurchase(t['source_type']))
          .toList(),
      'sales': (await _list('bar_sales'))
          .where((r) =>
              r['status'] == 'completed' && r['weekly_dinner_id'] == null)
          .toList()
    };
  }

  Future<void> linkExpense(String id, String transaction, String kind,
      {bool remove = false}) async {
    require(write: true);
    if (!demo) {
      await _rpc('link_weekly_dinner_expense_v1', {
        'p_dinner': id,
        'p_transaction': transaction,
        'p_kind': kind,
        'p_remove': remove
      });
      return;
    }
    final current = await detail(id);
    if (current.closed) throw StateError('Reabre o fecho financeiro.');
    final links = await _list('weekly_dinner_expenses');
    if (remove) {
      for (final link in links.where(
          (r) => r['dinner_id'] == id && r['transaction_id'] == transaction)) {
        await _data.delete('weekly_dinner_expenses', link['id'].toString());
      }
      return;
    }
    if (!['food', 'other'].contains(kind)) {
      throw ArgumentError('Tipo de custo inválido.');
    }
    final choicesData = await choices(id);
    if (!(choicesData['expenses'] as List).any((r) => r['id'] == transaction)) {
      throw StateError('Despesa inválida ou já ligada.');
    }
    await _data.insert('weekly_dinner_expenses', {
      'club_id': club,
      'dinner_id': id,
      'transaction_id': transaction,
      'cost_kind': kind
    });
  }

  Future<void> classifySaleItem(String dinnerId, String itemId,
      {String? component}) async {
    require(write: true);
    if (!demo) {
      await _rpc('classify_weekly_dinner_sale_item_v1', {
        'p_dinner': dinnerId,
        'p_sale_item': itemId,
        'p_component': component
      });
      return;
    }
    final current = await detail(dinnerId);
    if (current.closed) {
      throw StateError(
          'Reabre o fecho financeiro antes de alterar classificações.');
    }
    final saleIds = current.rows('sales').map((sale) => sale['id']).toSet();
    final matches = (await _list('bar_sale_items')).where(
        (line) => line['id'] == itemId && saleIds.contains(line['sale_id']));
    if (matches.isEmpty) {
      throw StateError('Linha de venda não encontrada neste jantar.');
    }
    final line = matches.first;
    if (line['dinner_component_snapshot'] != 'excluded' ||
        dinnerNumber(line['line_total']) <= 0) {
      throw StateError(
          'Apenas receita originalmente por classificar pode ser corrigida.');
    }
    final overrides = (await _list('weekly_dinner_sale_item_classifications'))
        .where(
            (c) => c['dinner_id'] == dinnerId && c['sale_item_id'] == itemId);
    if (component == null) {
      for (final row in overrides) {
        await _data.delete(
            'weekly_dinner_sale_item_classifications', row['id'].toString());
      }
      return;
    }
    if (!['meal', 'bar'].contains(component)) {
      throw ArgumentError('Classificação financeira inválida.');
    }
    if (component == 'bar' &&
        (line['cost_total_snapshot'] == null ||
            !dinnerNumber(line['cost_total_snapshot']).isFinite ||
            dinnerNumber(line['cost_total_snapshot']) < 0)) {
      throw StateError(
          'Não é possível classificar como BAR sem custo histórico de stock fiável.');
    }
    final values = {
      'club_id': club,
      'dinner_id': dinnerId,
      'sale_item_id': itemId,
      'component_override': component,
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toUtc().toIso8601String()
    };
    if (overrides.isEmpty) {
      await _data.insert('weekly_dinner_sale_item_classifications',
          {...values, 'created_by': AppSession.instance.profileId});
    } else {
      await _data.update('weekly_dinner_sale_item_classifications',
          overrides.first['id'].toString(), values);
    }
  }

  Future<void> assignSale(String id, String sale, {bool remove = false}) async {
    require(write: true);
    if (!demo) {
      await _rpc('assign_bar_sale_dinner_v1',
          {'p_sale': sale, 'p_dinner': remove ? null : id});
      return;
    }
    final current = await detail(id);
    if (current.closed) throw StateError('Reabre o fecho financeiro.');
    final sales = (await _list('bar_sales'))
        .where((r) => r['id'] == sale && r['status'] == 'completed');
    if (sales.isEmpty || (remove && sales.first['weekly_dinner_id'] != id)) {
      throw StateError('Venda inválida.');
    }
    final previous = sales.first['weekly_dinner_id'];
    if (previous != null && (await detail(previous.toString())).closed) {
      throw StateError('Jantar anterior fechado.');
    }
    await _data
        .update('bar_sales', sale, {'weekly_dinner_id': remove ? null : id});
  }
}

bool dinnerStockPurchase(Object? source) => const [
      'bar',
      'bar_purchase',
      'bar_operation',
      'inventory',
      'stock_purchase'
    ].contains(source);
