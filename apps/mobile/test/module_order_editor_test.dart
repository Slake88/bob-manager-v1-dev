import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/repositories/module_order_repository.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('guardar ordem altera a navegação e persiste por utilizador',
      (tester) async {
    final store = _MemoryModuleOrderStore();
    await _pumpDesktop(tester, store);
    final defaultDestinations = tester
        .widgetList<NavigationDrawerDestination>(
            find.byType(NavigationDrawerDestination))
        .map((destination) => _labelText(destination.label));
    expect(defaultDestinations.take(2), ['Dashboard', 'Atividade']);
    await _openEditor(tester);

    await tester.tap(find.byTooltip('Descer Dashboard'));
    await tester.tap(find.text('Guardar ordem'));
    await tester.pumpAndSettle();

    expect(store.saved, hasLength(17));
    expect(store.saved!.first, 'activity');
    expect(store.saved![1], 'dashboard');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .pumpWidget(MaterialApp(home: ShellScreen(moduleOrderStore: store)));
    await tester.pumpAndSettle();
    final destinations = tester
        .widgetList<NavigationDrawerDestination>(
          find.byType(NavigationDrawerDestination),
        )
        .map((destination) => _labelText(destination.label))
        .toList();
    expect(destinations.take(2), ['Atividade', 'Dashboard']);
    for (final code in store.saved!) {
      await _expectDrawerModule(
        tester,
        appModules.firstWhere((module) => module.code == code).title,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelar descarta a ordem e repor restaura a ordem canónica',
      (tester) async {
    final store = _MemoryModuleOrderStore();
    await _pumpDesktop(tester, store);

    await _openEditor(tester);
    await tester.tap(find.byTooltip('Descer Dashboard'));
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();
    expect(store.saved, isNull);

    await _openEditor(tester);
    await tester.tap(find.byTooltip('Descer Dashboard'));
    await tester.tap(find.text('Repor ordem original'));
    await tester.tap(find.text('Guardar ordem'));
    await tester.pumpAndSettle();
    expect(store.deleted, isTrue);
    expect(store.saved, isNull);
  });

  testWidgets('os controlos de ordem funcionam no menu mobile', (tester) async {
    final store = _MemoryModuleOrderStore();
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester
        .pumpWidget(MaterialApp(home: ShellScreen(moduleOrderStore: store)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await _openEditor(tester);
    await tester.tap(find.byTooltip('Descer Dashboard'));
    await tester.tap(find.text('Guardar ordem'));
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((destination) => destination.label)
        .toList();
    expect(labels, ['Atividade', 'Dashboard', 'Membros', 'Tesouraria', 'Mais']);
    expect(store.saved, hasLength(17));
  });

  testWidgets('a personalização é acessível no NavigationRail de tablet',
      (tester) async {
    final store = _MemoryModuleOrderStore();
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    await tester
        .pumpWidget(MaterialApp(home: ShellScreen(moduleOrderStore: store)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.byTooltip('Personalizar menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Descer Dashboard'));
    await tester.tap(find.text('Guardar ordem'));
    await tester.pumpAndSettle();

    final railLabels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byType(Text),
          ),
        )
        .map((label) => label.data)
        .whereType<String>()
        .toList();
    expect(railLabels.take(2), ['Atividade', 'Dashboard']);
    expect(store.saved, hasLength(17));
  });

  testWidgets('arrastar um módulo altera a ordem de rascunho', (tester) async {
    final store = _MemoryModuleOrderStore();
    await _pumpDesktop(tester, store);
    await _openEditor(tester);

    final dragHandle = find.byIcon(Icons.drag_handle).first;
    final firstItem = tester.getCenter(dragHandle);
    final secondItem = tester.getCenter(find.byKey(const ValueKey('activity')));
    await tester.timedDragFrom(
      firstItem,
      Offset(0, secondItem.dy - firstItem.dy + 8),
      const Duration(milliseconds: 700),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar ordem'));
    await tester.pumpAndSettle();

    expect(store.saved, isNotNull);
    expect(store.saved!.take(2), ['activity', 'dashboard']);
  });
}

Future<void> _pumpDesktop(
  WidgetTester tester,
  ModuleOrderStore store,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1;
  await tester
      .pumpWidget(MaterialApp(home: ShellScreen(moduleOrderStore: store)));
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester) async {
  final drawer = find.byType(NavigationDrawer);
  final scrollable =
      find.descendant(of: drawer, matching: find.byType(Scrollable)).first;
  final action = find.text('Personalizar menu');
  await tester.scrollUntilVisible(action, 120, scrollable: scrollable);
  await tester.ensureVisible(action);
  await tester.pumpAndSettle();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _expectDrawerModule(WidgetTester tester, String title) async {
  final drawer = find.byType(NavigationDrawer);
  final scrollable =
      find.descendant(of: drawer, matching: find.byType(Scrollable)).first;
  final destination = find.descendant(of: drawer, matching: find.text(title));
  await tester.scrollUntilVisible(destination, 100, scrollable: scrollable);
  expect(destination, findsOneWidget);
}

String _labelText(Widget widget) {
  if (widget is Text) return widget.data ?? '';
  if (widget is Tooltip) return _labelText(widget.child!);
  if (widget is SizedBox && widget.child != null) {
    return _labelText(widget.child!);
  }
  if (widget is Padding) {
    return _labelText(widget.child!);
  }
  return '';
}

class _MemoryModuleOrderStore implements ModuleOrderStore {
  List<String>? saved;
  bool deleted = false;

  @override
  Future<List<String>?> load() async => saved;

  @override
  Future<void> reset() async {
    saved = null;
    deleted = true;
  }

  @override
  Future<void> save(List<String> order) async {
    saved = List<String>.of(order);
    deleted = false;
  }
}
