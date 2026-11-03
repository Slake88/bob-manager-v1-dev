import 'dart:convert';

import 'app_role.dart';
import 'app_session.dart';
import 'permissions.dart';

enum ClubExportSection {
  members('members', 'Membros', 'Ficha, percurso, motas, manutenção, patches e timeline'),
  treasury('treasury', 'Tesouraria', 'Contas, categorias, centros de custo e movimentos'),
  financial('financial', 'Pedidos & Pagamentos', 'Pedidos financeiros e metadata dos comprovativos'),
  fees('fees', 'Quotas', 'Planos, obrigações e pagamentos'),
  lottery('lottery', 'Euromilhões', 'Participantes, chaves, sorteios, resultados e prémios'),
  events('events', 'Eventos', 'Eventos, inscrições, voluntários e parceiros'),
  inventory('inventory', 'Inventário', 'Produtos, stock, loja, património, contagens e Bar'),
  documents('documents', 'Documentos', 'Metadata do arquivo e, opcionalmente, ficheiros'),
  communication('communication', 'Comunicação', 'Comunicados e confirmações de leitura'),
  agenda('agenda', 'Agenda', 'Itens manuais da agenda'),
  weeklyOfficer('weekly_officer', 'Oficial da Semana', 'Escala, jantares, ausências e trocas'),
  configuration('configuration', 'Configuração', 'Clube, cargos, permissões e memberships'),
  audit('audit', 'Auditoria', 'Metadata de auditoria e atividade, sem payloads históricos');

  const ClubExportSection(this.key, this.title, this.description);
  final String key;
  final String title;
  final String description;
}

class ClubExportPolicy {
  const ClubExportPolicy._();

  static bool canExportRole(AppRole role, {required bool superAdmin}) {
    return superAdmin ||
        role == AppRole.president ||
        role == AppRole.vicePresident ||
        role == AppRole.administrator;
  }

  static bool canExport(AppSession session) =>
      canExportRole(session.currentRole, superAdmin: session.superAdmin);

  static bool canIncludeSensitive(AppSession session) {
    return canExport(session) &&
        session.can(AppPermission.viewEmergencyData) &&
        session.can(AppPermission.viewSensitiveDocuments);
  }
}

class ClubExportDataset {
  const ClubExportDataset({
    required this.path,
    required this.columns,
    required this.rows,
    this.sensitive = false,
  });

  final String path;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final bool sensitive;

  int get rowCount => rows.length;
}

class ClubExportFileRef {
  const ClubExportFileRef({
    required this.bucket,
    required this.storagePath,
    required this.archivePath,
    this.knownSize,
  });

  final String bucket;
  final String storagePath;
  final String archivePath;
  final int? knownSize;
}

class ClubExportBundle {
  const ClubExportBundle({
    required this.club,
    required this.datasets,
    required this.files,
  });

  final Map<String, dynamic> club;
  final List<ClubExportDataset> datasets;
  final List<ClubExportFileRef> files;

  int get rowCount =>
      datasets.fold<int>(0, (total, dataset) => total + dataset.rowCount);
}

class ClubExportPackage {
  const ClubExportPackage({
    required this.bytes,
    required this.filename,
    required this.exportId,
    required this.datasetCount,
    required this.rowCount,
    required this.fileCount,
  });

  final List<int> bytes;
  final String filename;
  final String exportId;
  final int datasetCount;
  final int rowCount;
  final int fileCount;
}

class ClubExportFailure implements Exception {
  const ClubExportFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

String safeArchiveName(String value) {
  final parts = value
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty && part != '.' && part != '..')
      .map(
        (part) => part
            .replaceAll(RegExp(r'[^A-Za-z0-9À-ÿ._ -]+'), '_')
            .replaceAll(RegExp(r'\s+'), '_'),
      )
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? 'ficheiro' : parts.join('/');
}

String csvCell(Object? value) {
  if (value == null) return '""';
  final String text;
  if (value is Map || value is List) {
    text = jsonEncode(value);
  } else if (value is bool) {
    text = value ? 'true' : 'false';
  } else {
    text = value.toString();
  }
  return '"${text.replaceAll('"', '""')}"';
}

List<int> datasetCsvBytes(ClubExportDataset dataset) {
  final rows = <String>[
    dataset.columns.map(csvCell).join(';'),
    ...dataset.rows.map(
      (row) => dataset.columns.map((column) => csvCell(row[column])).join(';'),
    ),
  ];
  return utf8.encode('\ufeff${rows.join('\r\n')}');
}

const Set<String> normalMemberExportColumns = {
  'id',
  'member_number',
  'full_name',
  'nickname',
  'email',
  'phone',
  'birth_date',
  'joined_at',
  'status',
  'prospect_joined_at',
  'full_colors_at',
  'primary_role',
  'additional_roles',
};

const Set<String> sensitiveMemberExportColumns = {
  'id',
  'member_number',
  'full_name',
  'tax_number',
  'address',
  'postal_code',
  'locality',
  'emergency_contact',
  'notes',
};
