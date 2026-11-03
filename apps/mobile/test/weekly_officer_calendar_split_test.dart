import 'package:bob_manager_mobile/repositories/weekly_officer_repository.dart';
import 'package:bob_manager_mobile/screens/weekly_officer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class CalendarRepo extends WeeklyOfficerRepository {
  bool allowed = false;
  bool rebuildSupported = true;
  @override
  bool get supportsRebuild => rebuildSupported;
  int ensures = 0;
  int rebuilds = 0;
  final years = <int>[];
  @override
  Future<bool> canManageSchedule() async => allowed;
  @override
  Future<void> ensureYear(int year) async {
    ensures++;
    years.add(year);
  }

  @override
  Future<Map<String, dynamic>> rebuildYear(int year) async {
    rebuilds++;
    return {'eligible': 52, 'assigned': 52};
  }

  @override
  Future<List<Map<String, dynamic>>> members() async => [];
  @override
  Future<List<Map<String, dynamic>>> listRotation() async => [];
  @override
  Future<List<Map<String, dynamic>>> listDinners(int year) async => [];
  @override
  Future<List<Map<String, dynamic>>> listAbsences(int year) async => [];
  @override
  Future<List<Map<String, dynamic>>> listSwaps() async => [];
  @override
  Future<String?> currentMemberId() async => null;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));
  Future<void> mount(WidgetTester tester, CalendarRepo repo) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WeeklyOfficerScreen(repository: repo))));
    await tester.pumpAndSettle();
  }

  testWidgets('member load, refresh and year change only ensure calendar',
      (tester) async {
    final repo = CalendarRepo();
    await mount(tester, repo);
    expect(repo.ensures, 1);
    expect(find.byTooltip('Recalcular atribuições automáticas'), findsNothing);
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ano seguinte'));
    await tester.pumpAndSettle();
    expect(repo.ensures, 3);
    expect(repo.years.last, DateTime.now().year + 1);
    expect(repo.rebuilds, 0);
  });

  testWidgets('unavailable rebuild is hidden even for a manager',
      (tester) async {
    final repo = CalendarRepo()
      ..allowed = true
      ..rebuildSupported = false;
    await mount(tester, repo);
    expect(find.byTooltip('Recalcular atribuições automáticas'), findsNothing);
    expect(repo.rebuilds, 0);
  });

  testWidgets('manager rebuild requires explicit confirmation; refresh is safe',
      (tester) async {
    final repo = CalendarRepo()..allowed = true;
    await mount(tester, repo);
    expect(repo.rebuilds, 0);
    await tester.tap(find.byTooltip('Recalcular atribuições automáticas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Atribuições manuais'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.rebuilds, 0);
    await tester.tap(find.byTooltip('Recalcular atribuições automáticas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recalcular'));
    await tester.pumpAndSettle();
    expect(repo.rebuilds, 1);
    await tester.tap(find.byTooltip('Atualizar'));
    await tester.pumpAndSettle();
    expect(repo.rebuilds, 1);
    await tester.tap(find.byTooltip('Ano anterior'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Recalcular atribuições automáticas'), findsNothing);
  });
}
