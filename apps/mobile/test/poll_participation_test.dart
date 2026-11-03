import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/polls_repository.dart';
import 'package:bob_manager_mobile/screens/poll_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const clubId = '00000000-0000-0000-0000-000000000001';

PollDemoElector elector(
  String profileId, {
  String club = clubId,
  AppRole role = AppRole.member,
  bool active = true,
  bool canView = true,
}) =>
    PollDemoElector(
      clubId: club,
      profileId: profileId,
      role: role,
      active: active,
      canViewCommunication: canView,
    );

Future<Map<String, dynamic>> publishedPoll(
  PollsRepository repository, {
  bool multiple = false,
  bool showResults = false,
}) async {
  final now = DateTime.now();
  final id = await repository.saveDraft(
    title: 'Participação agregada',
    pollType: 'vote',
    anonymous: true,
    multipleChoice: multiple,
    showResultsBeforeClose: showResults,
    startsAt: now.subtract(const Duration(minutes: 1)),
    endsAt: now.add(const Duration(days: 1)),
    optionLabels: const ['Sim', 'Não'],
  );
  await repository.setStatus(id, 'published');
  return (await repository.listPolls()).single;
}

Future<void> voteAs(
  PollsRepository repository,
  String pollId,
  String profileId, {
  bool multiple = false,
}) async {
  final previous = AppSession.instance.profileId;
  AppSession.instance.profileId = profileId;
  try {
    final options = await repository.options(pollId);
    await repository.castVote(
      pollId,
      (multiple ? options : options.take(1))
          .map((option) => option['id'].toString()),
    );
  } finally {
    AppSession.instance.profileId = previous;
  }
}

Future<void> showDetail(
  WidgetTester tester,
  PollsRepository repository,
  Map<String, dynamic> poll,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: PollDetailScreen(repository: repository, poll: poll)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.role = 'Secretário';
  });
  tearDown(() => AppSession.instance.clear());

  test('participação 1 de 2 é 50% mesmo com duas seleções', () async {
    final repository = PollsRepository(
      demoElectors: [elector('first'), elector('second')],
    );
    final poll = await publishedPoll(repository, multiple: true);
    await voteAs(repository, poll['id'].toString(), 'first', multiple: true);
    final participation = await repository.participation(poll['id'].toString());
    expect(participation.eligibleCount, 2);
    expect(participation.votedCount, 1);
    expect(participation.remainingCount, 1);
    expect(participation.participationPercent, 50);
    expect(await repository.results(poll['id'].toString()), isEmpty);
  });

  test('demo exclui inativos, prospects, unknown, sem permissão e outro clube',
      () async {
    final electors = [
      elector('first'),
      elector('first'),
      elector('inactive', active: false),
      elector('prospect', role: AppRole.prospect),
      elector('unknown', role: AppRole.unknown),
      elector('denied', canView: false),
      elector('other', club: 'other-club'),
    ];
    final repository = PollsRepository(demoElectors: electors);
    final poll = await publishedPoll(repository);
    final id = poll['id'].toString();
    await voteAs(repository, id, 'first');
    expect((await repository.participation(id)).votedCount, 1);
    electors[0] = elector('first', active: false);
    electors[1] = elector('first', active: false);
    final participation = await repository.participation(id);
    expect(participation.eligibleCount, 0);
    expect(participation.votedCount, 0);
    expect(participation.remainingCount, 0);
    expect(participation.participationPercent, 0);
  });

  test('consulta de participação exige gestão e valida clube/votação', () async {
    final repository = PollsRepository();
    final poll = await publishedPoll(repository);
    AppSession.instance.role = 'Membro';
    await expectLater(
      repository.participation(poll['id'].toString()),
      throwsA(isA<StateError>()),
    );
    AppSession.instance.role = 'Secretário';
    AppSession.instance.clubId = 'other-club';
    await expectLater(
      repository.participation(poll['id'].toString()),
      throwsA(isA<StateError>()),
    );
  });

  test('modelo aceita numeric serializado pelo RPC', () {
    final participation = PollParticipation.fromRow({
      'eligible_count': 2,
      'voted_count': 1,
      'remaining_count': 1,
      'participation_percent': '50.000000',
    });
    expect(participation.participationPercent, 50);
  });

  testWidgets('gestão vê participação com resultados ocultos e sem nomes',
      (tester) async {
    final repository = PollsRepository(
      demoElectors: [elector('first'), elector('second')],
    );
    final poll = await publishedPoll(repository);
    await voteAs(repository, poll['id'].toString(), 'first');
    await showDetail(tester, repository, poll);
    expect(find.text('Participação'), findsOneWidget);
    expect(find.text('1 de 2 votaram · 50%'), findsOneWidget);
    expect(find.text('Falta votar: 1'), findsOneWidget);
    expect(find.text('Resultados ainda ocultos'), findsOneWidget);
    expect(find.textContaining('seleções registadas'), findsNothing);
    expect(find.textContaining('first'), findsNothing);
    expect(find.textContaining('second'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sem manageCommunication não mostra participação', (tester) async {
    final repository = PollsRepository();
    final poll = await publishedPoll(repository);
    AppSession.instance.role = 'Membro';
    await showDetail(tester, repository, poll);
    expect(find.text('Participação'), findsNothing);
    expect(find.text('Submeter voto'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero elegíveis mostra 0% sem mensagem de participação completa',
      (tester) async {
    final repository = PollsRepository(demoElectors: const []);
    final poll = await publishedPoll(repository);
    await showDetail(tester, repository, poll);
    expect(find.text('0 eleitores elegíveis'), findsOneWidget);
    expect(find.text('Participação: 0%'), findsOneWidget);
    expect(find.text('Todos os eleitores elegíveis já votaram.'), findsNothing);
  });

  testWidgets('participação completa continua visível após encerrar',
      (tester) async {
    final repository = PollsRepository(
      demoElectors: [elector('first'), elector('second')],
    );
    final poll = await publishedPoll(repository);
    final id = poll['id'].toString();
    await voteAs(repository, id, 'first');
    await voteAs(repository, id, 'second');
    await repository.setStatus(id, 'closed');
    await showDetail(tester, repository, (await repository.listPolls()).single);
    expect(find.text('2 de 2 votaram · 100%'), findsOneWidget);
    expect(find.text('Todos os eleitores elegíveis já votaram.'), findsOneWidget);
    expect(find.textContaining('Falta votar:'), findsNothing);
  });

  testWidgets('Atualizar recalcula participação após novo voto', (tester) async {
    final repository = PollsRepository(
      demoElectors: [elector('first'), elector('second')],
    );
    final poll = await publishedPoll(repository);
    await showDetail(tester, repository, poll);
    expect(find.text('0 de 2 votaram · 0%'), findsOneWidget);
    await voteAs(repository, poll['id'].toString(), 'first');
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 votaram · 50%'), findsOneWidget);
    expect(find.text('Falta votar: 1'), findsOneWidget);
  });

  testWidgets('voto do gestor atualiza participação sem revelar resultados',
      (tester) async {
    final repository = PollsRepository(
      demoElectors: [elector('demo-profile'), elector('second')],
    );
    final poll = await publishedPoll(repository);
    await showDetail(tester, repository, poll);
    await tester.tap(find.text('Sim'));
    await tester.pump();
    await tester.tap(find.text('Submeter voto'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2 votaram · 50%'), findsOneWidget);
    expect(find.text('Voto submetido'), findsOneWidget);
    expect(find.text('Resultados ainda ocultos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resultados antecipados mantêm-se independentes da participação',
      (tester) async {
    final repository = PollsRepository(
      demoElectors: [elector('first'), elector('second')],
    );
    final poll = await publishedPoll(repository, showResults: true);
    await voteAs(repository, poll['id'].toString(), 'first');
    await showDetail(tester, repository, poll);
    expect(find.text('1 de 2 votaram · 50%'), findsOneWidget);
    expect(find.text('1 seleção registada'), findsOneWidget);
    expect(find.text('Resultados ainda ocultos'), findsNothing);
  });

  testWidgets('rascunhos e canceladas não mostram participação', (tester) async {
    final repository = PollsRepository();
    final poll = await publishedPoll(repository);
    await repository.setStatus(poll['id'].toString(), 'cancelled');
    await showDetail(tester, repository, (await repository.listPolls()).single);
    expect(find.text('Participação'), findsNothing);
    await tester.pumpWidget(
      MaterialApp(
        home: PollDetailScreen(
          repository: repository,
          poll: {...poll, 'status': 'draft'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Participação'), findsNothing);
  });
}
