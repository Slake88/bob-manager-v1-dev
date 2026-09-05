import 'dart:convert';

import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/core/reporting.dart';
import 'package:bob_manager_mobile/services/report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('centro de relatórios abre com qualquer permissão exportável', () {
    bool membersOnly(AppPermission permission) =>
        permission == AppPermission.viewMembers;

    expect(ReportCatalog.canOpenCenter(membersOnly), isTrue);
    final visible = ReportCatalog.visible(membersOnly);
    expect(visible.map((item) => item.kind), [ReportKind.members]);
  });

  test('sem permissões de leitura não existe centro de relatórios', () {
    expect(ReportCatalog.canOpenCenter((_) => false), isFalse);
    expect(ReportCatalog.visible((_) => false), isEmpty);
  });

  test('tesouraria continua protegida por viewFinancialReports', () {
    final visible = ReportCatalog.visible(
      (permission) => permission == AppPermission.viewFinancialReports,
    );
    expect(visible, hasLength(1));
    expect(visible.single.kind, ReportKind.treasury);
  });

  test('CSV usa BOM UTF-8, separador ponto e vírgula e escaping', () {
    final definition = ReportCatalog.definitions.first;
    final data = ReportData(
      definition: definition,
      columns: const [
        ReportColumn('name', 'Nome'),
        ReportColumn('amount', 'Valor', type: ReportValueType.currency),
      ],
      rows: const [
        {'name': 'João "Blue"', 'amount': 12.5},
      ],
      metrics: const {},
      filtersDescription: 'Sem filtros adicionais',
    );

    final bytes = ReportExportService.csvBytes(data);
    expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
    final text = utf8.decode(bytes);
    expect(text, contains('"Nome";"Valor"'));
    expect(text, contains('"João ""Blue""";"12,50 €"'));
  });

  test('formatação não expande booleanos ou datas em valores técnicos', () {
    expect(
      ReportExportService.formatValue(true, ReportValueType.boolean),
      'Sim',
    );
    expect(
      ReportExportService.formatValue(false, ReportValueType.boolean),
      'Não',
    );
    expect(
      ReportExportService.formatValue('2026-08-12', ReportValueType.date),
      '12/08/2026',
    );
  });
}
