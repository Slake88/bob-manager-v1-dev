import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import 'data_service.dart';

extension Rc1DataServiceExtensions on DataService {
  Future<List<Map<String, dynamic>>> listWhere(
    String table, {
    required String field,
    required Object value,
    int limit = 250,
  }) async {
    final rows = await list(table, limit: limit);
    return rows
        .where((row) => row[field]?.toString() == value.toString())
        .map(Map<String, dynamic>.from)
        .toList();
  }

  Future<Map<String, dynamic>> treasurySummary() async {
    if (!AppConfig.demoMode) {
      final response = await Supabase.instance.client.rpc(
        'treasury_summary_accounts_only',
        params: {'target_club': AppSession.instance.clubId},
      );
      return Map<String, dynamic>.from(response as Map);
    }

    final storedAccounts = await list('financial_accounts');
    final accounts = (storedAccounts.isEmpty ? _defaultAccounts : storedAccounts)
        .map(Map<String, dynamic>.from)
        .toList()
      ..sort((a, b) => _asInt(a['display_order']).compareTo(_asInt(b['display_order'])));
    final transactions = await list('financial_transactions');

    for (final account in accounts) {
      account['balance'] = _accountBalance(
        account['id'].toString(),
        account,
        transactions,
      );
    }

    final now = DateTime.now();
    var monthlyIncome = 0.0;
    var monthlyExpense = 0.0;
    for (final transaction in transactions) {
      final date = DateTime.tryParse(
        transaction['transaction_date']?.toString() ?? '',
      );
      if (date == null || date.year != now.year || date.month != now.month) {
        continue;
      }
      final amount = _asDouble(transaction['amount']);
      if (transaction['kind'] == 'income') monthlyIncome += amount;
      if (transaction['kind'] == 'expense') monthlyExpense += amount;
    }

    final requests = await list('expense_requests');
    final pendingApprovals = requests.where((row) {
      final status = row['status']?.toString();
      return status == 'submitted' || status == 'review';
    }).length;

    final recent = transactions.map(Map<String, dynamic>.from).toList()
      ..sort(
        (a, b) => (b['transaction_date']?.toString() ?? '')
            .compareTo(a['transaction_date']?.toString() ?? ''),
      );

    return {
      'accounts': accounts,
      'total_balance': accounts.fold<double>(
        0,
        (total, account) => total + _asDouble(account['balance']),
      ),
      'monthly_income': monthlyIncome,
      'monthly_expense': monthlyExpense,
      'pending_approvals': pendingApprovals,
      'recent_transactions': recent.take(8).toList(),
    };
  }

  Future<void> transferBetweenAccounts({
    required String sourceAccountId,
    required String destinationAccountId,
    required double amount,
    required String description,
  }) async {
    if (sourceAccountId == destinationAccountId) {
      throw ArgumentError(
        'As contas de origem e destino têm de ser diferentes.',
      );
    }
    if (amount <= 0) {
      throw ArgumentError('O valor deve ser superior a zero.');
    }

    if (!AppConfig.demoMode) {
      await Supabase.instance.client.rpc(
        'transfer_between_accounts',
        params: {
          'target_club': AppSession.instance.clubId,
          'source_account': sourceAccountId,
          'destination_account': destinationAccountId,
          'transfer_amount': amount,
          'transfer_description': description,
        },
      );
      return;
    }

    final summary = await treasurySummary();
    final accounts = List<Map<String, dynamic>>.from(
      summary['accounts'] as List<dynamic>? ?? const [],
    );
    final source = accounts.firstWhere(
      (account) => account['id']?.toString() == sourceAccountId,
      orElse: () => throw StateError('Conta de origem não encontrada.'),
    );
    final destination = accounts.firstWhere(
      (account) => account['id']?.toString() == destinationAccountId,
      orElse: () => throw StateError('Conta de destino não encontrada.'),
    );
    final sourceBalance = _asDouble(source['balance']);
    if (source['allows_negative'] != true && sourceBalance < amount) {
      throw StateError(
        'Saldo insuficiente na conta ${source['name']}. '
        'Saldo atual: ${sourceBalance.toStringAsFixed(2)} €.',
      );
    }

    await insert('financial_transactions', {
      'transaction_date': DateTime.now().toIso8601String().split('T').first,
      'kind': 'transfer',
      'status': 'confirmed',
      'description': description.trim().isEmpty
          ? 'Transferência entre contas'
          : description.trim(),
      'amount': amount,
      'account_id': sourceAccountId,
      'account_name': source['name'],
      'destination_account_id': destinationAccountId,
      'destination_account_name': destination['name'],
      'created_by': AppSession.instance.profileId,
    });
  }
}

double _accountBalance(
  String accountId,
  Map<String, dynamic> account,
  List<Map<String, dynamic>> transactions,
) {
  var balance = _asDouble(account['opening_balance']);
  for (final transaction in transactions) {
    final amount = _asDouble(transaction['amount']);
    final kind = transaction['kind']?.toString();
    final sourceId = transaction['account_id']?.toString();
    final destinationId = transaction['destination_account_id']?.toString();

    if (sourceId == accountId) {
      if (kind == 'expense' || kind == 'transfer') {
        balance -= amount;
      } else if (kind == 'income') {
        balance += amount;
      }
    }
    if (kind == 'transfer' && destinationId == accountId) {
      balance += amount;
    }
  }
  return balance;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 999;
}

const _defaultAccounts = <Map<String, dynamic>>[
  {
    'id': 'acc-cash',
    'name': 'Caixa',
    'type': 'cash',
    'icon': '💵',
    'color': '#F59E0B',
    'display_order': 1,
    'opening_balance': 200.0,
    'allows_negative': true,
    'protected': true,
    'active': true,
  },
  {
    'id': 'acc-cgd',
    'name': 'Banco CGD',
    'type': 'bank',
    'icon': '🏦',
    'color': '#0C18D2',
    'display_order': 2,
    'opening_balance': 1200.0,
    'allows_negative': false,
    'protected': true,
    'active': true,
  },
  {
    'id': 'acc-fees',
    'name': 'Quotas',
    'type': 'internal',
    'icon': '👥',
    'color': '#2563EB',
    'display_order': 3,
    'opening_balance': 0.0,
    'allows_negative': false,
    'protected': true,
    'active': true,
  },
  {
    'id': 'acc-reserve',
    'name': 'Reserva',
    'type': 'internal',
    'icon': '🛡️',
    'color': '#7C3AED',
    'display_order': 4,
    'opening_balance': 500.0,
    'allows_negative': false,
    'protected': false,
    'active': true,
  },
  {
    'id': 'acc-representation',
    'name': 'Representação',
    'type': 'internal',
    'icon': '🤝',
    'color': '#0891B2',
    'display_order': 5,
    'opening_balance': 250.0,
    'allows_negative': false,
    'protected': false,
    'active': true,
  },
  {
    'id': 'acc-marketing',
    'name': 'Marketing',
    'type': 'internal',
    'icon': '📣',
    'color': '#DB2777',
    'display_order': 6,
    'opening_balance': 150.0,
    'allows_negative': false,
    'protected': false,
    'active': true,
  },
  {
    'id': 'acc-lottery',
    'name': 'Euromilhões',
    'type': 'internal',
    'icon': '🍀',
    'color': '#16A34A',
    'display_order': 7,
    'opening_balance': 90.0,
    'allows_negative': false,
    'protected': false,
    'active': true,
  },
  {
    'id': 'acc-clubhouse',
    'name': 'Club House',
    'type': 'internal',
    'icon': '🍺',
    'color': '#EA580C',
    'display_order': 8,
    'opening_balance': 420.0,
    'allows_negative': false,
    'protected': false,
    'active': true,
  },
];
