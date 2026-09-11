import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/core/notification_center.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(PermissionPolicy.reset);

  test('viewBar pode ser concedido sem viewInventory', () {
    PermissionPolicy.configure(
      permissionKeys: const ['viewBar'],
      superAdmin: false,
    );

    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewBar),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewInventory),
      isFalse,
    );
  });

  test('BAR é um módulo principal próprio antes de Inventário', () {
    final barIndex = appModules.indexWhere((module) => module.code == 'bar');
    final inventoryIndex =
        appModules.indexWhere((module) => module.code == 'inventory');

    expect(barIndex, greaterThanOrEqualTo(0));
    expect(inventoryIndex, greaterThan(barIndex));
    expect(appModules[barIndex].title, 'BAR');
  });

  test('notificações do BAR já não abrem Inventário', () {
    expect(notificationModuleFromRoute('bar'), 'bar');
    expect(notificationModuleFromRoute('/bar/sales'), 'bar');
    expect(notificationModuleFromRoute('shop'), 'inventory');
    expect(notificationModuleFromRoute('inventory'), 'inventory');
  });
}
