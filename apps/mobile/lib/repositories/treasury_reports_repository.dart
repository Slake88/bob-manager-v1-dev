import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../services/data_service.dart';
import 'treasury_repository.dart';

class TreasuryReportData {
  const TreasuryReportData({
    required this.movements,
    required this.accounts,
    required this.costCenters,
    required this.openingBalance,
    required this.closingBalance,
    required this.income,
    required this.expense,
    required this.monthly,
  });

  final List<Map<String, dynamic>> movements;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> costCenters;
  final double openingBalance;
  final double closingBalance;
  final double income;
  final double expense;
  final List<TreasuryMonthlyPoint> monthly;

  double get result => income - expense;
}

class TreasuryMonthlyPoint {
  const TreasuryMonthlyPoint(this.year, this.month, this.income, this.expense);
  final int year;
  final int month;
  final double income;
  final double expense;
  double get result => income - expense;
}

class TreasuryReportsRepository {
  TreasuryReportsRepository({SupabaseClient? client, DataService? dataService})
      : _client = client,
        _dataService = dataService ?? DataService.instance;

  final SupabaseClient? _client;
  final DataService _dataService;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  final TreasuryRepository _treasury = TreasuryRepository();

  Future<TreasuryReportData> load({
    required DateTime from,
    required DateTime to,
    String? accountId,
    String? costCenterId,
    String? kind,
  }) async {
    final accounts = await _treasury.listAccounts();
    final costCenters = await _treasury.listCostCenters();
    final allToDate = await _transactionsUntil(to);

    final periodRows = allToDate.where((row) {
      final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      if (date == null || date.isBefore(_dateOnly(from))) return false;
      if (!_matchesFilters(row, accountId, costCenterId, kind)) return false;
      return true;
    }).toList();

    final beforeRows = allToDate.where((row) {
      final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      if (date == null || !date.isBefore(_dateOnly(from))) return false;
      return _matchesFilters(row, accountId, costCenterId, kind);
    }).toList();

    final opening = _net(beforeRows);
    final income = periodRows
        .where((row) => row['kind'] == 'income')
        .fold<double>(0, (sum, row) => sum + _num(row['amount']));
    final expense = periodRows
        .where((row) => row['kind'] == 'expense')
        .fold<double>(0, (sum, row) => sum + _num(row['amount']));

    final monthlyMap = <String, List<double>>{};
    for (final row in periodRows) {
      final date = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
      if (date == null) continue;
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final values = monthlyMap.putIfAbsent(key, () => [0, 0]);
      if (row['kind'] == 'income') values[0] += _num(row['amount']);
      if (row['kind'] == 'expense') values[1] += _num(row['amount']);
    }
    final monthly = monthlyMap.entries.map((entry) {
      final parts = entry.key.split('-');
      return TreasuryMonthlyPoint(
        int.parse(parts[0]),
        int.parse(parts[1]),
        entry.value[0],
        entry.value[1],
      );
    }).toList()
      ..sort((a, b) => a.year != b.year
          ? a.year.compareTo(b.year)
          : a.month.compareTo(b.month));

    periodRows.sort((a, b) {
      final date = (b['transaction_date']?.toString() ?? '')
          .compareTo(a['transaction_date']?.toString() ?? '');
      if (date != 0) return date;
      return (b['created_at']?.toString() ?? '')
          .compareTo(a['created_at']?.toString() ?? '');
    });

    return TreasuryReportData(
      movements: periodRows,
      accounts: accounts,
      costCenters: costCenters,
      openingBalance: opening,
      closingBalance: opening + income - expense,
      income: income,
      expense: expense,
      monthly: monthly,
    );
  }

  bool _matchesFilters(
    Map<String, dynamic> row,
    String? accountId,
    String? costCenterId,
    String? kind,
  ) {
    if (kind != null && kind.isNotEmpty && row['kind']?.toString() != kind) {
      return false;
    }
    if (costCenterId != null &&
        costCenterId.isNotEmpty &&
        row['cost_center_id']?.toString() != costCenterId) {
      return false;
    }
    if (accountId != null && accountId.isNotEmpty) {
      final source = row['account_id']?.toString();
      final destination = row['destination_account_id']?.toString();
      if (source != accountId && destination != accountId) return false;
    }
    return true;
  }

  double _net(Iterable<Map<String, dynamic>> rows) {
    var value = 0.0;
    for (final row in rows) {
      final amount = _num(row['amount']);
      if (row['kind'] == 'income') value += amount;
      if (row['kind'] == 'expense') value -= amount;
    }
    return value;
  }

  Future<List<Map<String, dynamic>>> _transactionsUntil(DateTime to) async {
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('financial_transactions');
      return rows.where((row) {
        final d = DateTime.tryParse(row['transaction_date']?.toString() ?? '');
        return d != null && !d.isAfter(_dateOnly(to));
      }).toList();
    }

    final result = <Map<String, dynamic>>[];
    const pageSize = 1000;
    var start = 0;
    while (true) {
      final response = await _supabase
          .from('treasury_transactions')
          .select(
            '*, source_account:treasury_accounts!treasury_transactions_account_id_fkey(name), destination_account:treasury_accounts!treasury_transactions_destination_account_id_fkey(name), cost_center:cost_centers(name)',
          )
          .eq('club_id', AppSession.instance.clubId)
          .lte('transaction_date', _isoDate(to))
          .order('transaction_date', ascending: true)
          .range(start, start + pageSize - 1);
      final page = List<Map<String, dynamic>>.from(response).map((row) {
        final source = row['source_account'];
        final destination = row['destination_account'];
        final costCenter = row['cost_center'];
        return <String, dynamic>{
          ...row,
          'account_name': source is Map ? source['name'] : null,
          'destination_account_name':
              destination is Map ? destination['name'] : null,
          'cost_center_name': costCenter is Map ? costCenter['name'] : null,
        };
      }).toList();
      result.addAll(page);
      if (page.length < pageSize) break;
      start += pageSize;
    }
    return result;
  }
}

double _num(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;
DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);
String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
