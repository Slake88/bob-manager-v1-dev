import 'permissions.dart';

enum GlobalSearchType {
  member,
  motorcycle,
  document,
  product,
  event,
}

extension GlobalSearchTypeMeta on GlobalSearchType {
  String get key => name;

  String get label => switch (this) {
        GlobalSearchType.member => 'Membros',
        GlobalSearchType.motorcycle => 'Motas',
        GlobalSearchType.document => 'Documentos',
        GlobalSearchType.product => 'Produtos',
        GlobalSearchType.event => 'Eventos',
      };
}

class GlobalSearchResult {
  const GlobalSearchResult({
    required this.type,
    required this.entityId,
    required this.title,
    required this.subtitle,
    required this.moduleCode,
    required this.score,
    this.parentId,
    this.detail,
  });

  factory GlobalSearchResult.fromMap(Map<String, dynamic> row) {
    final rawType = row['result_type']?.toString() ?? '';
    final type = GlobalSearchType.values.firstWhere(
      (item) => item.key == rawType,
      orElse: () => throw FormatException('Tipo de pesquisa inválido: $rawType'),
    );
    return GlobalSearchResult(
      type: type,
      entityId: row['entity_id']?.toString() ?? '',
      parentId: _optionalString(row['parent_id']),
      title: row['title']?.toString() ?? '',
      subtitle: row['subtitle']?.toString() ?? '',
      detail: _optionalString(row['detail']),
      moduleCode: row['module_code']?.toString() ?? '',
      score: int.tryParse(row['score']?.toString() ?? '') ?? 0,
    );
  }

  final GlobalSearchType type;
  final String entityId;
  final String? parentId;
  final String title;
  final String subtitle;
  final String? detail;
  final String moduleCode;
  final int score;
}

class GlobalSearchPolicy {
  const GlobalSearchPolicy._();

  static List<GlobalSearchType> visibleTypes(
    bool Function(AppPermission permission) allows,
  ) {
    return [
      if (allows(AppPermission.viewMembers)) ...[
        GlobalSearchType.member,
        GlobalSearchType.motorcycle,
      ],
      if (allows(AppPermission.viewDocuments)) GlobalSearchType.document,
      if (allows(AppPermission.viewInventory)) GlobalSearchType.product,
      if (allows(AppPermission.viewEvents)) GlobalSearchType.event,
    ];
  }
}

String normalizeGlobalSearchToken(String value) {
  var text = value.trim().toLowerCase();
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  return text.replaceAll(RegExp('[^a-z0-9]+'), '');
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
