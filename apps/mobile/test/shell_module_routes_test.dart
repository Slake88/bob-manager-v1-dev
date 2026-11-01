import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/screens/activity_screen.dart';
import 'package:bob_manager_mobile/screens/agenda_screen.dart';
import 'package:bob_manager_mobile/screens/bar_screen_v4.dart';
import 'package:bob_manager_mobile/screens/communication_module_screen.dart';
import 'package:bob_manager_mobile/screens/dashboard_screen.dart';
import 'package:bob_manager_mobile/screens/documents_module_screen.dart';
import 'package:bob_manager_mobile/screens/emergency_screen.dart';
import 'package:bob_manager_mobile/screens/events_module_v2_screen.dart';
import 'package:bob_manager_mobile/screens/fees_screen.dart';
import 'package:bob_manager_mobile/screens/financial_requests_screen.dart';
import 'package:bob_manager_mobile/screens/inventory_module_screen.dart';
import 'package:bob_manager_mobile/screens/lottery_screen.dart';
import 'package:bob_manager_mobile/screens/members_screen.dart';
import 'package:bob_manager_mobile/screens/reports_hub_screen.dart';
import 'package:bob_manager_mobile/screens/settings_screen.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:bob_manager_mobile/screens/treasury_module_screen.dart';
import 'package:bob_manager_mobile/screens/weekly_officer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _routeTypes = <String, Type>{
  'dashboard': DashboardScreen,
  'activity': ActivityScreen,
  'members': MembersScreen,
  'treasury': TreasuryModuleScreen,
  'financial': FinancialRequestsScreen,
  'fees': FeesScreen,
  'lottery': LotteryScreen,
  'events': EventsModuleV2Screen,
  'weekly_officer': WeeklyOfficerScreen,
  'agenda': AgendaScreen,
  'bar': BarScreenV4,
  'inventory': InventoryModuleScreen,
  'documents': DocumentsModuleScreen,
  'communication': CommunicationModuleScreen,
  'reports': ReportsHubScreen,
  'settings': SettingsScreen,
  'emergency': EmergencyScreen,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('pt_PT'));

  tearDown(() => AppSession.instance.clear());

  testWidgets('todos os 17 módulos abrem a rota esperada em desktop e mobile',
      (tester) async {
    _authenticateWithAllPermissions();

    await _pumpAt(tester, const Size(1600, 1000));
    for (final module in appModules) {
      await _openModule(tester, module, compact: false);
      expect(find.byType(_routeTypes[module.code]!), findsOneWidget,
          reason: 'desktop route for ${module.code}');
      expect(tester.takeException(), isNull,
          reason: 'desktop build for ${module.code}');
    }

    await _pumpAt(tester, const Size(390, 844));
    for (final module in appModules) {
      await _openModule(tester, module, compact: true);
      expect(find.byType(_routeTypes[module.code]!), findsOneWidget,
          reason: 'mobile route for ${module.code}');
      expect(tester.takeException(), isNull,
          reason: 'mobile build for ${module.code}');
    }
  });
}

void _authenticateWithAllPermissions() {
  final session = AppSession.instance;
  session.clear();
  session.authenticate(
    newProfileId: 'synthetic-full-navigation-profile',
    newClubId: 'synthetic-full-navigation-club',
    newFullName: 'Direção sintética',
    newRole: 'president',
  );
  session.applyPermissions(
      AppPermission.values.map((permission) => permission.key));
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openModule(
  WidgetTester tester,
  ModuleDefinition module, {
  required bool compact,
}) async {
  if (!compact) {
    final destination = find.descendant(
      of: find.byType(NavigationDrawer),
      matching: find.text(module.title),
    );
    final scrollable = find
        .descendant(
          of: find.byType(NavigationDrawer),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(destination, 120, scrollable: scrollable);
    await tester.tap(destination);
    await tester.pump(const Duration(milliseconds: 450));
    return;
  }

  var destination = _bottomDestination(module.title);
  if (destination.evaluate().isEmpty) {
    await tester.tap(_bottomDestination('Mais'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    final grid = find.byType(GridView).first;
    final scrollable =
        find.descendant(of: grid, matching: find.byType(Scrollable)).first;
    final inGrid = find.descendant(of: grid, matching: find.text(module.title));
    await tester.scrollUntilVisible(inGrid, 240, scrollable: scrollable);
    await tester.ensureVisible(inGrid);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(inGrid);
    await tester.pump(const Duration(milliseconds: 450));
    return;
  }
  await tester.tap(destination);
  await tester.pump(const Duration(milliseconds: 450));
}

Finder _bottomDestination(String label) => find.byWidgetPredicate(
      (widget) => widget is NavigationDestination && widget.label == label,
    );
