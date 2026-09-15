import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/importing.dart';
import '../repositories/import_repository.dart';
import '../services/import_file_parser.dart';

class ImportWizardScreen extends StatefulWidget {
  const ImportWizardScreen({super.key});

  @override
  State<ImportWizardScreen> createState() => _ImportWizardScreenState();
}

class _ImportWizardScreenState extends State<ImportWizardScreen> {
  final ImportRepository _repository = ImportRepository();
  final ImportFileParser _parser = const ImportFileParser();

  late final List<ImportDefinition> _definitions;
  ImportDefinition? _definition;
  ParsedImportFile? _file;
  Map<String, String?> _mapping = {};
  String? _importId;
  List<ImportRowPreview> _preview = const [];
  Map<String, dynamic> _stats = const {};
  bool _busy = false;
  String _progress = '';
  late Future<List<ImportHistoryEntry>> _history;

  @override
  void initState() {
    super.initState();
    _definitions = ImportCatalog.visible(AppSession.instance);
    _definition = _definitions.isEmpty ? null : _definitions.first;
    _history = _definitions.isEmpty
        ? Future<List<ImportHistoryEntry>>.value(const [])
        : _repository.history();
  }

  Future<void> _pickFile() async {
    if (_busy) return;
    try {
      final parsed = await _parser.pickAndParse();
      if (parsed == null || !mounted) return;
      final definition = _definition;
      setState(() {
        _file = parsed;
        _mapping =
            definition == null ? <String, String?>{} : definition.autoMapping(parsed.headers);
        _importId = null;
        _preview = const [];
        _stats = const {};
      });
    } on ImportParseException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('Não foi possível ler o ficheiro selecionado.');
    }
  }

  void _changeTarget(ImportDefinition? definition) {
    if (definition == null || _busy) return;
    setState(() {
      _definition = definition;
      _file = null;
      _mapping = {};
      _importId = null;
      _preview = const [];
      _stats = const {};
    });
  }

  Future<void> _validateAndPreview() async {
    final definition = _definition;
    final file = _file;
    if (definition == null || file == null) {
      _message('Seleciona o destino e um ficheiro.');
      return;
    }
    if (!definition.hasRequiredMapping(_mapping)) {
      _message('Mapeia todos os campos obrigatórios antes de validar.');
      return;
    }

    setState(() {
      _busy = true;
      _progress = 'A enviar e validar as linhas...';
    });

    try {
      final importId = await _repository.begin(
        definition: definition,
        file: file,
        mapping: _mapping,
      );
      final stats = await _repository.stage(
        importId: importId,
        definition: definition,
        file: file,
        mapping: _mapping,
      );
      final preview = await _repository.rows(importId);
      if (!mounted) return;
      setState(() {
        _importId = importId;
        _stats = stats;
        _preview = preview;
        _history = _repository.history();
      });
      _message(
        '${stats['valid_rows'] ?? 0} linhas válidas; '
        '${stats['invalid_rows'] ?? 0} com correções.',
      );
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _editRow(ImportRowPreview row) async {
    final definition = _definition;
    final importId = _importId;
    if (definition == null || importId == null || _busy) return;

    final controllers = {
      for (final field in definition.fields)
        field.key: TextEditingController(
          text: row.mappedData[field.key]?.toString() ?? '',
        ),
    };

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Corrigir linha ${row.rowNumber}'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final field in definition.fields) ...[
                TextField(
                  controller: controllers[field.key],
                  decoration: InputDecoration(
                    labelText: field.required ? '${field.label} *' : field.label,
                    helperText: _fieldHelp(field),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Validar alteração'),
          ),
        ],
      ),
    );

    if (save != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }

    final mapped = <String, dynamic>{
      for (final field in definition.fields)
        field.key: definition.normalizeValue(
          field,
          controllers[field.key]!.text,
        ),
    };
    for (final controller in controllers.values) {
      controller.dispose();
    }

    setState(() {
      _busy = true;
      _progress = 'A revalidar a linha...';
    });
    try {
      final stats = await _repository.updateRow(
        importId: importId,
        rowId: row.id,
        mappedData: mapped,
      );
      final preview = await _repository.rows(importId);
      if (!mounted) return;
      setState(() {
        _stats = {..._stats, ...stats};
        _preview = preview;
      });
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _apply() async {
    final importId = _importId;
    if (importId == null || _busy) return;
    final invalid = int.tryParse(_stats['invalid_rows']?.toString() ?? '') ?? 0;
    if (invalid > 0) {
      _message('Corrige todas as linhas antes de aplicar a importação.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aplicar importação?'),
        content: const Text(
          'Os registos serão criados numa única operação transacional. '
          'A reversão só será permitida enquanto os registos importados '
          'não tiverem sido alterados nem usados por outros módulos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _progress = 'A aplicar a importação...';
    });
    try {
      final result = await _repository.apply(importId);
      if (result['success'] != true) {
        _message('A importação foi anulada; nenhum registo parcial ficou aplicado.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _history = _repository.history();
        _preview = const [];
        _stats = const {};
        _file = null;
        _mapping = {};
        _importId = null;
      });
      _message('${result['applied_rows'] ?? 0} registos importados com sucesso.');
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  Future<void> _rollback(ImportHistoryEntry entry) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reverter importação?'),
        content: Text(
          'Será tentada a remoção dos ${entry.appliedRows} registos criados por '
          '${entry.filename}. A operação é bloqueada se algum deles tiver sido '
          'alterado ou já tiver dados dependentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _progress = 'A verificar e reverter a importação...';
    });
    try {
      final result = await _repository.rollback(entry.id);
      if (result['success'] == true) {
        _message('${result['reverted_rows'] ?? 0} registos revertidos.');
      } else {
        _message(
          'A reversão foi bloqueada para proteger dados já alterados ou relacionados.',
        );
      }
      if (!mounted) return;
      setState(() => _history = _repository.history());
    } catch (error) {
      _message(_friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  String? _fieldHelp(ImportField field) {
    if (field.choices.isNotEmpty) {
      return field.choices.values.join(' / ');
    }
    return field.hint;
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('Sem permissão')) {
      return 'Sem permissão para esta operação.';
    }
    if (text.contains('1000 linhas')) {
      return 'O máximo por importação é 1000 linhas.';
    }
    return 'Não foi possível concluir a operação de importação.';
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (_definitions.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Sem permissão para importar dados.')),
      );
    }

    final definition = _definition!;
    final file = _file;
    final mappingLocked = _importId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Assistente de Importação')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Destino',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ImportDefinition>(
                    initialValue: definition,
                    items: _definitions
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.title),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : _changeTarget,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Importar para',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(definition.description),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(file?.filename ?? '2. Selecionar CSV ou Excel'),
              subtitle: Text(
                file == null
                    ? 'Máximo 2 MB e 1000 linhas.'
                    : '${file.rows.length} linhas • ${file.headers.length} colunas'
                        '${file.sheetName == null ? '' : ' • ${file.sheetName}'}',
              ),
              trailing: FilledButton.tonal(
                onPressed: _busy || mappingLocked ? null : _pickFile,
                child: Text(file == null ? 'Escolher' : 'Trocar'),
              ),
            ),
          ),
          if (file != null) ...[
            const SizedBox(height: 8),
            Text(
              '3. Mapear colunas',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            ...definition.fields.map(
              (field) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String?>(
                    initialValue: _mapping[field.key],
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Ignorar / sem coluna'),
                      ),
                      ...file.headers.map(
                        (header) => DropdownMenuItem<String?>(
                          value: header,
                          child: Text(header),
                        ),
                      ),
                    ],
                    onChanged: _busy || mappingLocked
                        ? null
                        : (value) {
                            setState(() => _mapping[field.key] = value);
                          },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: field.required ? '${field.label} *' : field.label,
                      helperText: _fieldHelp(field),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_importId == null)
              FilledButton.icon(
                onPressed: _busy ? null : _validateAndPreview,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Validar e pré-visualizar'),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _importId = null;
                          _preview = const [];
                          _stats = const {};
                        }),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Alterar mapeamento e validar de novo'),
              ),
          ],
          if (_busy) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const CircularProgressIndicator(),
                title: const Text('A processar...'),
                subtitle: Text(_progress),
              ),
            ),
          ],
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              '4. Pré-visualização e correção',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${_stats['valid_rows'] ?? 0} válidas')),
                Chip(label: Text('${_stats['invalid_rows'] ?? 0} com erros')),
                Chip(label: Text('${_preview.length} linhas')),
              ],
            ),
            const SizedBox(height: 6),
            ..._preview.map((row) => _previewCard(definition, row)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _apply,
              icon: const Icon(Icons.playlist_add_check_circle_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Aplicar importação'),
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'Histórico de importações',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<ImportHistoryEntry>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: ListTile(
                    title: Text('Não foi possível carregar o histórico.'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data!;
              if (entries.isEmpty) {
                return const Card(
                  child: ListTile(title: Text('Ainda não existem importações.')),
                );
              }
              return Column(
                children: entries.map(_historyCard).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _previewCard(ImportDefinition definition, ImportRowPreview row) {
    final summary = definition.fields
        .where((field) => row.mappedData[field.key]?.toString().trim().isNotEmpty == true)
        .take(4)
        .map((field) => '${field.label}: ${row.mappedData[field.key]}')
        .join(' • ');

    return Card(
      child: ListTile(
        leading: Icon(
          row.valid ? Icons.check_circle_outline : Icons.error_outline,
        ),
        title: Text('Linha ${row.rowNumber}'),
        subtitle: Text(
          row.valid ? summary : row.errors.join('\n'),
          maxLines: row.valid ? 3 : 6,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Editar e revalidar',
          onPressed: _busy ? null : () => _editRow(row),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
    );
  }

  Widget _historyCard(ImportHistoryEntry entry) {
    String targetTitle;
    try {
      targetTitle = ImportCatalog.byKey(entry.target).title;
    } catch (_) {
      targetTitle = entry.target;
    }

    final date = entry.createdAt == null
        ? ''
        : DateFormat('dd/MM/yyyy HH:mm').format(entry.createdAt!.toLocal());

    return Card(
      child: ListTile(
        leading: Icon(
          switch (entry.status) {
            'applied' => Icons.check_circle_outline,
            'reverted' => Icons.undo_outlined,
            'failed' => Icons.error_outline,
            'ready' => Icons.fact_check_outlined,
            _ => Icons.edit_outlined,
          },
        ),
        title: Text('$targetTitle • ${entry.filename}'),
        subtitle: Text(
          [
            if (date.isNotEmpty) date,
            '${entry.totalRows} linhas',
            _statusLabel(entry.status),
          ].join(' • '),
        ),
        trailing: entry.status == 'applied'
            ? IconButton(
                tooltip: 'Reverter importação',
                onPressed: _busy ? null : () => _rollback(entry),
                icon: const Icon(Icons.undo),
              )
            : null,
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'ready' => 'Pronta',
      'applied' => 'Aplicada',
      'reverted' => 'Revertida',
      'failed' => 'Falhou',
      _ => 'Rascunho',
    };
