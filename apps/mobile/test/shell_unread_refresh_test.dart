import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/screens/shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.authenticate(
      newProfileId: 'synthetic-profile',
      newClubId: 'synthetic-club',
      newFullName: 'Synthetic Member',
      newRole: 'member',
    );
  });

  tearDown(AppSession.instance.clear);

  testWidgets('refresh unread count uses a synchronous setState callback',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ShellScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The shell refreshes its unread badge every 30 seconds.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Notificações'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
