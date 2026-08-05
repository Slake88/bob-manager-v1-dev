import 'package:flutter/material.dart';

import '../core/entity_definition.dart';
import '../services/data_service.dart';
import 'entity_form_screen.dart';

class EntityCrudScreen extends StatefulWidget {
  const EntityCrudScreen({
    super.key,
    required this.definition,
    this.detailBuilder,
  });

  final EntityDefinition definition;
  final Widget Function(Map<String, dynamic> row)? detailBuilder;

  @override
  State<EntityCrudScreen> createState() => _EntityCrudScreenState();
}

class _EntityCrudScreenState extends State<EntityCrudScreen> {
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
    _future = DataService.instance.list(widget.definition.table);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  String _titleFor(Map<String, dynamic> row) {
    final value = row[widget.definition.primaryField];
    return value == null || value.toString().trim().isEmpty
        ? widget.definition.singularTitle
        : value.toString();
  }

  String _subtitleFor(Map<String, dynamic> row) {
    return widget.definition.subtitleFields
        .map((field) => row[field])
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString())
        .join(' • ');
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: widget.definition,
          initialValues: row,
        ),
      ),
    );
    if (changed == true) setState(_reload);
  }

  Future<void> _openDetails(Map<String, dynamic> row) async {
    if (widget.detailBuilder != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => widget.detailBuilder!(row)),
      );
      setState(_reload);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _titleFor(row),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      runSpacing: 8,
                      children: widget.definition.fields.map((field) {
                        final value = row[field.key];
                        if (value == null || value.toString().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(field.label),
                          subtitle: Text(value.toString()),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (widget.definition.canEdit)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openForm(row);
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar'),
                        ),
                      ),
                    if (widget.definition.canEdit &&
                        widget.definition.canDelete)
                      const SizedBox(width: 12),
                    if (widget.definition.canDelete)
                      IconButton.filledTonal(
                        tooltip: 'Eliminar',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _confirmDelete(row);
                        },
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar registo?'),
        content: Text(
          'Pretendes eliminar “${_titleFor(row)}”? Esta ação fica sujeita às regras de auditoria na base real.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DataService.instance.delete(
      widget.definition.table,
      row['id'].toString(),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Pesquisar em ${widget.definition.title}',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${rows.length} registo${rows.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.inbox_outlined),
                      title: Text('Sem registos.'),
                      subtitle: Text('Usa o botão + para criar o primeiro.'),
                    ),
                  )
                else
                  ...rows.map((row) {
                    final subtitle = _subtitleFor(row);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(widget.definition.icon),
                        ),
                        title: Text(_titleFor(row)),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'view') _openDetails(row);
                            if (action == 'edit') _openForm(row);
                            if (action == 'delete') _confirmDelete(row);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Text('Consultar'),
                            ),
                            if (widget.definition.canEdit)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar'),
                              ),
                            if (widget.definition.canDelete)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Eliminar'),
                              ),
                          ],
                        ),
                        onTap: () => _openDetails(row),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: widget.definition.canCreate
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.add),
              label: Text('Novo ${widget.definition.singularTitle}'),
            )
          : null,
    );
  }
}
