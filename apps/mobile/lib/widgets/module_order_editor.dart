import 'package:flutter/material.dart';

import '../core/module_definition.dart';

class ModuleOrderEditor extends StatefulWidget {
  const ModuleOrderEditor({
    super.key,
    required this.modules,
    required this.initialOrder,
    required this.onSave,
  });

  final List<ModuleDefinition> modules;
  final List<String> initialOrder;
  final Future<void> Function(List<String> order) onSave;

  @override
  State<ModuleOrderEditor> createState() => _ModuleOrderEditorState();
}

class _ModuleOrderEditorState extends State<ModuleOrderEditor> {
  late List<ModuleDefinition> _draft;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = _orderedModules(widget.initialOrder);
  }

  List<ModuleDefinition> _orderedModules(Iterable<String> codes) {
    final byCode = {for (final module in widget.modules) module.code: module};
    final result = <ModuleDefinition>[];
    for (final code in codes) {
      final module = byCode.remove(code);
      if (module != null) result.add(module);
    }
    result.addAll(byCode.values);
    return result;
  }

  void _move(int index, int offset) {
    final destination = index + offset;
    if (destination < 0 || destination >= _draft.length) return;
    setState(() {
      final module = _draft.removeAt(index);
      _draft.insert(destination, module);
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = _draft.map((module) => module.code).toList();
      await widget.onSave(order);
      if (mounted) Navigator.of(context).pop(order);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Não foi possível guardar a ordem. Tente novamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetDraft() {
    setState(() {
      _draft = List<ModuleDefinition>.of(widget.modules);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Personalizar menu',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Cancelar',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Arraste ou use os controlos para alterar a ordem.'),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _draft.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final module = _draft.removeAt(oldIndex);
                    _draft.insert(newIndex, module);
                    _error = null;
                  });
                },
                itemBuilder: (context, index) {
                  final module = _draft[index];
                  return ListTile(
                    key: ValueKey(module.code),
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(module.title),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Subir ${module.title}',
                          onPressed: index == 0 || _saving
                              ? null
                              : () => _move(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Descer ${module.title}',
                          onPressed: index == _draft.length - 1 || _saving
                              ? null
                              : () => _move(index, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _resetDraft,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Repor ordem original'),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar ordem'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
