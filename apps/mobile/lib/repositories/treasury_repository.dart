import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';
import '../services/rc1_data_extensions.dart';

class TreasuryRepository {
  TreasuryRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<Map<String, dynamic>> summary() {
    _require(AppPermission.viewTreasury);
    return _dataService.treasurySummary();
  }

  Future<List<Map<String, dynamic>>> listAccounts() async {
    _require(AppPermission.viewTreasury);
    final summaryData = await _dataService.treasurySummary();
    final rows = List<Map<String, dynamic>>.from(
      summaryData['accounts'] as List<dynamic>? ?? const [],
    );
    rows.sort((a, b) {
      final aOrder = int.tryParse(a['display_order']?.toString() ?? '') ?? 999;
      final bOrder = int.tryParse(b['display_order']?.toString() ?? '') ?? 999;
      return aOrder.compareTo(bOrder);
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> listMovements() async {
    _require(AppPermission.viewTreasury);
    final rows = await _dataService.list('financial_transactions');
    rows.sort(
      (a, b) => (b['transaction_date']?.toString() ?? '')
          .compareTo(a['transaction_date']?.toString() ?? ''),
    );
    return rows;
  }

  Future<void> transfer({
    required String sourceAccountId,
    required String destinationAccountId,
    required double amount,
    required String description,
  }) {
    _require(AppPermission.transferBetweenAccounts);
    return _dataService.transferBetweenAccounts(
      sourceAccountId: sourceAccountId,
      destinationAccountId: destinationAccountId,
      amount: amount,
      description: description,
    );
  }

  Future<Map<String, dynamic>> createMovement(
    Map<String, dynamic> values,
  ) {
    _require(AppPermission.createTreasuryMovement);
    return _dataService.insert('financial_transactions', {
      ...values,
      'created_by': AppSession.instance.profileId,
      'status': values['status'] ?? 'confirmed',
    });
  }

  Future<Map<String, dynamic>> approveExpenseRequest(
    Map<String, dynamic> request,
  ) async {
    _require(AppPermission.approveExpenseRequests);
    final id = request['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Pedido de despesa sem identificador.');
    }

    final updated = await _dataService.update(
      'expense_requests',
      id,
      {
        'status': 'approved',
        'approved_by': AppSession.instance.profileId,
        'approved_at': DateTime.now().toIso8601String(),
      },
    );

    await createMovement({
      'transaction_date': request['request_date'] ??
          DateTime.now().toIso8601String().split('T').first,
      'kind': 'expense',
      'description': request['description'] ?? 'Despesa aprovada',
      'amount': request['requested_amount'] ?? 0,
      'account_id': request['account_id'],
      'account_name': request['account_name'],
      'cost_center_id': request['cost_center_id'],
      'cost_center_name': request['cost_center_name'],
      'member_id': request['requester_member_id'],
      'member_name': request['requester_name'],
      'expense_request_id': id,
    });

    return updated;
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}
