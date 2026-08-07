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

  bool get canManage => PermissionPolicy.allows(
        currentRole,
        AppPermission.manageLottery,
      );

  bool get canOperateMoney {
    final role = AppSession.instance.role.toLowerCase();
    return currentRole == AppRole.treasurer ||
        role == 'treasurer' ||
        role == 'super_admin' ||
        role == 'super admin';
  }

  Future<Map<String, dynamic>> loadMonth(int year, int month) async {
    _require(AppPermission.viewLottery);
    if (AppConfig.demoMode) {
      final participants = await listParticipants();
      return {
        'players': participants
            .map((row) => {
                  ...row,
                  'player_id': row['id'],
                  'status': row['active'] == false ? 'inactive' : 'active',
                })
            .toList(),
        'charges': <Map<String, dynamic>>[],
        'results': <Map<String, dynamic>>[],
        'fines': <Map<String, dynamic>>[],
        'weekly_amount': 4.40,
        'fine_per_miss': 0.10,
      };
    }

    await _supabase.rpc(
      'generate_euromillions_charges_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_year': year,
        'p_month': month,
      },
    );

    final first = DateTime(year, month, 1);
    final next = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    final chargeStart = first.subtract(const Duration(days: 6));
    final firstIso = _dateOnly(first);
    final nextIso = _dateOnly(next);

    final results = await Future.wait([
      _supabase
          .from('euromillions_players')
          .select('*, member:members!inner(id,full_name,nickname)')
          .eq('club_id', AppSession.instance.clubId),
      _supabase
          .from('euromillions_weekly_charges')
          .select()
          .eq('club_id', AppSession.instance.clubId)
          .gte('week_start', _dateOnly(chargeStart))
          .lt('week_start', nextIso)
          .order('week_start'),
      _supabase
          .from('euromillions_results')
          .select()
          .eq('club_id', AppSession.instance.clubId)
          .gte('draw_date', firstIso)
          .lt('draw_date', nextIso)
          .order('draw_date'),
      _supabase
          .from('euromillions_fines')
          .select('*, result:euromillions_results!inner(draw_date)')
          .eq('club_id', AppSession.instance.clubId),
      _supabase
          .from('club_settings')
          .select('key,value')
          .eq('club_id', AppSession.instance.clubId)
          .inFilter('key', [
        'euromillions_weekly_amount',
        'euromillions_fine_per_miss',
      ]),
    ]);

    final players = List<Map<String, dynamic>>.from(results[0] as List)
        .map((row) {
      final member = row['member'];
      return <String, dynamic>{
        ...row,
        'player_id': row['id'],
        'member_name': member is Map ? member['full_name'] : null,
        'member_nickname': member is Map ? member['nickname'] : null,
        'numbers_text': _intList(row['numbers']).join(', '),
        'stars_text': _intList(row['stars']).join(', '),
      };
    }).toList();
    players.sort((a, b) => (a['member_name']?.toString() ?? '')
        .compareTo(b['member_name']?.toString() ?? ''));

    final settings = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(results[4] as List)) {
      settings[row['key'].toString()] = row['value']?.toString() ?? '';
    }

    return {
      'players': players,
      'charges': List<Map<String, dynamic>>.from(results[1] as List),
      'results': List<Map<String, dynamic>>.from(results[2] as List),
      'fines': List<Map<String, dynamic>>.from(results[3] as List),
      'weekly_amount':
          double.tryParse(settings['euromillions_weekly_amount'] ?? '') ?? 4.40,
      'fine_per_miss':
          double.tryParse(settings['euromillions_fine_per_miss'] ?? '') ?? 0.10,
    };
  }

  Future<void> updatePlayer({
    required String playerId,
    required String status,
    required String numbers,
    required String stars,
  }) async {
    _require(AppPermission.manageLottery);
    final parsedNumbers = status == 'non_player' && numbers.trim().isEmpty
        ? <int>[]
        : _parseAndValidate(numbers, 5, 1, 50, 'números');
    final parsedStars = status == 'non_player' && stars.trim().isEmpty
        ? <int>[]
        : _parseAndValidate(stars, 2, 1, 12, 'estrelas');
    if (!['active', 'inactive', 'non_player'].contains(status)) {
      throw ArgumentError('Estado de jogador inválido.');
    }
    if (status == 'active' &&
        (parsedNumbers.length != 5 || parsedStars.length != 2)) {
      throw ArgumentError('Um jogador ativo precisa de uma chave completa.');
    }
    if (AppConfig.demoMode) return;
    await _supabase
        .from('euromillions_players')
        .update({
          'status': status,
          'numbers': parsedNumbers,
          'stars': parsedStars,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', playerId)
        .eq('club_id', AppSession.instance.clubId);
  }

  Future<void> saveSettings({
    required double weeklyAmount,
    required double finePerMiss,
  }) async {
    if (!canOperateMoney) {
      throw StateError(
        'Apenas o Tesoureiro ou Super Admin pode alterar estes valores.',
      );
    }
    if (weeklyAmount <= 0 || finePerMiss < 0) {
      throw ArgumentError('Valores de configuração inválidos.');
    }
    if (AppConfig.demoMode) return;
    for (final entry in {
      'euromillions_weekly_amount': weeklyAmount.toStringAsFixed(2),
      'euromillions_fine_per_miss': finePerMiss.toStringAsFixed(2),
    }.entries) {
      await _supabase.from('club_settings').upsert({
        'club_id': AppSession.instance.clubId,
        'key': entry.key,
        'value': entry.value,
        'updated_by': AppSession.instance.profileId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'club_id,key');
    }
  }

  Future<void> payWeek({
    required String chargeId,
    required String paymentMethod,
  }) async {
    if (!canOperateMoney) {
      throw StateError(
        'Apenas o Tesoureiro ou Super Admin pode registar pagamentos.',
      );
    }
    if (AppConfig.demoMode) return;
    await _supabase.rpc(
      'register_euromillions_week_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_charge': chargeId,
        'p_payment_method': paymentMethod,
      },
    );
  }

  Future<void> payMonth({
    required String playerId,
    required int year,
    required int month,
    required String paymentMethod,
  }) async {
    if (!canOperateMoney) {
      throw StateError(
        'Apenas o Tesoureiro ou Super Admin pode registar pagamentos.',
      );
    }
    if (AppConfig.demoMode) return;
    await _supabase.rpc(
      'register_euromillions_month_payment_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_player': playerId,
        'p_year': year,
        'p_month': month,
        'p_payment_method': paymentMethod,
      },
    );
  }

  Future<void> processResult({
    required DateTime drawDate,
    required String numbers,
    required String stars,
  }) async {
    if (!canOperateMoney) {
      throw StateError(
        'Apenas o Tesoureiro ou Super Admin pode processar resultados.',
      );
    }
    final parsedNumbers = _parseAndValidate(numbers, 5, 1, 50, 'números');
    final parsedStars = _parseAndValidate(stars, 2, 1, 12, 'estrelas');
    if (drawDate.weekday != DateTime.tuesday &&
        drawDate.weekday != DateTime.friday) {
      throw ArgumentError('O sorteio deve ser uma terça-feira ou sexta-feira.');
    }
    if (AppConfig.demoMode) return;
    await _supabase.rpc(
      'process_euromillions_result_v1',
      params: {
        'target_club': AppSession.instance.clubId,
        'p_draw_date': _dateOnly(drawDate),
        'p_numbers': parsedNumbers,
        'p_stars': parsedStars,
      },
    );
  }

  List<DateTime> drawDates(int year, int month) {
    final dates = <DateTime>[];
    var day = DateTime(year, month, 1);
    while (day.month == month) {
      if (day.weekday == DateTime.tuesday ||
          day.weekday == DateTime.friday) {
        dates.add(day);
      }
      day = day.add(const Duration(days: 1));
    }
    return dates;
  }

  DateTime weekStart(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  Future<List<Map<String, dynamic>>> listParticipants() async {
    _require(AppPermission.viewLottery);
    if (AppConfig.demoMode) {
      final rows = await _dataService.list('lottery_participants');
      rows.sort((a, b) => (a['member_name']?.toString() ?? '')
          .compareTo(b['member_name']?.toString() ?? ''));
      return rows;
    }
    final data = await loadMonth(DateTime.now().year, DateTime.now().month);
    return List<Map<String, dynamic>>.from(data['players'] as List)
        .where((row) => row['status'] != 'non_player')
        .map((row) => {
              ...row,
              'id': row['player_id'],
              'participant_amount': data['weekly_amount'],
              'numbers': row['numbers_text'],
              'stars': row['stars_text'],
              'active': row['status'] == 'active',
              'paid_amount': 0.0,
              'balance': 0.0,
            })
        .toList();
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
    final memberId = values['member_id']?.toString();
    if (memberId == null || memberId.isEmpty) {
      throw ArgumentError('Seleciona um membro.');
    }
    await _supabase.rpc(
      'sync_euromillions_players_v1',
      params: {'target_club': AppSession.instance.clubId},
    );
    final player = await _supabase
        .from('euromillions_players')
        .select()
        .eq('club_id', AppSession.instance.clubId)
        .eq('member_id', memberId)
        .single();
    await updatePlayer(
      playerId: player['id'].toString(),
      status: values['active'] == false ? 'inactive' : 'active',
      numbers: numbers.join(', '),
      stars: stars.join(', '),
    );
    return {
      ...Map<String, dynamic>.from(player),
      'member_id': memberId,
      'numbers': numbers.join(', '),
      'stars': stars.join(', '),
      'active': values['active'] != false,
    };
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
    if (AppConfig.demoMode) {
      final currentPaid = _asDouble(participant['paid_amount']);
      final currentBalance = _asDouble(participant['balance']);
      final participantId = participant['id']?.toString() ?? '';
      return _dataService.update('lottery_participants', participantId, {
        ...participant,
        'paid_amount': currentPaid + amount,
        'balance': (currentBalance - amount).clamp(0, double.infinity),
      });
    }
    throw StateError(
      'Usa o pagamento semanal ou mensal no novo módulo Euromilhões.',
    );
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
    if (parsed.length != expectedCount ||
        parsed.any((value) => value == null)) {
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

List<int> _intList(Object? value) {
  if (value is List) {
    return value.map((item) => int.parse(item.toString())).toList();
  }
  return const [];
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
