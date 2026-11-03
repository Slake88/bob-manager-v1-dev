import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const _technicalAuditFields = {
  'id',
  'club_id',
  'created_at',
  'updated_at',
  'created_by',
  'updated_by',
};

String auditActorLabel(Map<String, dynamic> row) {
  final actor = row['actor'];
  if (actor is Map) {
    final name = (row['actor_name'] ?? actor['full_name'])?.toString().trim() ?? '';
    final email = (row['actor_email'] ?? actor['email'])?.toString().trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return '$name · $email';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
  }
  final actorId = row['actor_id']?.toString().trim() ?? '';
  if (actorId.isEmpty) return 'Sistema / automatismo';
  return 'Utilizador $actorId';
}

String auditMomentLabel(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return value?.toString() ?? 'Data desconhecida';
  return DateFormat('dd/MM/yyyy HH:mm:ss').format(parsed);
}

String auditActionLabel(Object? value) {
  return switch (value?.toString()) {
    'created' => 'Criado',
    'updated' => 'Alterado',
    'deleted' => 'Eliminado',
    'insert' => 'Criado',
    'update' => 'Alterado',
    'upsert' => 'Criado/alterado',
    final String text when text.isNotEmpty => text,
    _ => 'Alteração',
  };
}

String auditEntityLabel(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return 'Registo';
  final normalized = text.replaceAll('_', ' ');
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

List<MapEntry<String, String>> auditFieldsFor(
  Object? value, {
  required bool clubSettings,
}) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! Map) return const [];

  final fields = <MapEntry<String, String>>[];
  for (final entry in decoded.entries) {
    final key = entry.key.toString();
    if (_isTechnicalAuditField(key)) continue;
    if (clubSettings && key != 'key' && key != 'value') continue;
    final label = clubSettings
        ? (key == 'key' ? 'Chave' : 'Valor')
        : _auditFieldLabel(key);
    fields.add(MapEntry(label, _auditValue(entry.value)));
  }
  return fields;
}

bool _isTechnicalAuditField(String key) =>
    _technicalAuditFields.contains(key.toLowerCase());

String _auditFieldLabel(String value) {
  final label = value.replaceAll('_', ' ');
  if (label.isEmpty) return label;
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

String _auditValue(Object? value) {
  if (value == null) return '—';
  if (value is Map) {
    final fields = value.entries
        .where((entry) => !_isTechnicalAuditField(entry.key.toString()))
        .map(
          (entry) =>
              '${_auditFieldLabel(entry.key.toString())}: ${_auditValue(entry.value)}',
        )
        .toList();
    return fields.isEmpty ? '—' : fields.join(', ');
  }
  if (value is Iterable) {
    final items = value.map(_auditValue).where((item) => item != '—').toList();
    return items.isEmpty ? '—' : items.join(', ');
  }
  if (value is bool) return value ? 'Sim' : 'Não';
  return value.toString();
}

class AuditDetailContent extends StatelessWidget {
  const AuditDetailContent({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final entityId = row['entity_id']?.toString();
    final clubSettings = row['entity_type']?.toString() == 'club_settings';
    final beforeData = row['before_data'];
    final afterData = row['after_data'];
    final before = auditFieldsFor(beforeData, clubSettings: clubSettings);
    final after = auditFieldsFor(afterData, clubSettings: clubSettings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('Utilizador'),
          subtitle: Text(auditActorLabel(row)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Data e hora'),
          subtitle: Text(auditMomentLabel(row['created_at'])),
        ),
        if (entityId != null && entityId.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.tag_outlined),
            title: const Text('ID do registo'),
            subtitle: SelectableText(entityId),
          ),
        if (beforeData != null) ...[
          const SizedBox(height: 8),
          Text('Antes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ..._fieldWidgets(before),
        ],
        if (afterData != null) ...[
          const SizedBox(height: 16),
          Text('Depois', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          ..._fieldWidgets(after),
        ],
      ],
    );
  }

  List<Widget> _fieldWidgets(List<MapEntry<String, String>> fields) {
    if (fields.isEmpty) return const [Text('Sem campos funcionais.')];
    return fields
        .map(
          (field) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SelectableText('${field.key}: ${field.value}'),
          ),
        )
        .toList();
  }
}