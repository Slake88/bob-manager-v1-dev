import 'app_role.dart';
import 'app_session.dart';
import 'permissions.dart';

enum ImportTarget {
  members,
  inventoryProducts,
  events,
  feePlans,
}

enum ImportFieldType {
  text,
  integer,
  decimal,
  date,
  dateTime,
  boolean,
  choice,
}

class ImportField {
  const ImportField({
    required this.key,
    required this.label,
    this.type = ImportFieldType.text,
    this.required = false,
    this.aliases = const [],
    this.choices = const {},
    this.hint,
  });

  final String key;
  final String label;
  final ImportFieldType type;
  final bool required;
  final List<String> aliases;
  final Map<String, String> choices;
  final String? hint;
}

class ImportDefinition {
  const ImportDefinition({
    required this.target,
    required this.key,
    required this.title,
    required this.description,
    required this.permission,
    required this.fields,
  });

  final ImportTarget target;
  final String key;
  final String title;
  final String description;
  final AppPermission permission;
  final List<ImportField> fields;

  Map<String, String?> autoMapping(List<String> headers) {
    final normalizedHeaders = <String, String>{};
    for (final header in headers) {
      normalizedHeaders.putIfAbsent(normalizeImportToken(header), () => header);
    }

    return {
      for (final field in fields)
        field.key: _findHeader(field, normalizedHeaders),
    };
  }

  String? _findHeader(
    ImportField field,
    Map<String, String> normalizedHeaders,
  ) {
    final candidates = <String>{
      field.key,
      field.label,
      ...field.aliases,
    }.map(normalizeImportToken);
    for (final candidate in candidates) {
      final header = normalizedHeaders[candidate];
      if (header != null) return header;
    }
    return null;
  }

  Map<String, dynamic> mapSourceRow(
    Map<String, String> source,
    Map<String, String?> mapping,
  ) {
    final mapped = <String, dynamic>{};
    for (final field in fields) {
      final header = mapping[field.key];
      final raw = header == null ? '' : (source[header] ?? '');
      mapped[field.key] = normalizeValue(field, raw);
    }
    return mapped;
  }

  String normalizeValue(ImportField field, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    if (field.type == ImportFieldType.choice) {
      final token = normalizeImportToken(value);
      for (final entry in field.choices.entries) {
        if (normalizeImportToken(entry.key) == token ||
            normalizeImportToken(entry.value) == token) {
          return entry.key;
        }
      }
    }

    if (field.type == ImportFieldType.boolean) {
      final token = normalizeImportToken(value);
      if ({'1', 'true', 'sim', 'yes', 'y', 's'}.contains(token)) {
        return 'true';
      }
      if ({'0', 'false', 'nao', 'no', 'n'}.contains(token)) {
        return 'false';
      }
    }

    return value;
  }

  bool hasRequiredMapping(Map<String, String?> mapping) {
    return fields
        .where((field) => field.required)
        .every((field) => mapping[field.key] != null);
  }
}

class ParsedImportFile {
  const ParsedImportFile({
    required this.filename,
    required this.format,
    required this.headers,
    required this.rows,
    this.sheetName,
  });

  final String filename;
  final String format;
  final List<String> headers;
  final List<Map<String, String>> rows;
  final String? sheetName;
}

class ImportRowPreview {
  const ImportRowPreview({
    required this.id,
    required this.rowNumber,
    required this.mappedData,
    required this.errors,
  });

  final String id;
  final int rowNumber;
  final Map<String, dynamic> mappedData;
  final List<String> errors;

  bool get valid => errors.isEmpty;

  factory ImportRowPreview.fromMap(Map<String, dynamic> row) {
    return ImportRowPreview(
      id: row['id'].toString(),
      rowNumber: int.tryParse(row['row_number']?.toString() ?? '') ?? 0,
      mappedData: Map<String, dynamic>.from(
        row['mapped_data'] as Map? ?? const <String, dynamic>{},
      ),
      errors: List<String>.from(row['validation_errors'] as List? ?? const []),
    );
  }
}

class ImportHistoryEntry {
  const ImportHistoryEntry({
    required this.id,
    required this.target,
    required this.filename,
    required this.status,
    required this.totalRows,
    required this.validRows,
    required this.invalidRows,
    required this.appliedRows,
    required this.createdAt,
  });

  final String id;
  final String target;
  final String filename;
  final String status;
  final int totalRows;
  final int validRows;
  final int invalidRows;
  final int appliedRows;
  final DateTime? createdAt;

  factory ImportHistoryEntry.fromMap(Map<String, dynamic> row) {
    int number(String key) => int.tryParse(row[key]?.toString() ?? '') ?? 0;
    return ImportHistoryEntry(
      id: row['id'].toString(),
      target: row['target']?.toString() ?? '',
      filename: row['source_filename']?.toString() ?? '',
      status: row['status']?.toString() ?? 'draft',
      totalRows: number('total_rows'),
      validRows: number('valid_rows'),
      invalidRows: number('invalid_rows'),
      appliedRows: number('applied_rows'),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    );
  }
}

class ImportCatalog {
  const ImportCatalog._();

  static const definitions = <ImportDefinition>[
    ImportDefinition(
      target: ImportTarget.members,
      key: 'members',
      title: 'Membros',
      description: 'Ficha base do membro, sem dados médicos ou documentos.',
      permission: AppPermission.manageMembers,
      fields: [
        ImportField(
          key: 'member_number',
          label: 'N.º membro',
          type: ImportFieldType.integer,
          aliases: ['numero', 'número', 'numero membro', 'socio', 'sócio'],
        ),
        ImportField(
          key: 'full_name',
          label: 'Nome completo',
          required: true,
          aliases: ['nome', 'membro', 'name'],
        ),
        ImportField(key: 'nickname', label: 'Alcunha', aliases: ['nickname']),
        ImportField(key: 'email', label: 'Email', aliases: ['e-mail']),
        ImportField(key: 'phone', label: 'Telefone', aliases: ['telemovel', 'telemóvel']),
        ImportField(
          key: 'birth_date',
          label: 'Data nascimento',
          type: ImportFieldType.date,
          aliases: ['nascimento', 'data de nascimento'],
          hint: 'AAAA-MM-DD ou DD/MM/AAAA',
        ),
        ImportField(
          key: 'joined_at',
          label: 'Entrada no clube',
          type: ImportFieldType.date,
          aliases: ['entrada', 'data entrada'],
        ),
        ImportField(
          key: 'status',
          label: 'Estado',
          type: ImportFieldType.choice,
          aliases: ['status'],
          choices: {
            'active': 'Ativo',
            'prospect': 'Prospect',
            'full_color': 'Full Color',
            'suspended': 'Suspenso',
            'honorary': 'Honorário',
            'former': 'Ex-membro',
            'deceased': 'Falecido',
          },
        ),
        ImportField(
          key: 'prospect_joined_at',
          label: 'Data Prospect',
          type: ImportFieldType.date,
          aliases: ['prospect desde', 'entrada prospect'],
        ),
        ImportField(
          key: 'full_colors_at',
          label: 'Data Full Colors',
          type: ImportFieldType.date,
          aliases: ['full colors', 'data full colors'],
        ),
      ],
    ),
    ImportDefinition(
      target: ImportTarget.inventoryProducts,
      key: 'inventory_products',
      title: 'Produtos de Inventário',
      description: 'Catálogo de Loja/Bar; o stock é gerido pelo módulo de inventário.',
      permission: AppPermission.manageInventory,
      fields: [
        ImportField(key: 'name', label: 'Produto', required: true, aliases: ['nome']),
        ImportField(key: 'sku', label: 'SKU', aliases: ['referencia', 'referência']),
        ImportField(key: 'category', label: 'Categoria'),
        ImportField(key: 'unit', label: 'Unidade', aliases: ['unidade consumo']),
        ImportField(key: 'cost', label: 'Custo', type: ImportFieldType.decimal),
        ImportField(
          key: 'sale_price',
          label: 'Preço venda',
          type: ImportFieldType.decimal,
          aliases: ['preco', 'preço'],
        ),
        ImportField(
          key: 'minimum_stock',
          label: 'Stock mínimo',
          type: ImportFieldType.decimal,
          aliases: ['stock minimo'],
        ),
        ImportField(
          key: 'active',
          label: 'Ativo',
          type: ImportFieldType.boolean,
          aliases: ['activo'],
        ),
        ImportField(
          key: 'inventory_area',
          label: 'Área',
          type: ImportFieldType.choice,
          aliases: ['area', 'tipo'],
          choices: {'shop': 'Loja', 'bar': 'Bar'},
        ),
        ImportField(key: 'description', label: 'Descrição'),
        ImportField(key: 'supplier', label: 'Fornecedor'),
        ImportField(
          key: 'institutional_delivery',
          label: 'Entrega institucional',
          type: ImportFieldType.boolean,
          aliases: ['institucional'],
        ),
        ImportField(key: 'purchase_unit', label: 'Unidade de compra'),
        ImportField(key: 'consumption_unit', label: 'Unidade de consumo'),
        ImportField(
          key: 'units_per_purchase',
          label: 'Unidades por compra',
          type: ImportFieldType.decimal,
        ),
        ImportField(
          key: 'purchase_cost',
          label: 'Custo de compra',
          type: ImportFieldType.decimal,
        ),
      ],
    ),
    ImportDefinition(
      target: ImportTarget.events,
      key: 'events',
      title: 'Eventos',
      description: 'Eventos base; participantes e operações continuam nos módulos próprios.',
      permission: AppPermission.manageEvents,
      fields: [
        ImportField(key: 'name', label: 'Evento', required: true, aliases: ['nome']),
        ImportField(key: 'description', label: 'Descrição'),
        ImportField(key: 'location', label: 'Local', aliases: ['localizacao', 'localização']),
        ImportField(
          key: 'starts_at',
          label: 'Início',
          type: ImportFieldType.dateTime,
          aliases: ['inicio', 'data inicio'],
        ),
        ImportField(
          key: 'ends_at',
          label: 'Fim',
          type: ImportFieldType.dateTime,
          aliases: ['data fim'],
        ),
        ImportField(
          key: 'status',
          label: 'Estado',
          type: ImportFieldType.choice,
          choices: {
            'draft': 'Rascunho',
            'published': 'Publicado',
            'active': 'Ativo',
            'completed': 'Concluído',
            'cancelled': 'Cancelado',
          },
        ),
        ImportField(key: 'capacity', label: 'Capacidade', type: ImportFieldType.integer),
        ImportField(key: 'budget', label: 'Orçamento', type: ImportFieldType.decimal),
      ],
    ),
    ImportDefinition(
      target: ImportTarget.feePlans,
      key: 'fee_plans',
      title: 'Planos de Quotas',
      description: 'Planos de cobrança; não gera obrigações durante a importação.',
      permission: AppPermission.manageFees,
      fields: [
        ImportField(key: 'name', label: 'Plano', required: true, aliases: ['nome']),
        ImportField(key: 'amount', label: 'Valor', required: true, type: ImportFieldType.decimal),
        ImportField(
          key: 'frequency',
          label: 'Frequência',
          type: ImportFieldType.choice,
          aliases: ['periodicidade'],
          choices: {
            'monthly': 'Mensal',
            'quarterly': 'Trimestral',
            'annual': 'Anual',
            'custom': 'Personalizado',
          },
        ),
        ImportField(
          key: 'due_day',
          label: 'Dia vencimento',
          type: ImportFieldType.integer,
          aliases: ['dia'],
        ),
        ImportField(key: 'active', label: 'Ativo', type: ImportFieldType.boolean),
      ],
    ),
  ];

  static ImportDefinition byKey(String key) =>
      definitions.firstWhere((definition) => definition.key == key);

  static List<ImportDefinition> visible(AppSession session) {
    if (isDirection(session)) return definitions;
    if (!session.can(AppPermission.manageImports)) return const [];
    return definitions
        .where((definition) => session.can(definition.permission))
        .toList();
  }

  static bool canOpen(AppSession session) => visible(session).isNotEmpty;

  static bool isDirection(AppSession session) {
    return session.superAdmin ||
        session.currentRole == AppRole.president ||
        session.currentRole == AppRole.vicePresident ||
        session.currentRole == AppRole.administrator;
  }
}

String normalizeImportToken(String input) {
  return input
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
