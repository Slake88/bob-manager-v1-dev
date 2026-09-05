import 'package:bob_manager_mobile/screens/inventory_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'inventário usa pré-visualização segura no modo demonstração',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: InventoryHubScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Assertion failed'), findsNothing);

      await tester.tap(find.widgetWithText(Tab, 'Loja'));
      await tester.pumpAndSettle();

      expect(
        find.text('Pré-visualização em modo demonstração'),
        findsOneWidget,
      );
      expect(find.textContaining('Supabase.instance'), findsNothing);
    },
  );
}
