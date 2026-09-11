import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/inventory_location_rules.dart';

void main() {
  group('InventoryLocationRules', () {
    test('aceita transferÃªncia vÃ¡lida', () {
      expect(
        InventoryLocationRules.validateTransfer(
          fromLocationId: 'a',
          toLocationId: 'b',
          quantity: 2,
          available: 5,
        ),
        isNull,
      );
    });

    test('rejeita origem e destino iguais', () {
      expect(
        InventoryLocationRules.validateTransfer(
          fromLocationId: 'a',
          toLocationId: 'a',
          quantity: 1,
          available: 5,
        ),
        isNotNull,
      );
    });

    test('rejeita quantidade superior ao disponÃ­vel', () {
      expect(
        InventoryLocationRules.validateTransfer(
          fromLocationId: 'a',
          toLocationId: 'b',
          quantity: 6,
          available: 5,
        ),
        isNotNull,
      );
    });

    test('rejeita quantidade nula ou negativa', () {
      expect(
        InventoryLocationRules.validateTransfer(
          fromLocationId: 'a',
          toLocationId: 'b',
          quantity: 0,
          available: 5,
        ),
        isNotNull,
      );
    });
  });
}
