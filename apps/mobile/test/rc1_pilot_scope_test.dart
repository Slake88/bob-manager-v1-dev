import 'dart:convert';

import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/club_export.dart';
import 'package:bob_manager_mobile/repositories/club_export_repository.dart';
import 'package:bob_manager_mobile/repositories/assets_operations_repository.dart';
import 'package:bob_manager_mobile/screens/club_export_screen.dart';
import 'package:bob_manager_mobile/screens/assets_phase2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late List<String> requestedRpcs;
  late List<String> requestedPaths;

  setUp(() {
    AppSession.instance.clear();
    AppSession.instance.role = 'Presidente';
    requestedRpcs = [];
    requestedPaths = [];
    client = SupabaseClient(
      'http://127.0.0.1:54321',
      'synthetic-local-test-key',
      httpClient: MockClient((request) async {
        if (request.url.pathSegments.contains('rpc')) {
          requestedRpcs.add(request.url.pathSegments.last);
        } else {
          requestedPaths.add(request.url.path);
        }
        return http.Response(
          request.url.pathSegments.contains('rpc')
              ? 'null'
              : jsonEncode(<Object>[]),
          200,
          request: request,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDown(() async {
    await client.dispose();
    AppSession.instance.clear();
  });

  test('pilot allowlist is exactly the 14 R13-tested datasets', () {
    expect(pilotClubExportDatasetPaths, hasLength(14));
    expect(pilotClubExportSections, {
      ClubExportSection.financial,
      ClubExportSection.fees,
      ClubExportSection.lottery,
    });
    expect(
      pilotClubExportDatasetPaths,
      containsAll([
        'financeiro/pedidos.csv',
        'financeiro/pedidos_anexos.csv',
        'financeiro/documentos_movimentos.csv',
        'quotas/planos.csv',
        'quotas/obrigacoes.csv',
        'quotas/pagamentos.csv',
        'euromilhoes/participantes.csv',
        'euromilhoes/sorteios.csv',
        'euromilhoes/chaves.csv',
        'euromilhoes/participacoes.csv',
        'euromilhoes/resultados.csv',
        'euromilhoes/cobrancas.csv',
        'euromilhoes/multas.csv',
        'euromilhoes/premios.csv',
      ]),
    );
  });

  test('unsupported section is rejected before any export RPC', () async {
    final repository = ClubExportRepository(client: client);
    await expectLater(
      repository.begin(
        sections: {ClubExportSection.members},
        includeSensitive: false,
        includeFiles: false,
      ),
      throwsA(
        isA<ClubExportFailure>().having(
          (failure) => failure.code,
          'code',
          'pilot_scope_disabled',
        ),
      ),
    );
    expect(requestedRpcs, isEmpty);
  });

  test(
    'sensitive and file export flags are rejected before the API call',
    () async {
      final repository = ClubExportRepository(client: client);
      for (final flags in [
        (sensitive: true, files: false),
        (sensitive: false, files: true),
      ]) {
        await expectLater(
          repository.begin(
            sections: {ClubExportSection.financial},
            includeSensitive: flags.sensitive,
            includeFiles: flags.files,
          ),
          throwsA(isA<ClubExportFailure>()),
        );
      }
      expect(requestedRpcs, isEmpty);
    },
  );

  testWidgets('export UI shows only the three pilot sections', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ClubExportScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Pedidos & Pagamentos'), findsOneWidget);
    expect(find.text('Quotas'), findsOneWidget);
    expect(find.text('Euromilhões'), findsOneWidget);
    for (final disabledTitle in [
      'Membros',
      'Tesouraria',
      'Eventos',
      'Inventário',
      'Documentos',
      'Comunicação',
      'Agenda',
      'Oficial da Semana',
      'Configuração',
      'Auditoria',
    ]) {
      expect(find.text(disabledTitle), findsNothing);
    }
    expect(find.text('Incluir dados altamente sensíveis'), findsNothing);
    expect(find.text('Incluir ficheiros armazenados'), findsNothing);
    final pilotNotice = find.text('Escopo limitado do piloto');
    await tester.scrollUntilVisible(
      pilotNotice,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(pilotNotice, findsOneWidget);
  });

  testWidgets('asset maintenance and inspection forms are absent in UI', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AssetsPhase2Screen(
          repository: AssetsOperationsRepository(client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manutenção'));
    await tester.pumpAndSettle();
    expect(find.text('Registo de intervenções desativado no piloto.'), findsOneWidget);
    expect(find.text('Registar intervenção'), findsNothing);
    expect(find.text('Registar manutenção'), findsNothing);

    await tester.tap(find.text('Inspeções'));
    await tester.pumpAndSettle();
    expect(find.text('Registo de inspeções desativado no piloto.'), findsOneWidget);
    expect(find.text('Registar inspeção'), findsNothing);
  });

  test('asset maintenance repository entry point is disabled without RPC',
      () async {
    final repository = AssetsOperationsRepository();
    await expectLater(
      repository.maintenance(
        assetId: 'synthetic-asset',
        type: 'maintenance',
        date: DateTime.utc(2026, 10, 24),
        description: 'synthetic test only',
        cost: 1,
        supplier: 'synthetic',
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('asset read, loan and return endpoints remain wired', () async {
    final repository = AssetsOperationsRepository(client: client);
    await repository.assets();
    await repository.maintenanceHistory();
    await repository.kits();

    expect(requestedPaths, contains('/rest/v1/inventory_assets'));
    expect(requestedPaths, contains('/rest/v1/asset_maintenance'));
    expect(requestedPaths, contains('/rest/v1/asset_kits'));

    AppSession.instance.role = 'Responsável de Inventário';
    await repository.loan(
      assetId: 'synthetic-asset',
      borrowerType: 'external',
      externalName: 'Synthetic recipient',
    );
    await repository.returnLoan(
      loanId: 'synthetic-loan',
      condition: 'good',
    );
    expect(requestedRpcs, containsAll(['asset_loan_v1', 'asset_return_v1']));
    expect(requestedRpcs, isNot(contains('asset_maintenance_v1')));
  });
}
