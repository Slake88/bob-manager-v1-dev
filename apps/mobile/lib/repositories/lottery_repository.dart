import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class LotteryRepository {
  LotteryRepository({DataService? dataService})
      : _dataService = dataService ?? DataService.instance;

  final DataService _dataService;

  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listParticipants() async {
    _require(AppPermission.viewLottery);
    final rows = await _dataService.list('lottery_participants');
    rows.sort((a, b) => (a['member_name']?.toString() ?? '')
        .compareTo(b['member_name']?.toString() ?? ''));
    return rows;
  }

  Future<List<Map<String, dynamic>>> listMembers() async {
    _require(AppPermission.viewLottery);
    final rows = await _dataService.list('members');
    rows.sort((a, b) => (a['full_name']?.toString() ?? '')
        .compareTo(b['full_name']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, dynamic>> saveParticipant(
    Map<String, dynamic> values, {
    String? id,
  }) {
    _require(AppPermission.manageLottery);
    _validateKey(values['numbers']?.toString() ?? '', 5, 1, 50, 'números');
    _validateKey(values['stars']?.toString() ?? '', 2, 1, 12, 'estrelas');

    final normalized = {
      ...values,
      'participant_amount': _asDouble(values['participant_amount']),
      'paid_amount': _asDouble(values['paid_amount']),
      'balance': _asDouble(values['balance']),
      'active': values['active'] != false,
    };
    if (id == null) {
      return _dataService.insert('lottery_participants', normalized);
    }
    return _dataService.update('lottery_participants', id, normalized);
  }

  Future<Map<String, dynamic>> registerPayment({
    required Map<String, dynamic> participant,
    required double amount,
    required String paymentMethod,
  }) async {
    _require(AppPermission.manageLottery);
    if (amount <= 0) {
      throw ArgumentError('O valor do pagamento deve ser superior a zero.');
    }
    final id = participant['id']?.toString();
    if (id == null || id.isEmpty) {
      throw ArgumentError('Participante sem identificador.');
    }

    final currentPaid = _asDouble(participant['paid_amount']);
    final currentBalance = _asDouble(participant['balance']);
    final updated = await saveParticipant(
      {
        ...participant,
        'paid_amount': currentPaid + amount,
        'balance': (currentBalance - amount).clamp(0, double.infinity),
        'payment_method': paymentMethod,
        'last_payment_at': DateTime.now().toIso8601String(),
      },
      id: id,
    );

    await _dataService.insert('financial_transactions', {
      'transaction_date': DateTime.now().toIso8601String().split('T').first,
      'kind': 'income',
      'status': 'confirmed',
      'description': 'Euromilhões - ${participant['member_name'] ?? ''}',
      'amount': amount,
      'account_id': 'acc-lottery',
      'account_name': 'Euromilhões',
      'member_id': participant['member_id'],
      'member_name': participant['member_name'],
      'payment_method': paymentMethod,
      'created_by': AppSession.instance.profileId,
    });

    return updated;
  }

  void _validateKey(
    String raw,
    int expectedCount,
    int minimum,
    int maximum,
    String label,
  ) {
    final values = raw
        .split(RegExp(r'[,;\s]+'))
        .where((value) => value.isNotEmpty)
        .map(int.tryParse)
        .toList();
    if (values.length != expectedCount || values.any((value) => value == null)) {
      throw ArgumentError('Indica exatamente $expectedCount $label.');
    }
    final numbers = values.cast<int>();
    if (numbers.toSet().length != expectedCount ||
        numbers.any((value) => value < minimum || value > maximum)) {
      throw ArgumentError('$label inválidos ou repetidos.');
    }
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
