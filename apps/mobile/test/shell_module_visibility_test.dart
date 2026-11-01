import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => AppSession.instance.clear());

  testWidgets('os 17 módulos aparecem em desktop, tablet e mobile mesmo sem permissões de consulta',
      (tester) async {
    _authenticateWith(const [], role: 'member');

    await _pumpAt(tester, const Size(1600, 1000));
    await _expectDrawerModules(tester, appModules.map((module) => module.title));
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, const Size(800, 1000));
    final tabletPrimary = _railLabels(tester);
    expect(tabletPrimary, contains('Mais'));
    await tester.tap(_railMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      tabletPrimary,
      appModules.map((module) => module.title),
    );

    await _pumpAt(tester, const Size(390, 844));
    final mobilePrimary = _bottomLabels(tester);
    expect(mobilePrimary, contains('Mais'));
    await tester.tap(_bottomMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      mobilePrimary,
      appModules.map((module) => module.title),
    );
  });

  testWidgets('o perfil Bar e Inventário mantém a navegação completa',
      (tester) async {
    _authenticateWith(
      const [
        'viewBar',
        'manageBar',
        'viewInventory',
        'manageInventory',
        'sellInventory',
        'manageMerchandising',
        'manageAssets',
        'performInventoryCount',
      ],
      role: 'inventory_manager',
    );

    await _pumpAt(tester, const Size(1600, 1000));
    await _expectDrawerModules(tester, appModules.map((module) => module.title));
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, const Size(800, 1000));
    final tabletPrimary = _railLabels(tester);
    expect(tabletPrimary, contains('Mais'));
    await tester.tap(_railMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      tabletPrimary,
      appModules.map((module) => module.title),
    );
    await _pumpAt(tester, const Size(390, 844));
    final mobilePrimary = _bottomLabels(tester);
    expect(mobilePrimary, contains('Mais'));
    await tester.tap(_bottomMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      mobilePrimary,
      appModules.map((module) => module.title),
    );
  });

  testWidgets('a navegação do membro inclui módulos sem acesso aos dados',
      (tester) async {
    _authenticateWith(const ['viewMembers'], role: 'member');

    await _pumpAt(tester, const Size(1600, 1000));
    await _expectDrawerModules(tester, appModules.map((module) => module.title));
    expect(_drawerHasModule(tester, 'BAR'), isTrue);
    expect(_drawerHasModule(tester, 'Património & Inventário'), isTrue);
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, const Size(800, 1000));
    final tabletPrimary = _railLabels(tester);
    expect(tabletPrimary, contains('Membros'));
    await tester.tap(_railMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      tabletPrimary,
      appModules.map((module) => module.title),
    );

    await _pumpAt(tester, const Size(390, 844));
    final mobilePrimary = _bottomLabels(tester);
    expect(mobilePrimary, contains('Membros'));
    await tester.tap(_bottomMore);
    await tester.pumpAndSettle();
    await _expectAllInMoreSheet(
      tester,
      mobilePrimary,
      appModules.map((module) => module.title),
    );
  });
}

void _authenticateWith(
  Iterable<String> permissionKeys, {
  required String role,
}) {
  final session = AppSession.instance;
  session.clear();
  session.authenticate(
    newProfileId: 'synthetic-menu-profile',
    newClubId: 'synthetic-menu-club',
    newFullName: 'Perfil sintético de navegação',
    newRole: role,
  );
  session.applyPermissions(permissionKeys);
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
  await tester.pumpAndSettle();
}

Future<void> _expectDrawerModules(
  WidgetTester tester,
  Iterable<String> expected,
) async {
  final scrollable = find
      .descendant(
        of: find.byType(NavigationDrawer),
        matching: find.byType(Scrollable),
      )
      .first;
  for (final title in expected) {
    final finder = find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(title),
    );
    await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
    expect(finder, findsOneWidget, reason: 'Drawer: $title');
  }
}

bool _drawerHasModule(WidgetTester tester, String title) => find
    .descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(title),
    )
    .evaluate()
    .isNotEmpty;

List<String> _railLabels(WidgetTester tester) => appModules
    .map((module) => module.title)
    .where(
      (title) => find
          .descendant(
            of: find.byType(NavigationRail),
            matching: find.text(title),
          )
          .evaluate()
          .isNotEmpty,
    )
    .toList()
  ..addAll(
    find
            .descendant(
              of: find.byType(NavigationRail),
              matching: find.text('Mais'),
            )
            .evaluate()
            .isNotEmpty
        ? ['Mais']
        : const [],
  );

List<String> _bottomLabels(WidgetTester tester) => tester
    .widgetList<NavigationDestination>(find.byType(NavigationDestination))
    .map((destination) => destination.label)
    .toList();

Finder get _railMore => find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('Mais'),
    );

Finder get _bottomMore => find.byWidgetPredicate(
      (widget) => widget is NavigationDestination && widget.label == 'Mais',
    );

Future<void> _expectAllInMoreSheet(
  WidgetTester tester,
  List<String> primaryLabels,
  Iterable<String> expectedTitles,
) async {
  final grid = find.byType(GridView).first;
  final scrollable = find
      .descendant(
        of: grid,
        matching: find.byType(Scrollable),
      )
      .first;
  for (final title in expectedTitles) {
    if (primaryLabels.contains(title)) continue;
    final finder = find.descendant(
      of: grid,
      matching: find.text(title),
    );
    await tester.scrollUntilVisible(finder, 100, scrollable: scrollable);
    expect(finder, findsOneWidget, reason: 'Mais: $title');
  }
}
