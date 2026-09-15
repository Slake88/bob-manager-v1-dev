import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/document_repository.dart';
import 'package:bob_manager_mobile/repositories/documents_advanced_repository.dart';
import 'package:bob_manager_mobile/screens/document_library_advanced_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('documento expirado é identificado', () {
    expect(
      DocumentRepository.isExpired(
        {'expires_at': '2026-01-01'},
        now: DateTime(2026, 8, 6),
      ),
      isTrue,
    );
  });

  test('documento a expirar nos próximos 30 dias é identificado', () {
    expect(
      DocumentRepository.expiresSoon(
        {'expires_at': '2026-08-20'},
        now: DateTime(2026, 8, 6),
      ),
      isTrue,
    );
  });

  test('secretário gere documentos e comunicação', () {
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageDocuments,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageCommunication,
      ),
      isTrue,
    );
  });

  test('membro consulta documentos públicos e confirma leituras', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewDocuments),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.viewSensitiveDocuments,
      ),
      isFalse,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.acknowledgeCommunication,
      ),
      isTrue,
    );
  });

  testWidgets('gestão da biblioteca tem navegação de regresso própria', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentLibraryAdvancedScreen(
            repository: DocumentsAdvancedRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gestão da biblioteca'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('Gestão da biblioteca'), findsWidgets);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('Arquivo documental'), findsOneWidget);
  });
}
