import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class TreasuryUserException implements Exception {
  const TreasuryUserException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TreasuryRepository {
  TreasuryRepository({DataService? dataService, SupabaseClient? client})
      : _dataService = dataService ?? DataService.instance,
        _client = client;

  final DataService _dataService;
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  bool get canManageAccounts =>
      PermissionPolicy.allows(currentRole, AppPermission.manageFinancialAccounts);

  Future<Map<String, dynamic>> summary() async {
    _require(AppPermission.viewTreasury);
    if (AppConfig.demoMode) return _dataService.treasurySummary();

    final accounts = await listAccounts();
    final movements = await listMovements();
    final now = DateTime.now();
    var monthlyIncome = 0.0;
    var monthlyExpense = 0.0;

    for (final movement in movements) {
      final date = DateTime.tryParse(
        movement['transaction_date']?.toString() ?? '',
      );
      if (date == null || date.year != now.year || date.month != now.month) {
        continue;
      }
      final amount = _asDouble(movement['amount']);
      if (movement['kind'] == 'income') monthlyIncome += amount;
      if (movement['kind'] == 'expense') monthlyExpense += amount;
    }

    return <String, dynamic>{
      'accounts': accounts,
      'total_balance': accounts.fold<double>(
        0,
        (total, account) => total + _asDouble(account['balance']),
      ),
      'monthly_income': monthlyIncome,
      'monthly_expense': monthlyExpense,
      'pending_approvals': 0,
      'recent_transactions': movements.take(8).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> listAccounts() async {
    _require(AppPermission.viewTreasury);
    if (AppConfig.demoMode) {
      final summaryData = await _dataService.treasurySummary();
      return _sortAccounts(List<Map<String, dynamic>>.from(
        summaryData['accounts'] as List<dynamic>? ?? const [],
      ));
    }

    final accountResponse = await _supabase
        .from('treasury_accounts')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('active', true);
    final balanceResponse = await _supabase.rpc(
      'treasury_account_balances_v1',
      params: {'target_club': AppSession.instance.clubId},
    );

    final balances = <String, dynamic>{
      for (final row in List<Map<String, dynamic>>.from(balanceResponse as List))
        row['id'].toString(): row['balance'],
    };

    final accounts = List<Map<String, dynamic>>.from(accountResponse)
        .map((row) => _normaliseAccount(row, balances[row['id'].toString()]))
        .toList();
    return _sortAccounts(accounts);
  }

  Future<List<Map<String, dynamic>>> listCostCenters() async {
    _require(AppPermission.viewTreasury);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('cost_centers');
      rows.sort((a, b) => (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('cost_centers')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> createAccount({
    required String name,
    required String accountType,
    String? iban,
    String? icon,
    double openingBalance = 0,
  }) async {
    _require(AppPermission.manageFinancialAccounts);
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const TreasuryUserException('Indica o nome da conta.');
    }

    final existing = await listAccounts();
    if (existing.any((row) =>
        row['name']?.toString().toLowerCase() == cleanName.toLowerCase())) {
      throw const TreasuryUserException('Já existe uma conta com esse nome.');
    }

    final values = <String, dynamic>{
      'name': cleanName,
      'account_type': accountType,
      'type': accountType,
      'iban': iban?.trim().isEmpty == true ? null : iban?.trim(),
      'icon': icon?.trim().isEmpty == true ? '💰' : icon?.trim(),
      'opening_balance': openingBalance,
      'opening_date': DateTime.now().toIso8601String().split('T').first,
      'allows_negative': cleanName.toLowerCase() == 'caixa',
      'active': true,
    };

    if (AppConfig.demoMode) {
      return _dataService.insert('financial_accounts', values);
    }

    try {
      final response = await _supabase
          .from('treasury_accounts')
          .insert({
            'club_id': AppSession.instance.clubId,
            'name': cleanName,
            'account_type': accountType,
            'iban': values['iban'],
            'icon': values['icon'],
            'opening_balance': openingBalance,
            'opening_date': values['opening_date'],
            'allows_negative': values['allows_negative'],
            'active': true,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (error) {
      throw TreasuryUserException(_friendlyDatabaseMessage(error.message));
    }
  }

  Future<Map<String, dynamic>> updateAccount(
    String id, {
    required String name,
    required String accountType,
    String? iban,
    String? icon,
  }) async {
    _require(AppPermission.manageFinancialAccounts);
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const TreasuryUserException('Indica o nome da conta.');
    }

    final accounts = await listAccounts();
    if (accounts.any((row) =>
        row['id']?.toString() != id &&
        row['name']?.toString().toLowerCase() == cleanName.toLowerCase())) {
      throw const TreasuryUserException('Já existe uma conta com esse nome.');
    }

    final values = <String, dynamic>{
      'name': cleanName,
      'account_type': accountType,
      'type': accountType,
      'iban': iban?.trim().isEmpty == true ? null : iban?.trim(),
      'icon': icon?.trim().isEmpty == true ? '💰' : icon?.trim(),
      'allows_negative': cleanName.toLowerCase() == 'caixa',
    };

    if (AppConfig.demoMode) {
      return _dataService.update('financial_accounts', id, values);
    }

    try {
      final response = await _supabase
          .from('treasury_accounts')
          .update({
            'name': cleanName,
            'account_type': accountType,
            'iban': values['iban'],
            'icon': values['icon'],
            'allows_negative': values['allows_negative'],
          })
          .eq('id', id)
          .eq('club_id', AppSession.instance.clubId)
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (error) {
      throw TreasuryUserException(_friendlyDatabaseMessage(error.message));
    }
  }

  Future<void> deactivateAccount(Map<String, dynamic> account) async {
    _require(AppPermission.manageFinancialAccounts);
    final id = account['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const TreasuryUserException('Conta inválida.');
    }
    if (_asDouble(account['balance']).abs() > 0.0001) {
      throw const TreasuryUserException(
        'A conta só pode ser desativada quando tiver saldo igual a zero.',
      );
    }

    if (AppConfig.demoMode) {
      await _dataService.update('financial_accounts', id, {'active': false});
      return;
    }

    try {
      await _supabase
          .from('treasury_accounts')
          .update({'active': false})
          .eq('id', id)
          .eq('club_id', AppSession.instance.clubId);
    } on PostgrestException catch (error) {
      throw TreasuryUserException(_friendlyDatabaseMessage(error.message));
    }
  }

  Future<List<Map<String, dynamic>>> listMovements() async {
    _require(AppPermission.viewTreasury);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('financial_transactions');
      rows.sort((a, b) => (b['transaction_date']?.toString() ?? '')
          .compareTo(a['transaction_date']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('treasury_transactions')
        .select(
          '*, source_account:treasury_accounts!treasury_transactions_account_id_fkey(name), destination_account:treasury_accounts!treasury_transactions_destination_account_id_fkey(name), cost_center:cost_centers(name)',
        )
        .eq('club_id', AppSession.instance.clubId)
        .order('transaction_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(250);

    return List<Map<String, dynamic>>.from(response).map((row) {
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
  }

  Future<void> transfer({
    required String sourceAccountId,
    required String destinationAccountId,
    required double amount,
    required String description,
  }) async {
    _require(AppPermission.transferBetweenAccounts);
    if (AppConfig.demoMode) {
      return _dataService.transferBetweenAccounts(
        sourceAccountId: sourceAccountId,
        destinationAccountId: destinationAccountId,
        amount: amount,
        description: description,
      );
    }

    try {
      await _supabase.rpc(
        'create_transaction_v1',
        params: {
          'target_club': AppSession.instance.clubId,
          'p_kind': 'transfer',
          'p_account': sourceAccountId,
          'p_destination_account': destinationAccountId,
          'p_description': description.trim().isEmpty
              ? 'Transferência entre contas'
              : description.trim(),
          'p_amount': amount,
        },
      );
    } on PostgrestException catch (error) {
      throw TreasuryUserException(_friendlyDatabaseMessage(error.message));
    }
  }

  Future<Map<String, dynamic>> createMovement(
    Map<String, dynamic> values,
  ) async {
    _require(AppPermission.createTreasuryMovement);

    final kind = values['kind']?.toString();
    final accountId = values['account_id']?.toString();
    final costCenterId = values['cost_center_id']?.toString();
    final amount = _asDouble(values['amount']);
    if (kind != 'income' && kind != 'expense') {
      throw const TreasuryUserException('Tipo de movimento inválido.');
    }
    if (accountId == null || accountId.isEmpty) {
      throw const TreasuryUserException('Seleciona uma conta.');
    }
    if (amount <= 0) {
      throw const TreasuryUserException('O valor deve ser superior a zero.');
    }
    if (kind == 'expense' &&
        (costCenterId == null || costCenterId.isEmpty)) {
      throw const TreasuryUserException('Seleciona o centro de custo.');
    }

    if (AppConfig.demoMode) {
      return _dataService.insert('financial_transactions', {
        ...values,
        'created_by': AppSession.instance.profileId,
        'status': values['status'] ?? 'confirmed',
      });
    }

    if (kind == 'expense') {
      final accounts = await listAccounts();
      final account = accounts.firstWhere(
        (row) => row['id']?.toString() == accountId,
        orElse: () => throw const TreasuryUserException('Conta não encontrada.'),
      );
      if (account['allows_negative'] != true &&
          _asDouble(account['balance']) < amount) {
        throw TreasuryUserException(
          'Saldo insuficiente na conta ${account['name']}. '
          'Esta conta não pode ficar com saldo negativo.',
        );
      }
    }

    try {
      final response = await _supabase
          .from('treasury_transactions')
          .insert({
            'club_id': AppSession.instance.clubId,
            'kind': kind,
            'account_id': accountId,
            'transaction_date': values['transaction_date'] ??
                DateTime.now().toIso8601String().split('T').first,
            'description': values['description']?.toString().trim(),
            'amount': amount,
            'cost_center_id': costCenterId,
            'payment_method': values['payment_method'],
            'notes': values['notes'],
            'created_by': AppSession.instance.profileId,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    } on PostgrestException catch (error) {
      throw TreasuryUserException(_friendlyDatabaseMessage(error.message));
    }
  }

  Map<String, dynamic> _normaliseAccount(
    Map<String, dynamic> row,
    Object? balance,
  ) {
    final name = row['name']?.toString() ?? 'Conta';
    final defaults = _accountDefaults(name);
    return <String, dynamic>{
      ...row,
      'type': row['account_type'],
      'icon': row['icon'] ?? defaults.$1,
      'display_order': row['display_order'] ?? defaults.$2,
      'allows_negative': row['allows_negative'] ?? name.toLowerCase() == 'caixa',
      'protected': row['protected'] ?? defaults.$3,
      'balance': _asDouble(balance),
    };
  }

  List<Map<String, dynamic>> _sortAccounts(
    List<Map<String, dynamic>> accounts,
  ) {
    accounts.sort((a, b) {
      final aOrder = int.tryParse(a['display_order']?.toString() ?? '') ?? 999;
      final bOrder = int.tryParse(b['display_order']?.toString() ?? '') ?? 999;
      if (aOrder != bOrder) return aOrder.compareTo(bOrder);
      return (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? '');
    });
    return accounts;
  }

  (String, int, bool) _accountDefaults(String name) {
    return switch (name.toLowerCase()) {
      'caixa' => ('💵', 1, true),
      'banco cgd' => ('🏦', 2, true),
      'quotas' => ('👥', 3, true),
      'reserva' => ('🛡️', 4, false),
      'representação' => ('🤝', 5, false),
      'marketing' => ('📣', 6, false),
      'euromilhões' => ('🍀', 7, false),
      'club house' => ('🍺', 8, false),
      _ => ('💰', 999, false),
    };
  }

  String _friendlyDatabaseMessage(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('saldo insuficiente')) {
      return 'Saldo insuficiente. Esta conta não pode ficar com saldo negativo.';
    }
    if (normalized.contains('origem') && normalized.contains('destino')) {
      return 'As contas de origem e destino têm de ser diferentes.';
    }
    if (normalized.contains('conta') && normalized.contains('inativa')) {
      return 'A conta selecionada está inativa.';
    }
    if (normalized.contains('valor') && normalized.contains('superior a zero')) {
      return 'O valor tem de ser superior a zero.';
    }
    if (normalized.contains('permiss')) {
      return 'Não tens permissão para executar esta operação.';
    }

    return 'Não foi possível concluir a operação. Verifica os dados e tenta novamente.';
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw const TreasuryUserException(
        'Não tens permissão para executar esta operação.',
      );
    }
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
