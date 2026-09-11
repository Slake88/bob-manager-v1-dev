import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/club_export.dart';
import '../repositories/club_export_repository.dart';
import '../services/club_export_service.dart';

class ClubExportScreen extends StatefulWidget {
  const ClubExportScreen({super.key});

  @override
  State<ClubExportScreen> createState() => _ClubExportScreenState();
}

class _ClubExportScreenState extends State<ClubExportScreen> {
  final ClubExportRepository _repository = ClubExportRepository();
  final ClubExportService _service = ClubExportService();
  final Set<ClubExportSection> _selected = ClubExportSection.values.toSet();

  bool _includeSensitive = false;
  bool _includeFiles = false;
  bool _busy = false;
  String _progress = '';
  late Future<List<Map<String, dynamic>>> _history;

  bool get _canSensitive =>
      ClubExportPolicy.canIncludeSensitive(AppSession.instance);

  @override
  void initState() {
    super.initState();
    _history = _repository.history();
  }

  void _selectAll() {
    setState(() {
      _selected
        ..clear()
        ..addAll(ClubExportSection.values);
    });
  }

  void _clearAll() {
    setState(() => _selected.clear());
  }

  Future<void> _generate() async {
    if (_selected.isEmpty) {
      _message('Seleciona pelo menos uma área.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gerar exportação integral?'),
        content: Text(
          [
            '${_selected.length} áreas selecionadas.',
            if (_includeSensitive)
              'Inclui dados altamente sensíveis de membros/documentos.',
            if (_includeFiles)
              'Inclui ficheiros armazenados e pode criar um ZIP de grande dimensão.',
            'A operação fica registada na auditoria do clube.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Gerar ZIP'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _progress = 'A iniciar...';
    });

    try {
      final package = await _service.generate(
        sections: _selected,
        includeSensitive: _includeSensitive,
        includeFiles: _includeFiles,
        onProgress: (message) {
          if (!mounted) return;
          setState(() => _progress = message);
        },
      );
      if (!mounted) return;
      await _service.share(context, package);
      if (!mounted) return;
      setState(() => _history = _repository.history());
      _message(
        'Exportação concluída: ${package.datasetCount} ficheiros de dados, '
        '${package.rowCount} registos e ${package.fileCount} ficheiros anexos.',
      );
    } on ClubExportFailure catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message('Não foi possível gerar a exportação integral.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
      }
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ClubExportPolicy.canExport(AppSession.instance)) {
      return const Scaffold(
        body: Center(child: Text('Sem permissão para exportação integral.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Exportação Integral do Clube')),
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
                    'Arquivo administrativo BOB',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cria um ZIP estruturado com manifest.json e CSVs por área. '
                    'O pacote é gerado no dispositivo; o Supabase guarda apenas '
                    'metadata e auditoria da operação.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Nunca são exportados passwords, sessões Auth, service_role, '
                    'tokens push nem payloads completos do audit log.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Áreas',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(onPressed: _busy ? null : _selectAll, child: const Text('Todas')),
              TextButton(onPressed: _busy ? null : _clearAll, child: const Text('Nenhuma')),
            ],
          ),
          ...ClubExportSection.values.map(
            (section) => Card(
              child: CheckboxListTile(
                value: _selected.contains(section),
                onChanged: _busy
                    ? null
                    : (value) {
                        setState(() {
                          if (value == true) {
                            _selected.add(section);
                          } else {
                            _selected.remove(section);
                          }
                        });
                      },
                title: Text(section.title),
                subtitle: Text(section.description),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Opções protegidas',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Card(
            child: SwitchListTile(
              value: _includeSensitive,
              onChanged: !_canSensitive || _busy
                  ? null
                  : (value) => setState(() => _includeSensitive = value),
              title: const Text('Incluir dados altamente sensíveis'),
              subtitle: Text(
                _canSensitive
                    ? 'NIF, morada, contacto de emergência/notas privadas e '
                        'metadata/documentos marcados como sensíveis.'
                    : 'Exige simultaneamente permissão para Emergência e '
                        'Documentos Sensíveis.',
              ),
              secondary: const Icon(Icons.security_outlined),
            ),
          ),
          Card(
            child: SwitchListTile(
              value: _includeFiles,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _includeFiles = value),
              title: const Text('Incluir ficheiros armazenados'),
              subtitle: const Text(
                'Inclui fotografias e anexos conhecidos através das mesmas '
                'regras de Storage/RLS. Limite de proteção: 200 MB.',
              ),
              secondary: const Icon(Icons.folder_zip_outlined),
            ),
          ),
          const SizedBox(height: 12),
          if (_busy)
            Card(
              child: ListTile(
                leading: const CircularProgressIndicator(),
                title: const Text('A gerar exportação...'),
                subtitle: Text(_progress),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.archive_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Gerar e partilhar ZIP'),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            'Histórico recente',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _history,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Não foi possível carregar o histórico.'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const Card(
                  child: ListTile(title: Text('Ainda não existem exportações.')),
                );
              }
              return Column(children: rows.map(_historyCard).toList());
            },
          ),
        ],
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? 'running';
    final requested = DateTime.tryParse(row['requested_at']?.toString() ?? '');
    final modules = row['modules'];
    final moduleCount = modules is List ? modules.length : 0;
    final byteSize = int.tryParse(row['byte_size']?.toString() ?? '') ?? 0;

    return Card(
      child: ListTile(
        leading: Icon(
          switch (status) {
            'completed' => Icons.check_circle_outline,
            'failed' => Icons.error_outline,
            _ => Icons.hourglass_top,
          },
        ),
        title: Text(
          switch (status) {
            'completed' => 'Concluída',
            'failed' => 'Falhou',
            _ => 'Em processamento',
          },
        ),
        subtitle: Text(
          [
            if (requested != null)
              DateFormat('dd/MM/yyyy HH:mm').format(requested.toLocal()),
            '$moduleCount áreas',
            '${row['row_count'] ?? 0} registos',
            if (status == 'completed') _bytes(byteSize),
            if (row['include_sensitive'] == true) 'dados sensíveis',
            if (row['include_files'] == true) 'com ficheiros',
          ].join(' • '),
        ),
      ),
    );
  }
}

String _bytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '$value B';
}
