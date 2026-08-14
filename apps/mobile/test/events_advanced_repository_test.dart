import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/events_advanced_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PermissionPolicy.reset();
    AppSession.instance.role = 'Administrador';
  });

  tearDown(PermissionPolicy.reset);

  test('membro pode propor mas não gerir operação', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.proposeEvents),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.manageEventOperations,
      ),
      isFalse,
    );
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.manageRockRide),
      isFalse,
    );
  });

  test('road captain gere roadbook e operação', () {
    expect(
      PermissionPolicy.allows(
        AppRole.roadCaptain,
        AppPermission.manageEventRoadbook,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.roadCaptain,
        AppPermission.manageEventOperations,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.roadCaptain,
        AppPermission.manageEventFinance,
      ),
      isFalse,
    );
  });

  test('tesoureiro aprova propostas e gere finanças do evento', () {
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.approveEventProposals,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.manageEventFinance,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.manageEventRoadbook,
      ),
      isFalse,
    );
  });

  test('responsável de eventos gere roadbook, operação e Rock Ride', () {
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageEventRoadbook,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageEventOperations,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageRockRide,
      ),
      isTrue,
    );
  });

  test('helpers de eventos avançados normalizam tipo e Octanas', () {
    expect(eventKindLabel('general'), 'Evento');
    expect(eventKindLabel('ride'), 'Passeio');
    expect(eventKindLabel('rock_ride_in'), 'Rock & Ride In');
    expect(
      octaneCardTotalUnits({
        'ten_card_units': 10,
        'ten_card_bonus': 1,
      }),
      11,
    );
  });

  test('overview avançado funciona em modo demonstração', () async {
    final repository = EventsAdvancedRepository();
    final overview = await repository.overview('demo-event');

    expect(overview['guests'], isA<int>());
    expect(overview['routes'], isA<int>());
    expect(overview['bands'], isA<int>());
    expect(overview['tasks_open'], isA<int>());
    expect(overview['shifts'], isA<int>());
    expect(overview['incidents_open'], isA<int>());
    expect(overview['octane_configured'], isTrue);
  });
}
