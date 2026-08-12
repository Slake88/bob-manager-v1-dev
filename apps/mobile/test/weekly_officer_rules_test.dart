import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/weekly_officer_rules.dart';

void main() {
  group('WeeklyOfficerRules', () {
    test('gestão fica limitada a Superadmin, Presidente e Vice-Presidente', () {
      expect(WeeklyOfficerRules.canManageRole('president'), isTrue);
      expect(WeeklyOfficerRules.canManageRole('Vice-Presidente'), isTrue);
      expect(WeeklyOfficerRules.canManageRole('super_admin'), isTrue);
      expect(WeeklyOfficerRules.canManageRole('Tesoureiro'), isFalse);
      expect(WeeklyOfficerRules.canManageRole('Membro'), isFalse);
    });

    test('quinta oficial fechada não conta', () {
      expect(
        WeeklyOfficerRules.countsAsOfficialDinner({
          'dinner_kind': 'regular',
          'status': 'closed',
          'assigned_member_id': null,
        }),
        isFalse,
      );
    });

    test('jantar extraordinário não entra na justiça anual', () {
      expect(
        WeeklyOfficerRules.countsAsOfficialDinner({
          'dinner_kind': 'extraordinary',
          'status': 'completed',
          'assigned_member_id': 'member-1',
        }),
        isFalse,
      );
    });

    test('quinta oficial planeada com membro conta', () {
      expect(
        WeeklyOfficerRules.countsAsOfficialDinner({
          'dinner_kind': 'regular',
          'status': 'planned',
          'assigned_member_id': 'member-1',
        }),
        isTrue,
      );
    });

    test('alcunha tem prioridade no nome visível', () {
      expect(
        WeeklyOfficerRules.displayMember({
          'full_name': 'Israel Sousa',
          'nickname': 'Lela',
        }),
        'Lela',
      );
    });

    test('estado aceite explicita que a Direção ainda tem de aplicar', () {
      expect(
        WeeklyOfficerRules.swapStatusLabel('accepted'),
        contains('aguarda Direção'),
      );
    });
  });
}
