import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../core/treasury_economics.dart';
import 'treasury_repository.dart';

class TreasuryOperationalRepository {
  TreasuryOperationalRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  TreasuryRepository get _treasury => TreasuryRepository(client: _client);

  bool get isDemo => AppConfig.demoMode;
  bool get canPlan => AppSession.instance.can(AppPermission.manageTreasuryPlanning);
  bool get canManageCash => AppSession.instance.can(AppPermission.manageCashSessions);
  bool get canApproveCash =>
      AppSession.instance.can(AppPermission.approveCashDifferences);
  bool get canReverse =>
      AppSession.instance.can(AppPermission.reverseTreasuryMovement);

  Future<Map<String, dynamic>> overview() async {
    final values = await Future.wait<dynamic>([
      listObligations('payable'),
      listObligations('receivable'),
      listBudgets(),
      listReconciliations(),
      listCashSessions(),
      listCostCenters(includeInactive: true),
    ]);
    final payables = values[0] as List<Map<String, dynamic>>;
    final receivables = values[1] as List<Map<String, dynamic>>;
    final budgets = values[2] as List<Map<String, dynamic>>;
    final reconciliations = values[3] as List<Map<String, dynamic>>;
    final sessions = values[4] as List<Map<String, dynamic>>;
    final centers = values[5] as List<Map<String, dynamic>>;

    return <String, dynamic>{
      'payables_open': payables.where(_isOpen).length,
      'payables_amount': payables.where(_isOpen).fold<double>(
            0,
            (sum, row) => sum + treasuryOutstanding(row),
          ),
      'receivables_open': receivables.where(_isOpen).length,
      'receivables_amount': receivables.where(_isOpen).fold<double>(
            0,
            (sum, row) => sum + treasuryOutstanding(row),
          ),
      'budgets_active': budgets.where((row) => row['status'] != 'closed').length,
      'reconciliations_draft':
          reconciliations.where((row) => row['status'] == 'draft').length,
      'cash_active': sessions
          .where((row) =>
              row['status'] == 'open' || row['status'] == 'pending_approval')
          .length,
      'cash_pending_approval':
          sessions.where((row) => row['status'] == 'pending_approval').length,
      'cost_centers': centers.where((row) => row['active'] != false).length,
    };
  }

  Future<List<Map<String, dynamic>>> listAccounts() => _treasury.listAccounts();

  Future<List<Map<String, dynamic>>> listCostCenters({
    bool includeInactive = false,
  }) async {
    if (isDemo) {
      final rows = <Map<String, dynamic>>[
        {'id': 'demo-cc-events', 'name': 'Eventos', 'code': 'EVT', 'active': true},
        {'id': 'demo-cc-clubhouse', 'name': 'Club House', 'code': 'CH', 'active': true},
        {'id': 'demo-cc-admin', 'name': 'Administração', 'code': 'ADM', 'active': true},
      ];
      return includeInactive
          ? rows
          : rows.where((row) => row['active'] == true).toList();
    }

    final response = await _supabase
        .from('cost_centers')
        .select('id,name,code,active')
        .eq('club_id', AppSession.instance.clubId)
        .order('name');
    final rows = List<Map<String, dynamic>>.from(response);
    return includeInactive
        ? rows
        : rows.where((row) => row['active'] == true).toList();
  }

  Future<void> saveCostCenter({
    String? id,
    required String name,
    String code = '',
    bool active = true,
  }) async {
    _ensureRealWrite();
    await _supabase.rpc('save_cost_center_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_id': id,
      'p_name': name,
      'p_code': code.trim().isEmpty ? null : code.trim(),
      'p_active': active,
    });
  }

  Future<List<Map<String, dynamic>>> listObligations(String type) async {
    final table = _obligationTable(type);
    if (isDemo) return _demoObligations(type);
    final response = await _supabase
        .from(table)
        .select(
          '*, account:treasury_accounts(name), cost_center:cost_centers(name), event:events(name)',
        )
        .eq('club_id', AppSession.instance.clubId)
        .order('due_date')
        .limit(300);
    return List<Map<String, dynamic>>.from(response).map((row) {
      final account = row['account'];
      final center = row['cost_center'];
      final event = row['event'];
      return <String, dynamic>{
        ...row,
        'account_name': account is Map ? account['name'] : null,
        'cost_center_name': center is Map ? center['name'] : null,
        'event_name': event is Map ? event['name'] : null,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> saveObligation(
    String type,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _ensureRealWrite();
    final table = _obligationTable(type);
    final payload = <String, dynamic>{
      'counterparty': values['counterparty']?.toString().trim(),
      'description': values['description']?.toString().trim(),
      'due_date': values['due_date'],
      'amount': treasuryNumber(values['amount']),
      'account_id': _nullable(values['account_id']),
      'cost_center_id': _nullable(values['cost_center_id']),
      'event_id': _nullable(values['event_id']),
      'notes': _nullable(values['notes']),
    };
    if (id == null) {
      final response = await _supabase
          .from(table)
          .insert({...payload, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from(table)
        .update(payload)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> settleObligation({
    required String type,
    required String obligationId,
    required String accountId,
    required double amount,
    String paymentMethod = '',
    String notes = '',
  }) async {
    _ensureRealWrite();
    await _supabase.rpc('settle_treasury_obligation_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_obligation_type': type,
      'p_obligation': obligationId,
      'p_account': accountId,
      'p_amount': amount,
      'p_payment_method':
          paymentMethod.trim().isEmpty ? null : paymentMethod.trim(),
      'p_notes': notes.trim().isEmpty ? null : notes.trim(),
    });
  }

  Future<void> cancelObligation({
    required String type,
    required String obligationId,
    required String reason,
  }) async {
    _ensureRealWrite();
    await _supabase.rpc('cancel_treasury_obligation_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_obligation_type': type,
      'p_obligation': obligationId,
      'p_reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> listBudgets() async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-budget',
          'name': 'Orçamento anual 2026',
          'period_start': '2026-01-01',
          'period_end': '2026-12-31',
          'status': 'approved',
          'notes': 'Pré-visualização do planeamento anual.',
        },
      ];
    }
    final response = await _supabase
        .from('budgets')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .order('period_start', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveBudget(
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _ensureRealWrite();
    final payload = <String, dynamic>{
      'name': values['name']?.toString().trim(),
      'period_start': values['period_start'],
      'period_end': values['period_end'],
      'notes': _nullable(values['notes']),
    };
    if (id == null) {
      final response = await _supabase
          .from('budgets')
          .insert({...payload, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from('budgets')
        .update(payload)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listBudgetLines(String budgetId) async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-line-income',
          'budget_id': budgetId,
          'label': 'Quotas e receitas regulares',
          'line_type': 'income',
          'planned_amount': 6000.0,
        },
        {
          'id': 'demo-line-expense',
          'budget_id': budgetId,
          'label': 'Eventos e representação',
          'line_type': 'expense',
          'planned_amount': 3500.0,
        },
      ];
    }
    final response = await _supabase
        .from('budget_lines')
        .select('*, cost_center:cost_centers(name), event:events(name)')
        .eq('club_id', AppSession.instance.clubId)
        .eq('budget_id', budgetId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response).map((row) {
      final center = row['cost_center'];
      final event = row['event'];
      return <String, dynamic>{
        ...row,
        'cost_center_name': center is Map ? center['name'] : null,
        'event_name': event is Map ? event['name'] : null,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> saveBudgetLine(
    String budgetId,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _ensureRealWrite();
    final payload = <String, dynamic>{
      'budget_id': budgetId,
      'label': values['label']?.toString().trim(),
      'line_type': values['line_type'],
      'planned_amount': treasuryNumber(values['planned_amount']),
      'cost_center_id': _nullable(values['cost_center_id']),
      'event_id': _nullable(values['event_id']),
      'notes': _nullable(values['notes']),
    };
    if (id == null) {
      final response = await _supabase
          .from('budget_lines')
          .insert({...payload, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from('budget_lines')
        .update(payload)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<void> deleteBudgetLine(String id) async {
    _ensureRealWrite();
    await _supabase
        .from('budget_lines')
        .delete()
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<void> setBudgetStatus(String budgetId, String status) async {
    _ensureRealWrite();
    await _supabase.rpc('set_budget_status_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_budget': budgetId,
      'p_status': status,
    });
  }

  Future<List<Map<String, dynamic>>> budgetPerformance(String budgetId) async {
    if (isDemo) {
      final lines = await listBudgetLines(budgetId);
      return lines.map((line) {
        final planned = treasuryNumber(line['planned_amount']);
        final actual =
            line['line_type'] == 'income' ? planned * .72 : planned * .61;
        return <String, dynamic>{
          ...line,
          'actual_amount': actual,
          'variance_amount': actual - planned,
        };
      }).toList();
    }
    final response = await _supabase.rpc('budget_performance_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_budget': budgetId,
    });
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<List<Map<String, dynamic>>> listReconciliations() async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-reconciliation',
          'account_id': 'acc-bank',
          'account_name': 'Banco CGD',
          'period_start': '2026-07-01',
          'period_end': '2026-07-31',
          'statement_opening_balance': 4300.0,
          'statement_closing_balance': 4725.0,
          'book_closing_balance': 4725.0,
          'difference_amount': 0.0,
          'status': 'closed',
        },
      ];
    }
    final response = await _supabase
        .from('bank_reconciliations')
        .select('*, account:treasury_accounts(name)')
        .eq('club_id', AppSession.instance.clubId)
        .order('period_end', ascending: false);
    return List<Map<String, dynamic>>.from(response).map((row) {
      final account = row['account'];
      return <String, dynamic>{
        ...row,
        'account_name': account is Map ? account['name'] : null,
      };
    }).toList();
  }

  Future<Map<String, dynamic>> saveReconciliation(
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _ensureRealWrite();
    final payload = <String, dynamic>{
      'account_id': values['account_id'],
      'period_start': values['period_start'],
      'period_end': values['period_end'],
      'statement_opening_balance':
          treasuryNumber(values['statement_opening_balance']),
      'statement_closing_balance':
          treasuryNumber(values['statement_closing_balance']),
      'notes': _nullable(values['notes']),
    };
    if (id == null) {
      final response = await _supabase
          .from('bank_reconciliations')
          .insert({...payload, 'club_id': AppSession.instance.clubId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from('bank_reconciliations')
        .update(payload)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> listReconciliationTransactions(
    Map<String, dynamic> reconciliation,
  ) async {
    if (isDemo) return <Map<String, dynamic>>[];
    final accountId = reconciliation['account_id']?.toString() ?? '';
    final from = reconciliation['period_start']?.toString() ?? '';
    final to = reconciliation['period_end']?.toString() ?? '';
    final response = await _supabase
        .from('treasury_transactions')
        .select(
          'id,kind,account_id,destination_account_id,transaction_date,description,amount,reversal_of',
        )
        .eq('club_id', AppSession.instance.clubId)
        .gte('transaction_date', from)
        .lte('transaction_date', to)
        .or('account_id.eq.$accountId,destination_account_id.eq.$accountId')
        .order('transaction_date');
    return effectiveTreasuryRows(List<Map<String, dynamic>>.from(response));
  }

  Future<Set<String>> reconciliationTransactionIds(
    String reconciliationId,
  ) async {
    if (isDemo) return <String>{};
    final response = await _supabase
        .from('bank_reconciliation_items')
        .select('transaction_id')
        .eq('club_id', AppSession.instance.clubId)
        .eq('reconciliation_id', reconciliationId);
    return List<Map<String, dynamic>>.from(response)
        .map((row) => row['transaction_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<void> setReconciliationTransaction({
    required String reconciliationId,
    required String transactionId,
    required bool included,
  }) async {
    _ensureRealWrite();
    if (included) {
      await _supabase.from('bank_reconciliation_items').insert({
        'club_id': AppSession.instance.clubId,
        'reconciliation_id': reconciliationId,
        'transaction_id': transactionId,
      });
    } else {
      await _supabase
          .from('bank_reconciliation_items')
          .delete()
          .eq('club_id', AppSession.instance.clubId)
          .eq('reconciliation_id', reconciliationId)
          .eq('transaction_id', transactionId);
    }
  }

  Future<double> closeReconciliation(String id) async {
    _ensureRealWrite();
    final response = await _supabase.rpc(
      'close_bank_reconciliation_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_reconciliation': id,
      },
    );
    return treasuryNumber(response);
  }

  Future<List<Map<String, dynamic>>> listCashSessions() async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-cash',
          'account_id': 'acc-cash',
          'account_name': 'Caixa',
          'book_opening_amount': 150.0,
          'opening_amount': 150.0,
          'opened_at': '2026-08-13T09:00:00',
          'status': 'open',
        },
      ];
    }
    final response = await _supabase
        .from('cash_sessions')
        .select('*, account:treasury_accounts(name,account_type)')
        .eq('club_id', AppSession.instance.clubId)
        .order('opened_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response).map((row) {
      final account = row['account'];
      return <String, dynamic>{
        ...row,
        'account_name': account is Map ? account['name'] : null,
        'account_type': account is Map ? account['account_type'] : null,
      };
    }).toList();
  }

  Future<void> openCashSession(String accountId, double openingAmount) async {
    _ensureRealWrite();
    await _supabase.rpc('open_cash_session_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_account': accountId,
      'p_opening_amount': openingAmount,
    });
  }

  Future<String> closeCashSession(
    String sessionId,
    double countedAmount,
    String notes,
  ) async {
    _ensureRealWrite();
    final response = await _supabase.rpc('close_cash_session_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_session': sessionId,
      'p_counted_amount': countedAmount,
      'p_notes': notes.trim().isEmpty ? null : notes.trim(),
    });
    return response.toString();
  }

  Future<void> approveCashSession(String sessionId, String reason) async {
    _ensureRealWrite();
    await _supabase.rpc('approve_cash_session_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_session': sessionId,
      'p_reason': reason,
    });
  }

  Future<List<Map<String, dynamic>>> listReversibleTransactions() async {
    if (isDemo) {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-transaction',
          'transaction_date': '2026-08-12',
          'kind': 'expense',
          'description': 'Exemplo de despesa reversível',
          'amount': 75.0,
          'account_name': 'Banco CGD',
        },
      ];
    }
    final response = await _supabase
        .from('treasury_transactions')
        .select(
          '*, source_account:treasury_accounts!treasury_transactions_account_id_fkey(name), destination_account:treasury_accounts!treasury_transactions_destination_account_id_fkey(name)',
        )
        .eq('club_id', AppSession.instance.clubId)
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(300);
    final rows = List<Map<String, dynamic>>.from(response).map((row) {
      final account = row['source_account'];
      final destination = row['destination_account'];
      return <String, dynamic>{
        ...row,
        'account_name': account is Map ? account['name'] : null,
        'destination_account_name':
            destination is Map ? destination['name'] : null,
      };
    }).toList();
    final reversedIds = rows
        .map((row) => row['reversal_of']?.toString())
        .whereType<String>()
        .toSet();
    return rows.where((row) {
      final id = row['id']?.toString();
      final sourceType = row['source_type']?.toString();
      if (row['reversal_of'] != null || row['kind'] == 'reversal') return false;
      if (id != null && reversedIds.contains(id)) return false;
      return sourceType == null ||
          sourceType.isEmpty ||
          sourceType == 'payable' ||
          sourceType == 'receivable';
    }).toList();
  }

  Future<void> reverseTransaction(String transactionId, String reason) async {
    _ensureRealWrite();
    await _supabase.rpc('reverse_treasury_transaction_v1', params: {
      'target_club': AppSession.instance.clubId,
      'p_transaction': transactionId,
      'p_reason': reason,
    });
  }

  String _obligationTable(String type) {
    if (type == 'payable') return 'payables';
    if (type == 'receivable') return 'receivables';
    throw ArgumentError('Tipo de obrigação financeira inválido.');
  }

  bool _isOpen(Map<String, dynamic> row) =>
      row['status'] != 'paid' && row['status'] != 'cancelled';

  Object? _nullable(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : value;
  }

  void _ensureRealWrite() {
    if (isDemo) {
      throw StateError(
        'No modo demonstração as operações de escrita estão desativadas.',
      );
    }
  }

  List<Map<String, dynamic>> _demoObligations(String type) {
    if (type == 'payable') {
      return <Map<String, dynamic>>[
        {
          'id': 'demo-payable-1',
          'counterparty': 'Fornecedor exemplo',
          'description': 'Material para evento',
          'due_date': '2026-08-25',
          'amount': 480.0,
          'settled_amount': 180.0,
          'status': 'partial',
          'cost_center_name': 'Eventos',
        },
      ];
    }
    return <Map<String, dynamic>>[
      {
        'id': 'demo-receivable-1',
        'counterparty': 'Parceiro exemplo',
        'description': 'Apoio ao evento',
        'due_date': '2026-08-30',
        'amount': 650.0,
        'settled_amount': 0.0,
        'status': 'open',
        'cost_center_name': 'Eventos',
      },
    ];
  }
}
