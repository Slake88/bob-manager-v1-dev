import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/polls_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PermissionPolicy.reset();
    AppSession.instance
      ..role = 'Administrador'
      ..profileId = 'demo-profile';
  });

  tearDown(PermissionPolicy.reset);

  test('POLL-UNIT-01 elegibilidade e gestão seguem Comunicação', () {
    AppSession.instance.role = 'Membro';
    var repository = PollsRepository();
    expect(repository.canView, isTrue);
    expect(repository.canManage, isFalse);
    expect(repository.isEligible, isTrue);

    AppSession.instance.role = 'Prospect';
    repository = PollsRepository();
    expect(repository.canView, isTrue);
    expect(repository.isEligible, isFalse);

    AppSession.instance.role = 'Secretário';
    repository = PollsRepository();
    expect(repository.canManage, isTrue);
    expect(
      PermissionPolicy.allows(AppRole.secretary, AppPermission.manageCommunication),
      isTrue,
    );
  });

  test('POLL-INT-01 criar, publicar, votar uma vez e fechar', () async {
    AppSession.instance.role = 'Secretário';
    final repository = PollsRepository();
    final now = DateTime.now();
    final pollId = await repository.saveDraft(
      title: 'Aprovar proposta?',
      pollType: 'vote',
      anonymous: true,
      multipleChoice: false,
      showResultsBeforeClose: false,
      startsAt: now.subtract(const Duration(minutes: 1)),
      endsAt: now.add(const Duration(days: 3)),
      optionLabels: const ['Sim', 'Não'],
    );
    expect((await repository.listPolls()).first['status'], 'draft');
    expect(await repository.options(pollId), hasLength(2));

    await repository.setStatus(pollId, 'published');
    AppSession.instance.role = 'Membro';
    final polls = await repository.listPolls();
    final poll = polls.firstWhere((row) => row['id'] == pollId);
    expect(pollIsOpen(poll), isTrue);

    final options = await repository.options(pollId);
    await repository.castVote(pollId, [options.first['id'].toString()]);
    expect(await repository.ownVotes(pollId), hasLength(1));
    await expectLater(
      repository.castVote(pollId, [options.last['id'].toString()]),
      throwsA(isA<StateError>()),
    );
    expect(await repository.results(pollId), isEmpty);

    AppSession.instance.role = 'Secretário';
    await repository.setStatus(pollId, 'closed');
    AppSession.instance.role = 'Membro';
    final results = await repository.results(pollId);
    expect(results, hasLength(1));
    expect(results.single['vote_count'], 1);
  });

  test('inquérito de escolha múltipla aceita várias opções no mesmo voto', () async {
    AppSession.instance.role = 'Secretário';
    final repository = PollsRepository();
    final now = DateTime.now();
    final pollId = await repository.saveDraft(
      title: 'Que atividades preferes?',
      pollType: 'survey',
      anonymous: false,
      multipleChoice: true,
      showResultsBeforeClose: true,
      startsAt: now.subtract(const Duration(minutes: 1)),
      endsAt: now.add(const Duration(days: 7)),
      optionLabels: const ['Passeios', 'Eventos', 'Solidariedade'],
    );
    await repository.setStatus(pollId, 'published');

    AppSession.instance.role = 'Membro';
    final options = await repository.options(pollId);
    await repository.castVote(
      pollId,
      [options[0]['id'].toString(), options[2]['id'].toString()],
    );
    expect(await repository.ownVotes(pollId), hasLength(2));
    final results = await repository.results(pollId);
    expect(
      results.fold<int>(
        0,
        (total, row) => total + (int.tryParse(row['vote_count'].toString()) ?? 0),
      ),
      2,
    );
  });

  test('helpers calculam agendamento, fecho e visibilidade de resultados', () {
    final now = DateTime.utc(2026, 8, 30, 18);
    final scheduled = <String, dynamic>{
      'status': 'published',
      'starts_at': now.add(const Duration(hours: 1)).toIso8601String(),
      'ends_at': now.add(const Duration(hours: 2)).toIso8601String(),
      'show_results_before_close': false,
    };
    expect(pollEffectiveStatus(scheduled, now: now), 'scheduled');
    expect(pollIsOpen(scheduled, now: now), isFalse);
    expect(
      pollResultsVisible(scheduled, canManage: false, now: now),
      isFalse,
    );

    final ended = <String, dynamic>{
      ...scheduled,
      'starts_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'ends_at': now.subtract(const Duration(minutes: 1)).toIso8601String(),
    };
    expect(pollEffectiveStatus(ended, now: now), 'closed');
    expect(pollResultsVisible(ended, canManage: false, now: now), isTrue);
  });
}
