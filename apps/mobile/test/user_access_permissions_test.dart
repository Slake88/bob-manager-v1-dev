import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/screens/user_access_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PermissionPolicy.reset);

  test('manageUserAccess pode ser delegado sem manageSettings', () {
    PermissionPolicy.configure(
      permissionKeys: const ['manageUserAccess'],
      superAdmin: false,
    );

    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageUserAccess,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageSettings,
      ),
      isFalse,
    );
  });

  test('Super Admin mantém manageUserAccess', () {
    PermissionPolicy.configure(permissionKeys: const [], superAdmin: true);

    expect(
      PermissionPolicy.allows(
        AppRole.administrator,
        AppPermission.manageUserAccess,
      ),
      isTrue,
    );
  });

  test('AppRole reconhece perfis aceites em club_memberships', () {
    expect(AppRole.fromValue('president'), AppRole.president);
    expect(AppRole.fromValue('vice_president'), AppRole.vicePresident);
    expect(AppRole.fromValue('road_captain'), AppRole.roadCaptain);
    expect(
      AppRole.fromValue('sergeant_at_arms'),
      AppRole.sergeantAtArms,
    );
    expect(
      AppRole.fromValue('Sargento de Armas'),
      AppRole.sergeantAtArms,
    );
    expect(
      AppRole.fromValue('euromillions_manager'),
      AppRole.euromillionsManager,
    );
  });

  test('Sargento de Armas é atribuível sem privilégios administrativos fixos', () {
    expect(
      userAccessRoles.any(
        (role) =>
            role.key == 'sergeant_at_arms' && role.label == 'Sargento de Armas',
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.sergeantAtArms,
        AppPermission.viewMembers,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.sergeantAtArms,
        AppPermission.manageUserAccess,
      ),
      isFalse,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.sergeantAtArms,
        AppPermission.manageSettings,
      ),
      isFalse,
    );
  });
}
