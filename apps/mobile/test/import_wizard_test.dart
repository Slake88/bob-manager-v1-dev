import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:flutter_test/flutter_test.dart';

import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/importing.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/services/import_file_parser.dart';

void main() {
  tearDown(PermissionPolicy.reset);

  test('manageImports mantém Direção e permite autorização explícita', () {
    PermissionPolicy.reset();
    expect(
      PermissionPolicy.allows(AppRole.president, AppPermission.manageImports),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.secretary, AppPermission.manageImports),
      isFalse,
    );

    PermissionPolicy.configure(
      permissionKeys: ['manageImports', 'manageMembers'],
      superAdmin: false,
    );
    expect(
      PermissionPolicy.allows(AppRole.secretary, AppPermission.manageImports),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.secretary, AppPermission.manageMembers),
      isTrue,
    );
  });

  test('mapeamento automático reconhece cabeçalhos portugueses', () {
    final definition = ImportCatalog.byKey('members');
    final mapping = definition.autoMapping([
      'N.º Membro',
      'Nome',
      'Telemóvel',
      'Estado',
    ]);

    expect(mapping['member_number'], 'N.º Membro');
    expect(mapping['full_name'], 'Nome');
    expect(mapping['phone'], 'Telemóvel');
    expect(mapping['status'], 'Estado');
    expect(definition.hasRequiredMapping(mapping), isTrue);
  });

  test('normalização converte escolhas e booleanos', () {
    final member = ImportCatalog.byKey('members');
    final status = member.fields.firstWhere((field) => field.key == 'status');
    expect(member.normalizeValue(status, 'Ativo'), 'active');
    expect(member.normalizeValue(status, 'Full Color'), 'full_color');

    final product = ImportCatalog.byKey('inventory_products');
    final active = product.fields.firstWhere((field) => field.key == 'active');
    expect(product.normalizeValue(active, 'Sim'), 'true');
    expect(product.normalizeValue(active, 'não'), 'false');
  });

  test('CSV suporta BOM, ponto e vírgula, aspas e quebras de linha', () {
    const text = '\ufeff"Nome";"Nota"\r\n'
        '"João";"Texto; com ""aspas"""\r\n'
        '"Maria";"linha 1\nlinha 2"\r\n';

    final parsed = const ImportFileParser().parseCsv(
      'membros.csv',
      Uint8List.fromList(utf8.encode(text)),
    );

    expect(parsed.headers, ['Nome', 'Nota']);
    expect(parsed.rows, hasLength(2));
    expect(parsed.rows.first['Nome'], 'João');
    expect(parsed.rows.first['Nota'], 'Texto; com "aspas"');
    expect(parsed.rows.last['Nota'], 'linha 1\nlinha 2');
  });

  test('XLSX lê a primeira folha com dados', () {
    final workbook = ex.Excel.createExcel();
    final sheet = workbook['Membros'];
    sheet.appendRow([
      ex.TextCellValue('Nome'),
      ex.TextCellValue('Estado'),
    ]);
    sheet.appendRow([
      ex.TextCellValue('Teste'),
      ex.TextCellValue('Ativo'),
    ]);
    final bytes = workbook.save();
    expect(bytes, isNotNull);

    final parsed = const ImportFileParser().parseXlsx(
      'membros.xlsx',
      Uint8List.fromList(bytes!),
    );

    expect(parsed.sheetName, 'Membros');
    expect(parsed.headers, ['Nome', 'Estado']);
    expect(parsed.rows.single['Nome'], 'Teste');
  });

  test('normalização de cabeçalhos remove acentos e pontuação', () {
    expect(normalizeImportToken('N.º Sócio / Membro'), 'nsociomembro');
    expect(normalizeImportToken('Preço Venda (€)'), 'precovenda');
  });
}
