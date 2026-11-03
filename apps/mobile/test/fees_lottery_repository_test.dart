import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/fees_repository.dart';
import 'package:bob_manager_mobile/repositories/lottery_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSession.instance.role = 'Administrador';
    AppSession.instance.profileId = 'demo-profile';
  });

  test('Quotas são ligadas aos membros e calculam saldo', () async {
    final repository = FeesRepository();
    final members = await repository.listMembers();
    expect(members, isNotEmpty);

    final created = await repository.saveObligation({
      'member_id': members.first['id'],
      'member_name': members.first['full_name'],
      'period_label': 'Teste RC1',
      'due_date': '2026-08-10',
      'amount': 25.0,
      'paid_amount': 10.0,
      'credit_amount': 0.0,
      'status': 'pending',
    });

    expect(created['member_id'], members.first['id']);
    expect(created['balance'], 15.0);
    expect(created['status'], 'partial');
  });

  test('Pagamento de quota entra na conta Quotas', () async {
    final repository = FeesRepository();
    final rows = await repository.listObligations();
    final obligation = rows.firstWhere(
      (row) => (row['balance'] as num?)?.toDouble() != 0,
    );

    final updated = await repository.registerPayment(
      obligation: obligation,
      amount: 5.0,
      paymentMethod: 'MB Way',
    );

    expect(
      (updated['paid_amount'] as num).toDouble(),
      greaterThan((obligation['paid_amount'] as num?)?.toDouble() ?? 0),
    );
  });

  test('Euromilhões valida chave e liga participante a membro', () async {
    final repository = LotteryRepository();
    final members = await repository.listMembers();

    final created = await repository.saveParticipant({
      'member_id': members.last['id'],
      'member_name': members.last['full_name'],
      'billing_frequency': 'weekly',
      'participant_amount': 5.0,
      'numbers': '1, 10, 20, 30, 40',
      'stars': '2, 11',
      'paid_amount': 0.0,
      'balance': 5.0,
      'active': true,
    });

    expect(created['member_id'], members.last['id']);
    expect(created['numbers'], '1, 10, 20, 30, 40');
  });

  test('Euromilhões rejeita chaves inválidas', () async {
    final repository = LotteryRepository();
    final members = await repository.listMembers();

    expect(
      () => repository.saveParticipant({
        'member_id': members.first['id'],
        'member_name': members.first['full_name'],
        'billing_frequency': 'weekly',
        'participant_amount': 5.0,
        'numbers': '1, 1, 2',
        'stars': '1',
      }),
      throwsArgumentError,
    );
  });
}
