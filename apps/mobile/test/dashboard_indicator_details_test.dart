import 'dart:async';

import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/models/dashboard_indicator_detail.dart';
import 'package:bob_manager_mobile/repositories/dashboard_repository.dart';
import 'package:bob_manager_mobile/screens/dashboard_screen.dart';
import 'package:bob_manager_mobile/screens/member_detail_screen.dart';
import 'package:bob_manager_mobile/widgets/dashboard_indicator_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository extends DashboardRepository {
  final calls = <(DashboardIndicator, Map<String, dynamic>?)>[];
  int summaryCalls = 0;
  int total = 0;
  bool authorized = true;
  bool fail = false;
  Completer<DashboardIndicatorDetail>? pending;
  Map<String, dynamic>? row;
  Map<String, dynamic>? cursor;
  int pageTotal = 1;

  @override
  Future<Map<String, dynamic>> summary() async {
    summaryCalls++;
    return {
      'can_view_financial': true,
      for (final indicator in DashboardIndicator.values) indicator.key: total,
      'monthly_income': 0,
      'monthly_expense': 0,
      'overdue_fees': 0,
    };
  }

  @override
  Future<DashboardIndicatorDetail> indicatorDetails(
    DashboardIndicator indicator, {
    int limit = 50,
    Map<String, dynamic>? cursor,
  }) async {
    calls.add((indicator, cursor));
    if (fail) throw StateError('test');
    if (pending != null) return pending!.future;
    return DashboardIndicatorDetail(
      indicator: indicator,
      authorized: authorized,
      complete: authorized,
      totalRows: authorized ? (row == null ? 0 : pageTotal) : null,
      monetaryTotal: authorized && indicator.monetary ? total : null,
      rows: authorized && row != null ? [row!] : [],
      nextCursor: authorized ? this.cursor : null,
    );
  }
}

Map<String, dynamic> _eventCursor(String id) => {
      'v': 1,
      'club_id': AppSession.instance.clubId,
      'indicator': 'open_events',
      'number': null,
      'date': null,
      'time': '2026-10-10T10:00:00Z',
      'text': 'Primeiro',
      'id': id,
    };

Future<void> _dashboard(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(1100, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: DashboardScreen(repository: repository)),
  ));
  await tester.pumpAndSettle();
}

Finder _card(DashboardIndicator indicator) =>
    find.byKey(ValueKey('dashboard-card-${indicator.key}'));

void main() {
  setUp(() => AppSession.instance.clear());
  tearDown(() => AppSession.instance.clear());

  for (final indicator in DashboardIndicator.values) {
    testWidgets('${indicator.key}: só carrega após clique e zero abre vazio',
        (tester) async {
      final repository = _Repository();
      await _dashboard(tester, repository);
      expect(repository.calls, isEmpty);
      await tester.ensureVisible(_card(indicator));
      await tester.pumpAndSettle();
      await tester.tap(_card(indicator));
      await tester.pumpAndSettle();
      expect(repository.calls, [(indicator, null)]);
      expect(find.text('Não existem registos para este indicador.'),
          findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sem autorização mostra mensagem e não mostra lista',
      (tester) async {
    final repository = _Repository()..authorized = false;
    await _dashboard(tester, repository);
    await tester.tap(_card(DashboardIndicator.lowStock));
    await tester.pumpAndSettle();
    expect(
        find.text(
          'Não tem permissão para consultar o detalhe completo deste indicador.',
        ),
        findsOneWidget);
    expect(
        find.text('Não existem registos para este indicador.'), findsNothing);
    expect(find.textContaining('Total:'), findsNothing);
  });

  testWidgets('carregamento e erro permitem repetir', (tester) async {
    final repository = _Repository()
      ..pending = Completer<DashboardIndicatorDetail>();
    await _dashboard(tester, repository);
    await tester.tap(_card(DashboardIndicator.members));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending!.completeError(StateError('test'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar o detalhe.'), findsOneWidget);
    repository.pending = null;
    await tester.tap(find.text('Repetir'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, 2);
    expect(
        find.text('Não existem registos para este indicador.'), findsOneWidget);
  });

  testWidgets('carregar mais passa cursor, não repete linhas, refresh reinicia',
      (tester) async {
    final repository = _Repository()
      ..row = {'id': 'e1', 'name': 'Primeiro', 'status': 'planning'}
      ..cursor = _eventCursor('e1')
      ..pageTotal = 2;
    await _dashboard(tester, repository);
    await tester.tap(_card(DashboardIndicator.openEvents));
    await tester.pumpAndSettle();
    expect(find.text('Primeiro'), findsOneWidget);
    final firstCursor = repository.cursor;
    repository
      ..row = {'id': 'e2', 'name': 'Segundo', 'status': 'planning'}
      ..cursor = null;
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.$2, _eventCursor('e1'));
    expect(repository.calls.last.$2, same(firstCursor));
    expect(find.text('Primeiro'), findsOneWidget);
    expect(find.text('Segundo'), findsOneWidget);
    expect(find.text('Carregar mais'), findsNothing);
    repository
      ..row = {'id': 'e3', 'name': 'Atualizado', 'status': 'planning'}
      ..pageTotal = 1;
    await tester.tap(find.byTooltip('Atualizar detalhe'));
    await tester.pumpAndSettle();
    expect(repository.calls.last.$2, isNull);
    expect(find.text('Primeiro'), findsNothing);
    expect(find.text('Segundo'), findsNothing);
    expect(find.text('Atualizado'), findsOneWidget);
  });

  testWidgets('mudança de agregado durante paginação reinicia a lista',
      (tester) async {
    final repository = _Repository()
      ..row = {'id': 'e1', 'name': 'Antigo', 'status': 'planning'}
      ..cursor = _eventCursor('e1')
      ..pageTotal = 2;
    await _dashboard(tester, repository);
    await tester.tap(_card(DashboardIndicator.openEvents));
    await tester.pumpAndSettle();
    repository
      ..row = {'id': 'e2', 'name': 'Novo', 'status': 'planning'}
      ..cursor = null
      ..pageTotal = 1;
    await tester.tap(find.text('Carregar mais'));
    await tester.pumpAndSettle();
    expect(repository.calls.map((call) => call.$2),
        [null, _eventCursor('e1'), null]);
    expect(find.text('Antigo'), findsNothing);
    expect(find.text('Novo'), findsOneWidget);
  });

  testWidgets('fechar o detalhe recarrega o resumo atualizado', (tester) async {
    final repository = _Repository();
    await _dashboard(tester, repository);
    expect(repository.summaryCalls, 1);
    await tester.tap(_card(DashboardIndicator.members));
    await tester.pumpAndSettle();
    repository.total = 7;
    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(repository.summaryCalls, 2);
    expect(
        find.descendant(
            of: _card(DashboardIndicator.members), matching: find.text('7')),
        findsOneWidget);
  });

  testWidgets('abrir membro mantém MemberDetailScreen acessível',
      (tester) async {
    final repository = _Repository()
      ..row = {
        'id': 'm1',
        'full_name': 'Ana',
        'member_number': 1,
        'nickname': 'A'
      };
    String? opened;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardIndicatorDetailDialog(
          indicator: DashboardIndicator.members,
          repository: repository,
          onOpenMember: (id) async {
            opened = id;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir membro'));
    await tester.pumpAndSettle();
    expect(opened, 'm1');

    // Exercise the real default navigation with an existing demo member.
    final realRepository = DashboardRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: DashboardIndicatorDetailDialog(
        key: const ValueKey('real-member'),
        indicator: DashboardIndicator.members,
        repository: realRepository,
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Abrir membro').first);
    await tester.pumpAndSettle();
    expect(find.byType(MemberDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('troca de sessão descarta resposta em curso', (tester) async {
    final repository = _Repository()
      ..pending = Completer<DashboardIndicatorDetail>();
    await _dashboard(tester, repository);
    await tester.tap(_card(DashboardIndicator.members));
    await tester.pump();
    AppSession.instance.clubId = 'different';
    repository.pending!.complete(const DashboardIndicatorDetail(
      indicator: DashboardIndicator.members,
      authorized: true,
      complete: true,
      rows: [
        {'id': 'secret', 'full_name': 'Secret'}
      ],
      totalRows: 1,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Secret'), findsNothing);
    expect(
        find.text(
          'Não tem permissão para consultar o detalhe completo deste indicador.',
        ),
        findsOneWidget);
  });

  for (final requester in [
    (name: 'Gestor', missing: false, expected: 'Gestor'),
    (name: null, missing: true, expected: 'Nome não disponível'),
    (name: null, missing: false, expected: 'Nome não disponível'),
    (name: '   ', missing: false, expected: 'Nome não disponível'),
    (name: 'Ocultado', missing: true, expected: 'Nome não disponível'),
  ]) {
    testWidgets('requerente ${requester.name}/${requester.missing} sem UUID',
        (tester) async {
      const requesterId = '11111111-2222-3333-4444-555555555555';
      final repository = _Repository()
        ..row = {
          'id': 'r1',
          'description': 'Pedido',
          'status': 'pending_review',
          'requested_by': requesterId,
          'requester_name': requester.name,
          'requester_name_missing': requester.missing,
        };
      await _dashboard(tester, repository);
      await tester.tap(_card(DashboardIndicator.pendingApprovals));
      await tester.pumpAndSettle();
      expect(find.textContaining('Requerente: ${requester.expected}'),
          findsOneWidget);
      expect(find.textContaining(requesterId), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    testWidgets('painel responsivo $size sem overflow com conteúdo longo',
        (tester) async {
      final repository = _Repository()
        ..row = {
          'id': 'r1',
          'description': 'Descrição extensa ' * 12,
          'request_type': 'reimbursement',
          'status': 'pending_review',
          'amount': 20,
          'requester_name': 'Nome extenso ' * 8,
        };
      await _dashboard(tester, repository, size: size);
      await tester.ensureVisible(_card(DashboardIndicator.pendingApprovals));
      await tester.pumpAndSettle();
      await tester.tap(_card(DashboardIndicator.pendingApprovals));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardIndicatorDetailDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width < 700) {
        expect(find.byType(BottomSheet), findsOneWidget);
      } else {
        expect(find.byType(Dialog), findsOneWidget);
      }
    });
  }
}
