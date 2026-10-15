import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/inventory_repository.dart';
import 'package:bob_manager_mobile/services/data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSession.instance.role = 'Administrador';
  });

  test('responsável de inventário gere stock e vendas', () {
    expect(
      PermissionPolicy.allows(
        AppRole.inventoryManager,
        AppPermission.manageInventory,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.inventoryManager,
        AppPermission.sellInventory,
      ),
      isTrue,
    );
  });

  test('resumo identifica artigos e valor de stock', () async {
    final summary = await InventoryRepository().summary();
    expect(summary['product_count'], greaterThan(0));
    expect(summary['stock_value'], isA<double>());
    expect(summary['products'], isNotEmpty);
  });

  test('ajuste, reserva e venda atualizam stock e tesouraria', () async {
    final repository = InventoryRepository();
    final product = await repository.saveProduct({
      'name': 'Produto teste RC1',
      'sku': 'RC1-TEST',
      'category': 'Teste',
      'variant': 'Único',
      'location': 'Club House',
      'unit': 'unidade',
      'current_stock': 10.0,
      'reserved_stock': 0.0,
      'minimum_stock': 2.0,
      'cost': 2.0,
      'sale_price': 5.0,
      'active': true,
    });
    final id = product['id'].toString();

    await repository.adjustStock(
      productId: id,
      quantity: 5,
      reason: 'Entrada de teste',
    );
    await repository.reserveStock(
      productId: id,
      quantity: 2,
      description: 'Reserva de teste',
    );
    await repository.recordSale(
      productId: id,
      quantity: 3,
      unitPrice: 5,
      paymentMethod: 'Dinheiro',
      description: 'Venda de teste',
    );

    final updated = await DataService.instance.getById('products', id);
    expect(updated, isNotNull);
    expect(updated!['current_stock'], 12.0);
    expect(updated['reserved_stock'], 2.0);

    final transactions = await DataService.instance.list(
      'financial_transactions',
    );
    expect(
      transactions.any(
        (row) =>
            row['product_id']?.toString() == id &&
            row['account_name'] == 'Club House' &&
            row['amount'] == 15.0,
      ),
      isTrue,
    );

    final movements = await DataService.instance.list('inventory_movements');
    expect(
      movements.where((row) => row['product_id']?.toString() == id).length,
      3,
    );
  });

  test('não permite vender stock reservado', () async {
    final repository = InventoryRepository();
    final product = await repository.saveProduct({
      'name': 'Produto reservado RC1',
      'current_stock': 2.0,
      'reserved_stock': 2.0,
      'minimum_stock': 0.0,
      'cost': 1.0,
      'sale_price': 3.0,
      'active': true,
    });

    expect(
      () => repository.recordSale(
        productId: product['id'].toString(),
        quantity: 1,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
