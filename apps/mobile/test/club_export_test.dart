import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/club_export.dart';
import 'package:bob_manager_mobile/services/club_export_service.dart';

void main() {
  test('exportação integral fica limitada à Direção fixa', () {
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.president,
        superAdmin: false,
      ),
      isTrue,
    );
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.vicePresident,
        superAdmin: false,
      ),
      isTrue,
    );
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.administrator,
        superAdmin: false,
      ),
      isTrue,
    );
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.treasurer,
        superAdmin: false,
      ),
      isFalse,
    );
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.secretary,
        superAdmin: false,
      ),
      isFalse,
    );
    expect(
      ClubExportPolicy.canExportRole(
        AppRole.unknown,
        superAdmin: true,
      ),
      isTrue,
    );
  });

  test('exportação normal de membros exclui campos altamente sensíveis', () {
    expect(normalMemberExportColumns, isNot(contains('tax_number')));
    expect(normalMemberExportColumns, isNot(contains('address')));
    expect(normalMemberExportColumns, isNot(contains('emergency_contact')));
    expect(normalMemberExportColumns, isNot(contains('notes')));
    expect(sensitiveMemberExportColumns, contains('tax_number'));
    expect(sensitiveMemberExportColumns, contains('emergency_contact'));
  });

  test('safeArchiveName elimina traversal e separadores perigosos', () {
    expect(
      safeArchiveName('../../segredo/../foto final.jpg'),
      'segredo/foto_final.jpg',
    );
    expect(safeArchiveName(r'..\\..\\teste?.pdf'), 'teste_.pdf');
  });

  test('CSV usa BOM UTF-8, ponto e vírgula e escaping', () {
    const dataset = ClubExportDataset(
      path: 'teste.csv',
      columns: ['nome', 'nota'],
      rows: [
        {'nome': 'João', 'nota': 'texto; "citado"'},
      ],
    );
    final bytes = datasetCsvBytes(dataset);
    expect(bytes.take(3), orderedEquals([0xEF, 0xBB, 0xBF]));
    final text = utf8.decode(bytes.sublist(3));
    expect(text, contains(r'"nome";"nota"'));
    expect(text, contains(r'"João";"texto; ""citado"""'));
  });

  test('pacote ZIP inclui manifest e datasets sem ficheiros externos', () async {
    const bundle = ClubExportBundle(
      club: {'id': 'club-1', 'name': 'BLUE ON BLACK'},
      datasets: [
        ClubExportDataset(
          path: 'membros/membros.csv',
          columns: ['id', 'full_name'],
          rows: [
            {'id': 'm-1', 'full_name': 'Teste'},
          ],
        ),
      ],
      files: [],
    );
    final package = await ClubExportService().buildPackage(
      exportId: 'export-1',
      bundle: bundle,
      sections: {ClubExportSection.members},
      includeSensitive: false,
      includeFiles: false,
    );

    expect(package.datasetCount, 1);
    expect(package.rowCount, 1);
    expect(package.fileCount, 0);
    expect(package.bytes.length, greaterThan(4));

    final archive = ZipDecoder().decodeBytes(
      Uint8List.fromList(package.bytes),
    );
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, contains('manifest.json'));
    expect(names, contains('membros/membros.csv'));
  });
}
