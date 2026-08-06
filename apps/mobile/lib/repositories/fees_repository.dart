import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class FeesRepository {
  FeesRepository({DataService? dataService, SupabaseClient? client})
      : _dataService = dataService ?? DataService.instance,
        _client = client;

  final DataService _dataService;
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listObligations() async {
    _require(AppPermission.viewFees);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('fee_obligations');
      rows.sort((a, b) => (b['due_date']?.toString() ?? '')
          .compareTo(a['due_date']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('fee_obligations')
        .select('*, member:members!fee_obligations_member_id_fkey(full_name)')
        .eq('club_id', AppSession.instance.clubId)
        .order('reference_year', ascending: false)
        .order('reference_month', ascending: false)
        .order('due_date', ascending: false);

    return List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['member'];
      final amount = _asDouble(row['amount']);
      final paid = _asDouble(row['paid_amount']);
      return <String, dynamic>{
        ...row,
        'member_name': member is Map ? member['full_name'] : null,
        'period_label': _periodLabel(
          row['reference_year'],
          row['reference_month'],
        ),
        'credit_amount': 0.0,
        'balance': (amount - paid).clamp(0, double.infinity),
        'status': _displayStatus(row),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> listMembers() async {
    _require(AppPermission.viewFees);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('members');
      rows.sort((a, b) => (a['full_name']?.toString() ?? '')
          .compareTo(b['full_name']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('members')
        .select('id, full_name, member_number, status')
        .eq('club_id', AppSession.instance.clubId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveObligation(
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageFees);
    final normalized = _normalize(values);

    if (AppConfig.demoMode) {
      if (id == null) {
        return _dataService.insert('fee_obligations', normalized);
      }
      return _dataService.update('fee_obligations', id, normalized);
    }

    final period = _parsePeriod(values['period_label']);
    final payload = <String, dynamic>{
      'club_id': AppSession.instance.clubId,
      'member_id': values['member_id'],
      'reference_year': period.$1,
      'reference_month': period.$2,
      'due_date': _nullableText(values['due_date']),
      'amount': normalized['amount'],
      'paid_amount': normalized['paid_amount'],
      'status': normalized['status'] == 'overdue'
          ? 'pending'
          : normalized['status'],
      'notes': _nullableText(values['notes']),
    };

    if (id == null) {
      final response = await _supabase
          .from('fee_obligations')
          .insert(payload)
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _supabase
        .from('fee_obligations')
        .update(payload)
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
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

    final balance = _asDouble(obligation['balance']);
    if (balance > 0 && amount > balance) {
      throw StateError('O pagamento excede o valor em dívida.');
    }

    if (AppConfig.demoMode) {
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

    await _supabase.rpc(
      'register_fee_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_obligation': id,
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_notes': null,
      },
    );

    final refreshed = await _supabase
        .from('fee_obligations')
        .select()
        .eq('id', id)
        .eq('club_id', AppSession.instance.clubId)
        .single();
    return Map<String, dynamic>.from(refreshed);
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

  String _displayStatus(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'pending';
    if (status == 'pending' && _isOverdue(row['due_date'])) return 'overdue';
    return status;
  }

  (int, int?) _parsePeriod(Object? value) {
    final text = value?.toString().trim() ?? '';
    final now = DateTime.now();
    if (text.isEmpty) return (now.year, now.month);

    final iso = RegExp(r'^(\d{4})[-/](\d{1,2})$').firstMatch(text);
    if (iso != null) {
      final year = int.parse(iso.group(1)!);
      final month = int.parse(iso.group(2)!);
      if (month >= 1 && month <= 12) return (year, month);
    }

    final pt = RegExp(r'^(\d{1,2})[-/](\d{4})$').firstMatch(text);
    if (pt != null) {
      final month = int.parse(pt.group(1)!);
      final year = int.parse(pt.group(2)!);
      if (month >= 1 && month <= 12) return (year, month);
    }

    final parts = text.toLowerCase().split(RegExp(r'\s+'));
    if (parts.length == 2) {
      final month = _months[parts.first];
      final year = int.tryParse(parts.last);
      if (month != null && year != null) return (year, month);
    }

    throw ArgumentError(
      'Período inválido. Usa, por exemplo, Agosto 2026 ou 2026-08.',
    );
  }

  String _periodLabel(Object? yearValue, Object? monthValue) {
    final year = int.tryParse(yearValue?.toString() ?? '');
    final month = int.tryParse(monthValue?.toString() ?? '');
    if (year == null) return '';
    if (month == null || month < 1 || month > 12) return '$year';
    return '${_monthNames[month - 1]} $year';
  }

  bool _isOverdue(Object? dueDate) {
    final date = DateTime.tryParse(dueDate?.toString() ?? '');
    if (date == null) return false;
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    return date.isBefore(day);
  }

  String? _nullableText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  void _require(AppPermission permission) {
    if (!PermissionPolicy.allows(currentRole, permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }
}

const Map<String, int> _months = {
  'janeiro': 1,
  'fevereiro': 2,
  'março': 3,
  'marco': 3,
  'abril': 4,
  'maio': 5,
  'junho': 6,
  'julho': 7,
  'agosto': 8,
  'setembro': 9,
  'outubro': 10,
  'novembro': 11,
  'dezembro': 12,
};

const List<String> _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
