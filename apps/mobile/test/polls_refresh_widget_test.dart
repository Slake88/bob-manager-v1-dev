import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/polls_repository.dart';
import 'package:bob_manager_mobile/screens/poll_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PermissionPolicy.reset();
    AppSession.instance
      ..role = 'Secretário'
      ..profileId = 'demo-profile';
  });

  tearDown(PermissionPolicy.reset);

  testWidgets('submeter voto atualiza detalhe sem Future dentro de setState',
      (tester) async {
    final repository = PollsRepository();
    final now = DateTime.now();
    final pollId = await repository.saveDraft(
      title: 'Teste de refresh do voto',
      pollType: 'vote',
      anonymous: true,
      multipleChoice: false,
      showResultsBeforeClose: false,
      startsAt: now.subtract(const Duration(minutes: 1)),
      endsAt: now.add(const Duration(days: 1)),
      optionLabels: const ['Sim', 'Não'],
    );
    await repository.setStatus(pollId, 'published');

    AppSession.instance.role = 'Membro';
    final poll = (await repository.listPolls())
        .firstWhere((row) => row['id'].toString() == pollId);

    await tester.pumpWidget(
      MaterialApp(
        home: PollDetailScreen(repository: repository, poll: poll),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Submeter voto'), findsOneWidget);
    await tester.tap(find.text('Sim'));
    await tester.pump();
    await tester.tap(find.text('Submeter voto'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Voto submetido'), findsOneWidget);
    expect(find.text('Submeter voto'), findsNothing);
    expect(await repository.ownVotes(pollId), hasLength(1));
  });
}
