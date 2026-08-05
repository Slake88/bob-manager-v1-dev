import 'package:flutter/material.dart';

import '../services/data_service.dart';

class EntityListScreen extends StatefulWidget {
  const EntityListScreen({
    super.key,
    required this.title,
    required this.table,
    required this.primaryField,
    this.subtitleFields = const [],
  });

  final String title;
  final String table;
  final String primaryField;
  final List<String> subtitleFields;

  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _future = DataService.instance.list(widget.table);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  String _titleFor(Map<String, dynamic> row) {
    final value = row[widget.primaryField];
    if (value == null || value.toString().trim().isEmpty) {
      return 'Registo';
    }
    return value.toString();
  }

  String _subtitleFor(Map<String, dynamic> row) {
    return widget.subtitleFields
        .map((field) => row[field])
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString())
        .join(' • ');
  }

  String _detailsFor(Map<String, dynamic> row) {
    return row.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }

  void _showDetails(Map<String, dynamic> row) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(_titleFor(row)),
          content: SingleChildScrollView(
            child: SelectableText(_detailsFor(row)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Erro: ${snapshot.error}'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final query = _searchController.text.trim().toLowerCase();
        final rows = snapshot.data!.where((row) {
          if (query.isEmpty) return true;
          return row.values.any(
            (value) => value.toString().toLowerCase().contains(query),
          );
        }).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Pesquisar em ${widget.title}',
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.inbox_outlined),
                    title: Text('Sem registos.'),
                  ),
                )
              else
                ...rows.map(
                  (row) {
                    final subtitle = _subtitleFor(row);
                    return Card(
                      child: ListTile(
                        title: Text(_titleFor(row)),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showDetails(row),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 80),
            ],
          ),
        );
      },
    );
  }
}
