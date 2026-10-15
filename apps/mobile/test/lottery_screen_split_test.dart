import 'package:bob_manager_mobile/core/app_config.dart';
import 'package:bob_manager_mobile/repositories/lottery_repository.dart';
import 'package:bob_manager_mobile/screens/lottery_screen_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ReadOnlyLotteryRepo extends LotteryRepository {
  bool manage = true;
  int loads = 0;
  int prepares = 0;
  @override
  bool get canManage => manage;
  @override
  bool get canOperateMoney => false;
  @override
  Future<Map<String,dynamic>> loadMonth(int year,int month) async {
    loads++;
    return {'players': <Map<String,dynamic>>[], 'charges': <Map<String,dynamic>>[],
      'results': <Map<String,dynamic>>[], 'fines': <Map<String,dynamic>>[],
      'prizes': <Map<String,dynamic>>[], 'draw_amount':2.2,'fine_per_miss':0.1};
  }
  @override
  Future<void> prepareMonth(int year,int month) async { prepares++; }
}
void main() {
  Future<void> mount(WidgetTester tester,ReadOnlyLotteryRepo repo) async {
    await tester.binding.setSurfaceSize(const Size(1100,1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:LotteryScreen(repository:repo)));
    await tester.pumpAndSettle();
  }
  testWidgets('load, refresh and navigation never prepare', (tester) async {
    final repo=ReadOnlyLotteryRepo();
    await mount(tester,repo);
    final refresh=find.byType(RefreshIndicator);
    tester.state<RefreshIndicatorState>(refresh).show();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(repo.loads,3);
    expect(repo.prepares,0);
    expect(find.text('Preparar mês'),findsNothing);
    expect(find.text('Custo atual / jogador'),findsNothing);
  });
  testWidgets('preparation requires an explicit confirmed action', (tester) async {
    final repo=ReadOnlyLotteryRepo();
    await mount(tester,repo);
    expect(repo.prepares,0);
    await tester.tap(find.text('Preparar mês'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.prepares,0);
    await tester.tap(find.text('Preparar mês'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preparar'));
    await tester.pumpAndSettle();
    expect(repo.prepares,1);
  },skip:AppConfig.demoMode);
  testWidgets('management actions are hidden from viewers', (tester) async {
    final repo=ReadOnlyLotteryRepo()..manage=false;
    await mount(tester,repo);
    expect(find.text('Preparar mês'),findsNothing);
    expect(find.text('Atualizar oficial'),findsNothing);
  });
}
