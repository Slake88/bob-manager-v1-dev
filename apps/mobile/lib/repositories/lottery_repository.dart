import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/data_service.dart';

class LotteryRepository {
  LotteryRepository({DataService? dataService, SupabaseClient? client})
      : _dataService = dataService ?? DataService.instance,
        _client = client;

  final DataService _dataService;
  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  AppRole get currentRole => AppRole.fromValue(AppSession.instance.role);

  Future<List<Map<String, dynamic>>> listParticipants() async {
    _require(AppPermission.viewLottery);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('lottery_participants');
      rows.sort((a, b) => (a['member_name']?.toString() ?? '')
          .compareTo(b['member_name']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('euromillions_participations')
        .select('*, member:members(full_name), draw:euromillions_draws!inner(club_id, week, status)')
        .eq('draw.club_id', AppSession.instance.clubId)
        .order('active', ascending: false);

    final rows = List<Map<String, dynamic>>.from(response).map((row) {
      final member = row['member'];
      final draw = row['draw'];
      final numbers = List<int>.from(row['numbers'] as List? ?? const []);
      final stars = List<int>.from(row['stars'] as List? ?? const []);
      return <String, dynamic>{
        ...row,
        'member_name': member is Map ? member['full_name'] : null,
        'draw_week': draw is Map ? draw['week'] : null,
        'participant_amount': row['amount'],
        'numbers': numbers.join(', '),
        'stars': stars.join(', '),
      };
    }).toList();

    rows.sort((a, b) => (a['member_name']?.toString() ?? '')
        .compareTo(b['member_name']?.toString() ?? ''));
    return rows;
  }

  Future<List<Map<String, dynamic>>> listMembers() async {
    _require(AppPermission.viewLottery);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('members');
      rows.sort((a, b) => (a['full_name']?.toString() ?? '')
          .compareTo(b['full_name']?.toString() ?? ''));
      return rows;
    }

    final response = await _supabase
        .from('members')
        .select('id, full_name')
        .eq('club_id', AppSession.instance.clubId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveParticipant(
    Map<String, dynamic> values, {
    String? id,
  }) async {
    _require(AppPermission.manageLottery);
    final numbers = _parseAndValidate(
      values['numbers']?.toString() ?? '',
      5,
      1,
      50,
      'números',
    );
    final stars = _parseAndValidate(
      values['stars']?.toString() ?? '',
      2,
      1,
      12,
      'estrelas',
    );

    if (AppConfig.demoMode) {
      final normalized = <String, dynamic>{
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

    final amount = _asDouble(values['participant_amount'] ?? values['amount']);
    if (amount <= 0) throw ArgumentError('O valor deve ser superior a zero.');

    final payload = <String, dynamic>{
      'member_id': values['member_id'],
      'amount': amount,
      'billing_frequency': values['billing_frequency'] ?? 'weekly',
      'numbers': numbers,
      'stars': stars,
      'paid_amount': _asDouble(values['paid_amount']),
      'balance': _asDouble(values['balance'] ?? amount),
      'active': values['active'] != false,
    };

    if (id == null) {
      final drawId = await _supabase.rpc(
        'ensure_euromillions_open_draw_v1',
        params: {'target_club': AppSession.instance.clubId},
      );
      final response = await _supabase
          .from('euromillions_participations')
          .insert({...payload, 'draw_id': drawId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }

    final response = await _supabase
        .from('euromillions_participations')
        .update(payload)
        .eq('id', id)
        .select()
        .single();
    return Map<String, dynamic>.from(response);
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

    if (AppConfig.demoMode) {
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

    await _supabase.rpc(
      'register_euromillions_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'participation_id': id,
        'payment_amount': amount,
        'p_payment_method': paymentMethod,
      },
    );

    final response = await _supabase
        .from('euromillions_participations')
        .select()
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(response);
  }

  List<int> _parseAndValidate(
    String raw,
    int expectedCount,
    int minimum,
    int maximum,
    String label,
  ) {
    final parsed = raw
        .split(RegExp(r'[,;\s]+'))
        .where((value) => value.isNotEmpty)
        .map(int.tryParse)
        .toList();
    if (parsed.length != expectedCount || parsed.any((value) => value == null)) {
      throw ArgumentError('Indica exatamente $expectedCount $label.');
    }
    final values = parsed.cast<int>();
    if (values.toSet().length != expectedCount ||
        values.any((value) => value < minimum || value > maximum)) {
      throw ArgumentError('$label inválidos ou repetidos.');
    }
    values.sort();
    return values;
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
