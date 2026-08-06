import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class FeesRepository {
  FeesRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listObligations() async {
    _require(AppPermission.viewFees);
    final rows = await _dataService.list('fee_obligations');
    rows.sort((a, b) => (b['due_date']?.toString() ?? '')
        .compareTo(a['due_date']?.toString() ?? ''));
    return rows;
  }

  Future<List<Map<String, dynamic>>> listMembers() async {
    _require(AppPermission.viewFees);
    final rows = await _dataService.list('members');
    rows.sort((a, b) => (a['full_name']?.toString() ?? '')
        .compareTo(b['full_name']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, dynamic>> saveObligation(
    Map<String, dynamic> values, {
    String? id,
  }) {
    _require(AppPermission.manageFees);
    final normalized = _normalize(values);
    if (id == null) {
      return _dataService.insert('fee_obligations', normalized);
    }
    return _dataService.update('fee_obligations', id, normalized);
  }

  Future<Map<String, dynamic>> registerPayment({
    required Map<String, dynamic> obligation,
    required double amount,
    required String paymentMethod,
  }) async {
    _require(AppPermission.manageFees);
    if (amount <= 0) {
      throw ArgumentError('O valor do pagamento deve ser superior a zero.');
    }

    final id = obligation['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Quota sem identificador.');
    }

    final currentPaid = _asDouble(obligation['paid_amount']);
    final updated = await saveObligation(
      {
        ...obligation,
        'paid_amount': currentPaid + amount,
        'payment_method': paymentMethod,
        'last_payment_at': DateTime.now().toIso8601String(),
      },
      id: id,
    );

    await _dataService.insert('financial_transactions', {
      'transaction_date': DateTime.now().toIso8601String().split('T').first,
      'kind': 'income',
      'status': 'confirmed',
      'description': 'Pagamento de quota - ${obligation['member_name'] ?? ''}',
      'amount': amount,
      'account_id': 'acc-fees',
      'account_name': 'Quotas',
      'member_id': obligation['member_id'],
      'member_name': obligation['member_name'],
      'payment_method': paymentMethod,
      'created_by': AppSession.instance.profileId,
    });

    return updated;
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> values) {
    final amount = _asDouble(values['amount']);
    final paid = _asDouble(values['paid_amount']);
    final credit = _asDouble(values['credit_amount']);
    final balance = (amount - paid - credit).clamp(0, double.infinity);

    var status = values['status']?.toString() ?? 'pending';
    if (balance == 0 && amount > 0) {
      status = 'paid';
    } else if (paid > 0) {
      status = 'partial';
    } else if (_isOverdue(values['due_date'])) {
      status = 'overdue';
    }

    return {
      ...values,
      'amount': amount,
      'paid_amount': paid,
      'credit_amount': credit,
      'balance': balance,
      'status': status,
    };
  }

  bool _isOverdue(Object? dueDate) {
    final date = DateTime.tryParse(dueDate?.toString() ?? '');
    return date != null && date.isBefore(DateTime.now());
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
