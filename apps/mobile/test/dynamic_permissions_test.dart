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

  test('Super Admin respeita um deny individual no conjunto efetivo', () {
    final effective = resolveEffectivePermissionKeys(
      superAdmin: true,
      roleRows: const [],
      userOverrides: const [
        {'permission_key': 'viewTreasury', 'allowed': false},
      ],
    );
    PermissionPolicy.configure(
      permissionKeys: effective,
      superAdmin: true,
    );

    expect(
      PermissionPolicy.allows(
          AppRole.administrator, AppPermission.viewTreasury),
      isFalse,
    );
    expect(
      PermissionPolicy.allows(
          AppRole.administrator, AppPermission.manageSettings),
      isTrue,
    );
  });
}
