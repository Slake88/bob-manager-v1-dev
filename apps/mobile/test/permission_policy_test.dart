import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direção tem acesso total', () {
    for (final role in <AppRole>[
      AppRole.president,
      AppRole.vicePresident,
      AppRole.administrator,
    ]) {
      for (final permission in AppPermission.values) {
        expect(
          PermissionPolicy.allows(role, permission),
          isTrue,
          reason: '$role deveria ter $permission',
        );
      }
    }
  });

  test('super_admin do Supabase é reconhecido como administrador', () {
    final role = AppRole.fromValue('super_admin');

    expect(role, AppRole.administrator);
    for (final permission in AppPermission.values) {
      expect(
        PermissionPolicy.allows(role, permission),
        isTrue,
        reason: 'super_admin deveria ter $permission',
      );
    }
  });

  test('tesoureiro movimenta dinheiro mas não gere contas', () {
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.transferBetweenAccounts,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.treasurer,
        AppPermission.manageFinancialAccounts,
      ),
      isFalse,
    );
  });

  test('membro comum apenas consulta e edita dados próprios', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewMembers),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.editOwnMemberProfile,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.viewTreasury,
      ),
      isFalse,
    );
  });
}
