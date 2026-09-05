import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/inventory_advanced_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PermissionPolicy.reset();
    AppSession.instance.role = 'Administrador';
  });

  tearDown(PermissionPolicy.reset);

  test('membro consulta inventário mas não gere lotes e quebras', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewInventory),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.manageInventory),
      isFalse,
    );
  });

  test('responsável de inventário tem gestão avançada', () {
    expect(
      PermissionPolicy.allows(
        AppRole.inventoryManager,
        AppPermission.manageInventory,
      ),
      isTrue,
    );
  });

  test('reserva demo nasce ativa por 30 dias e pode ser cancelada', () async {
    AppSession.instance.role = 'Membro';
    final repository = InventoryAdvancedRepository();
    final stock = await repository.stockRows();
    final row = stock.first;

    final id = await repository.createReservation(
      productId: row['product_id'].toString(),
      variantId: row['variant_id']?.toString(),
      locationId: row['location_id'].toString(),
      quantity: 2,
    );

    final reservations = await repository.reservations();
    expect(reservations, hasLength(1));
    expect(reservations.first['id'], id);
    expect(reservations.first['status'], 'active');
    expect(reservations.first['days_remaining'], 30);

    final reservedAt = DateTime.parse(reservations.first['reserved_at'].toString());
    final expiresAt = DateTime.parse(reservations.first['expires_at'].toString());
    expect(expiresAt.difference(reservedAt), const Duration(days: 30));

    await repository.closeReservation(id, action: 'cancel');
    expect((await repository.reservations()).first['status'], 'cancelled');
  });

  test('membro não pode receber lotes', () async {
    AppSession.instance.role = 'Membro';
    final repository = InventoryAdvancedRepository();
    expect(repository.canManage, isFalse);
    await expectLater(
      repository.receiveLot(
        productId: 'product-water',
        locationId: 'loc-main',
        lotCode: 'L001',
        quantity: 10,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('gestor recebe lote e regista quebra em demonstração', () async {
    AppSession.instance.role = 'Responsável Inventário';
    final repository = InventoryAdvancedRepository();

    final lotId = await repository.receiveLot(
      productId: 'product-water',
      locationId: 'loc-main',
      lotCode: 'AGUA-2026-01',
      quantity: 20,
      expiresAt: DateTime.now().add(const Duration(days: 25)),
      unitCost: 0.19,
    );
    final lots = await repository.lots();
    expect(lots, hasLength(1));
    expect(lots.first['id'], lotId);
    expect(lots.first['status'], 'active');

    await repository.recordBreakage(
      productId: 'product-water',
      locationId: 'loc-main',
      quantity: 3,
      reason: 'damage',
      lotId: lotId,
    );
    final breakages = await repository.breakages();
    expect(breakages, hasLength(1));
    expect(breakages.first['quantity'], 3);
    expect(breakages.first['reason'], 'damage');

    final summary = await repository.summary();
    expect(inventoryQuantity(summary['breakage_units_month']), 3);
    expect(summary['lots_expiring_30d'], 1);
  });

  test('helpers apresentam estados e motivos em português', () {
    expect(inventoryReservationStatusLabel('expired'), 'Expirada');
    expect(inventoryLotStatusLabel('quarantined'), 'Quarentena');
    expect(inventoryBreakageReasonLabel('expiry'), 'Validade');
    expect(inventoryQuantity('2.5'), 2.5);
  });
}
