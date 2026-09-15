import 'package:flutter/material.dart';

import '../repositories/inventory_advanced_repository.dart';

class InventoryBreakagesScreen extends StatefulWidget {
  const InventoryBreakagesScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final InventoryAdvancedRepository repository;
  final VoidCallback onChanged;

  @override
  State<InventoryBreakagesScreen> createState() =>
      _InventoryBreakagesScreenState();
}

class _InventoryBreakagesScreenState extends State<InventoryBreakagesScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.canManage
        ? widget.repository.breakages()
        : Future<List<Map<String, dynamic>>>.value(const []);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
    widget.onChanged();
  }

  Future<void> _record() async {
    List<Map<String, dynamic>> stock;
    List<Map<String, dynamic>> lots;
    try {
      final values = await Future.wait([
        widget.repository.stockRows(),
        widget.repository.lots(),
      ]);
      stock = values[0]
          .where((row) => inventoryQuantity(row['quantity']) > 0)
          .toList();
      lots = values[1];
    } catch (error) {
      if (!mounted) return;
      _snack(_friendly(error));
      return;
    }
    if (!mounted) return;
    if (stock.isEmpty) {
      _snack('Não existe stock físico para registar uma quebra/perda.');
      return;
    }

    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    var itemIndex = 0;
    var reason = 'breakage';
    var selectedLotId = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final item = stock[itemIndex];
          final matchingLots = lots.where((lot) {
            return lot['product_id'] == item['product_id'] &&
                lot['variant_id'] == item['variant_id'] &&
                lot['location_id'] == item['location_id'] &&
                inventoryQuantity(lot['quantity']) > 0;
          }).toList();
          if (selectedLotId.isNotEmpty &&
              !matchingLots.any((lot) => lot['id'].toString() == selectedLotId)) {
            selectedLotId = '';
          }

          return AlertDialog(
            title: const Text('Registar quebra / perda'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: itemIndex,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Artigo / local'),
                      items: [
                        for (var index = 0; index < stock.length; index++)
                          DropdownMenuItem(
                            value: index,
                            child: Text(
                              '${inventoryItemLabel(stock[index])} · '
                              '${stock[index]['location_name']} '
                              '(${_qty(inventoryQuantity(stock[index]['quantity']))} un.)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            itemIndex = value;
                            selectedLotId = '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: reason,
                      decoration: const InputDecoration(labelText: 'Motivo'),
                      items: const [
                        DropdownMenuItem(value: 'breakage', child: Text('Quebra')),
                        DropdownMenuItem(value: 'expiry', child: Text('Validade')),
                        DropdownMenuItem(value: 'damage', child: Text('Dano')),
                        DropdownMenuItem(value: 'loss', child: Text('Perda')),
                        DropdownMenuItem(value: 'other', child: Text('Outro')),
                      ],
                      onChanged: (value) {
                        if (value != null) setDialogState(() => reason = value);
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedLotId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Lote (opcional)'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Automático · prioridade à validade mais próxima'),
                        ),
                        for (final lot in matchingLots)
                          DropdownMenuItem(
                            value: lot['id'].toString(),
                            child: Text(
                              '${lot['lot_code']} · ${_qty(inventoryQuantity(lot['quantity']))} un.'
                              '${lot['expires_at'] == null ? '' : ' · ${inventoryDateLabel(lot['expires_at'])}'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        setDialogState(() => selectedLotId = value ?? '');
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quantity,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Quantidade'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Justificação / notas'),
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'A operação retira stock e fica registada no histórico como perda.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () async {
                  final qty = double.tryParse(quantity.text.replaceAll(',', '.'));
                  if (qty == null || qty <= 0) return;
                  final selected = stock[itemIndex];
                  try {
                    await widget.repository.recordBreakage(
                      productId: selected['product_id'].toString(),
                      variantId: selected['variant_id']?.toString(),
                      locationId: selected['location_id'].toString(),
                      quantity: qty,
                      reason: reason,
                      lotId: selectedLotId.isEmpty ? null : selectedLotId,
                      notes: notes.text,
                    );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (error) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text(_friendly(error))),
                      );
                    }
                  }
                },
                child: const Text('Registar'),
              ),
            ],
          );
        },
      ),
    );

    quantity.dispose();
    notes.dispose();
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.canManage) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Quebras e perdas são restritas'),
              subtitle: Text(
                'Só o responsável de inventário e direção podem retirar stock por quebra, dano, validade ou perda.',
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _BreakageError(error: snapshot.error!, onRetry: _refresh);
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 80),
                      Icon(Icons.verified_outlined, size: 54),
                      SizedBox(height: 12),
                      Center(child: Text('Não existem quebras/perdas registadas.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final product = row['product_name']?.toString() ??
                          _relationName(row, 'products') ??
                          'Produto';
                      final variant = row['variant_name']?.toString() ??
                          _relationName(row, 'product_variants');
                      final location = row['location_name']?.toString() ??
                          _relationName(row, 'inventory_locations') ??
                          'Local';
                      final lot = row['lot_code']?.toString() ??
                          _relationValue(row, 'stock_lots', 'lot_code');
                      final itemLabel = variant == null || variant.trim().isEmpty
                          ? product
                          : '$product · $variant';
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                          title: Text(
                            '${inventoryBreakageReasonLabel(row['reason'])} · $itemLabel',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$location · ${_qty(inventoryQuantity(row['quantity']))} un.'
                                '${lot == null ? '' : ' · Lote $lot'}',
                              ),
                              Text(inventoryDateLabel(row['created_at'])),
                              if (row['notes']?.toString().trim().isNotEmpty == true)
                                Text(
                                  row['notes'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _record,
        icon: const Icon(Icons.remove_circle_outline),
        label: const Text('Registar quebra'),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _BreakageError extends StatelessWidget {
  const _BreakageError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 10),
            Text(_friendly(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

String? _relationName(Map<String, dynamic> row, String key) =>
    _relationValue(row, key, 'name');

String? _relationValue(Map<String, dynamic> row, String key, String field) {
  final value = row[key];
  if (value is Map && value[field] != null) return value[field].toString();
  return null;
}

String _qty(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

String _friendly(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '');
