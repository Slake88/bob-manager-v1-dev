import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/events_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSession.instance.role = 'Administrador';
  });

  test('responsável de eventos gere eventos e participantes', () {
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageEvents,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageEventParticipants,
      ),
      isTrue,
    );
  });

  test('membro consulta eventos mas não os altera', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewEvents),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.manageEvents),
      isFalse,
    );
  });

  test('evento aceita participante, acompanhante e voluntário', () async {
    final repository = EventsRepository();
    final events = await repository.listEvents();
    expect(events, isNotEmpty);
    final eventId = events.first['id'].toString();

    await repository.addParticipant(
      eventId: eventId,
      memberId: 'm1',
      memberName: 'Israel Sousa',
      companionName: 'Acompanhante',
    );
    await repository.addVolunteer(
      eventId: eventId,
      memberId: 'm2',
      memberName: 'Fernando Martins',
      functionName: 'Road Captain',
    );

    final participants = await repository.participants(eventId);
    final volunteers = await repository.volunteers(eventId);
    expect(participants.any((row) => row['member_id'] == 'm1'), isTrue);
    expect(participants.any((row) => row['companion_name'] == 'Acompanhante'), isTrue);
    expect(volunteers.any((row) => row['member_id'] == 'm2'), isTrue);
  });

  test('resumo financeiro do evento separa receitas e despesas', () async {
    final repository = EventsRepository();
    final events = await repository.listEvents();
    final summary = await repository.financialSummary(events.first['id'].toString());
    expect(summary['income'], isA<double>());
    expect(summary['expense'], isA<double>());
    expect(summary['result'], isA<double>());
  });
}
