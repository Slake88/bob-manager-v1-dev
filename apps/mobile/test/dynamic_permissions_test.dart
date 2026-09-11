import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PermissionPolicy.reset);

  test('matriz dinâmica substitui permissões fixas do cargo', () {
    PermissionPolicy.configure(
      permissionKeys: const ['viewTreasury', 'createTreasuryMovement'],
      superAdmin: false,
    );

    expect(
      PermissionPolicy.allows(AppRole.secretary, AppPermission.viewTreasury),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.createTreasuryMovement,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.transferBetweenAccounts,
      ),
      isFalse,
    );
  });

  test('Super Admin mantém acesso total independentemente da matriz', () {
    PermissionPolicy.configure(permissionKeys: const [], superAdmin: true);

    for (final permission in AppPermission.values) {
      expect(
        PermissionPolicy.allows(AppRole.administrator, permission),
        isTrue,
        reason: permission.name,
      );
    }
  });
}
