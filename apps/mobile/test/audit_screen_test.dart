import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/repositories/admin_repository.dart';
import 'package:bob_manager_mobile/screens/audit_screen.dart';
import 'package:bob_manager_mobile/widgets/audit_detail_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppSession.instance.clear());

  group('mapeamento de módulos da Auditoria', () {
    test('mapeia entidades conhecidas e usa Outros como fallback', () {
      expect(auditModuleForEntityType('members'), 'Membros');
      expect(auditModuleForEntityType('financial_transactions'), 'Tesouraria');
      expect(
        auditModuleForEntityType('financial_requests'),
        'Pedidos & Pagamentos',
      );
      expect(auditModuleForEntityType('bar_sales'), 'BAR');
      expect(auditModuleForEntityType('agenda_item'), 'Agenda');
      expect(auditModuleForEntityType('entity_added_later'), 'Outros');
    });

    test('todos os tipos de produção pertencem ao módulo correto', () {
      const productionTypesByModule = <String, List<String>>{
        'Membros': ['members'],
        'Motas e manutenção': ['member_motorcycles'],
        'Tesouraria': [
          'treasury_transactions',
          'treasury_accounts',
          'transaction',
          'financial_transaction_documents',
          'financial_ocr_jobs',
        ],
        'Quotas': [
          'fee_obligations',
          'fee_payments',
          'fee_payment_allocations',
          'fee_plans',
          'reported_payments',
        ],
        'Euromilhões': [
          'euromillions',
          'euromillions_draw_charges',
          'euromillions_draw_charge',
          'euromillions_fines',
          'euromillions_fine_payment',
          'euromillions_results',
          'euromillions_players',
          'euromillions_prizes',
          'euromillions_prize',
        ],
        'Eventos': [
          'events',
          'event_route_stops',
          'event_program',
          'event_volunteers',
          'event_incidents',
          'event_shifts',
          'event_shift_members',
          'event_tasks',
          'event_task_assignees',
          'event_routes',
        ],
        'BAR': [
          'bar_operations',
          'bar_sales',
          'bar_sale_items',
          'bar_sale_attachments',
          'bar_product_sale_options',
        ],
        'Inventário': [
          'inventory',
          'inventory_locations',
          'inventory_prices',
          'inventory_visibility',
          'inventory_count_sessions',
          'products',
          'product',
          'stock_movements',
          'stock_reservations',
          'stock_breakages',
          'stock_lots',
        ],
        'Documentos': ['documents', 'document_versions'],
        'Comunicação': [
          'announcements',
          'announcement',
          'announcement_acknowledgements',
        ],
        'Administração': [
          'club_settings',
          'club_role_permissions',
          'club_memberships',
          'user_access',
        ],
      };

      for (final module in productionTypesByModule.entries) {
        for (final entityType in module.value) {
          expect(
            auditModuleForEntityType(entityType),
            module.key,
            reason: entityType,
          );
          expect(
            auditEntityTypesForModule(module.key),
            contains(entityType),
            reason: entityType,
          );
          expect(auditEntityTypesForModule('Outros'), contains(entityType));
        }
      }
    });

    test('Outros exclui os tipos atualmente mapeados', () {
      expect(
        auditEntityTypesForModule('Outros'),
        containsAll({'members', 'documents', 'club_settings'}),
      );
      expect(auditEntityTypesForModule('Membros'), contains('members'));
    });
  });

  test('filtros geram parâmetros server-side limpos e limitados', () {
    final cursor = AuditLogCursor(
      createdAt: DateTime.utc(2026, 10, 1, 9),
      id: 42,
    );
    final filters = AuditLogFilters(
      dateFrom: DateTime(2026, 10, 1),
      dateTo: DateTime(2026, 10, 4),
      entityTypes: const [' members ', ''],
      action: ' updated ',
      actorQuery: ' Ana Silva ',
      search: ' documento ',
      entityId: ' 123-abc ',
    );

    final params = filters.toRpcParams(cursor: cursor, limit: 500);

    expect(params['p_created_from'], isNotNull);
    expect(params['p_created_before'], isNotNull);
    expect(params['p_entity_types'], ['members']);
    expect(params['p_action'], 'updated');
    expect(params['p_actor_query'], 'Ana Silva');
    expect(params['p_search'], 'documento');
    expect(params['p_entity_id'], '123-abc');
    expect(params['p_cursor_created_at'], '2026-10-01T09:00:00.000Z');
    expect(params['p_cursor_id'], 42);
    expect(params['p_limit'], 50);
    expect(params.keys, isNot(contains('before_data')));
    expect(params.keys, isNot(contains('after_data')));
  });

  test('página usa created_at e id para expor o próximo cursor', () {
    final page = AuditLogPage.fromRows(
      [
        {'id': 11, 'created_at': '2026-10-10T10:00:00Z'},
        {'id': 10, 'created_at': '2026-10-10T10:00:00Z'},
        {'id': 9, 'created_at': '2026-10-10T09:00:00Z'},
      ],
      limit: 2,
    );

    expect(page.rows, hasLength(2));
    expect(page.hasMore, isTrue);
    expect(page.nextCursor?.createdAt, DateTime.utc(2026, 10, 10, 10));
    expect(page.nextCursor?.id, 10);
  });

  testWidgets('detalhe preserva topo e esconde campos técnicos aninhados',
      (tester) async {
    final row = <String, dynamic>{
      'entity_type': 'members',
      'entity_id': 'member-17',
      'actor': {'full_name': 'Ana Silva', 'email': 'ana@example.test'},
      'created_at': '2026-10-10T10:00:00Z',
      'before_data': {
        'full_name': 'Ana',
        'club_id': 'hidden-club',
        'metadata': {
          'status': 'active',
          'updated_by': 'hidden-user',
        },
      },
      'after_data': {
        'full_name': 'Ana Silva',
        'created_by': 'hidden-user',
      },
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AuditDetailContent(row: row)),
        ),
      ),
    );

    expect(find.text('Utilizador'), findsOneWidget);
    expect(find.text('Data e hora'), findsOneWidget);
    expect(find.text('ID do registo'), findsOneWidget);
    expect(find.text('member-17'), findsOneWidget);
    expect(find.text('Antes'), findsOneWidget);
    expect(find.text('Depois'), findsOneWidget);
    expect(find.text('Full name: Ana'), findsOneWidget);
    expect(find.text('Metadata: Status: active'), findsOneWidget);
    expect(find.text('Full name: Ana Silva'), findsOneWidget);
    expect(find.textContaining('hidden'), findsNothing);
    expect(find.textContaining('club id'), findsNothing);
    expect(find.textContaining('created by'), findsNothing);
    expect(find.textContaining('updated by'), findsNothing);
  });

  test('club_settings mostra somente Chave e Valor', () {
    final fields = auditFieldsFor(
      {
        'key': 'club_name',
        'value': 'Clube exemplo',
        'id': 'hidden-id',
        'club_id': 'hidden-club',
        'description': 'hidden-description',
      },
      clubSettings: true,
    );

    expect(fields.map((field) => field.key), ['Chave', 'Valor']);
    expect(fields.map((field) => field.value), ['club_name', 'Clube exemplo']);
  });

  test('a paginação continua protegida por manageSettings', () async {
    AppSession.instance.role = 'Membro';

    await expectLater(
      AdminRepository().listAuditLogPage(),
      throwsA(isA<StateError>()),
    );
  });
}