import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/app_session.dart';

void main() {
  final session = AppSession.instance;

  tearDown(session.clear);

  bool allowedFor(String role) {
    session.clear();
    session.authenticate(
      newProfileId: 'profile-test',
      newClubId: 'club-test',
      newFullName: 'Teste',
      newRole: role,
    );
    return session.canEditMemberMilestoneDates;
  }

  test('Superadmin pode editar datas Prospect e Full Color', () {
    expect(allowedFor('super_admin'), isTrue);
  });

  test('Presidente pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Presidente'), isTrue);
  });

  test('Vice-Presidente pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Vice-Presidente'), isTrue);
  });

  test('Administrador normal não recebe esta permissão fixa', () {
    expect(allowedFor('Administrador'), isFalse);
  });

  test('Secretário não pode editar datas Prospect e Full Color', () {
    expect(allowedFor('Secretário'), isFalse);
  });
}
