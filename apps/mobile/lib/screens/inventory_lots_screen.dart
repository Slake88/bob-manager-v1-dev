import 'package:flutter/material.dart';

import '../repositories/inventory_advanced_repository.dart';

class InventoryLotsScreen extends StatefulWidget {
  const InventoryLotsScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final InventoryAdvancedRepository repository;
  final VoidCallback onChanged;

  @override
  State<InventoryLotsScreen> createState() => _InventoryLotsScreenState();
}

class _InventoryLotsScreenState extends State<InventoryLotsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.repository.canManage
        ? widget.repository.lots()
        : Future<List<Map<String, dynamic>>>.value(const []);
  }

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
    widget.onChanged();
  }

  Future<void> _receive() async {
    List<Map<String, dynamic>> catalog;
    List<Map<String, dynamic>> locations;
    try {
      final values = await Future.wait([
        widget.repository.catalogItems(),
        widget.repository.locations(),
      ]);
      catalog = values[0];
      locations = values[1];
    } catch (error) {
      if (!mounted) return;
      _snack(_friendly(error));
      return;
    }
    if (!mounted) return;
    if (catalog.isEmpty || locations.isEmpty) {
      _snack('É necessário ter artigos e localizações ativas.');
      return;
    }

    final lotCode = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final cost = TextEditingController();
    final supplier = TextEditingController();
    final notes = TextEditingController();
    var itemIndex = 0;
    var locationIndex = 0;
    var receivedAt = DateTime.now();
    DateTime? expiresAt;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Receber lote'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: itemIndex,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Artigo'),
                    items: [
                      for (var index = 0; index < catalog.length; index++)
                        DropdownMenuItem(
                          value: index,
                          child: Text(
                            inventoryItemLabel(catalog[index]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => itemIndex = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: locationIndex,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Localização'),
                    items: [
                      for (var index = 0; index < locations.length; index++)
                        DropdownMenuItem(
                          value: index,
                          child: Text(locations[index]['name']?.toString() ?? 'Local'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => locationIndex = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lotCode,
                    decoration: const InputDecoration(labelText: 'Código / lote'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantidade recebida'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Receção: ${inventoryDateLabel(receivedAt)}'),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: dialogContext,
                              initialDate: receivedAt,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (date != null && dialogContext.mounted) {
                              setDialogState(() => receivedAt = date);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.event_available_outlined),
                          label: Text(
                            expiresAt == null
                                ? 'Sem validade definida'
                                : 'Validade: ${inventoryDateLabel(expiresAt)}',
                          ),
                          onPressed: () async {
                            final date = await showDatePicker(
                              context: dialogContext,
                              initialDate: expiresAt ?? receivedAt.add(const Duration(days: 30)),
                              firstDate: receivedAt,
                              lastDate: DateTime(receivedAt.year + 10),
                            );
                            if (date != null && dialogContext.mounted) {
                              setDialogState(() => expiresAt = date);
                            }
                          },
                        ),
                      ),
                      if (expiresAt != null)
                        IconButton(
                          tooltip: 'Remover validade',
                          onPressed: () => setDialogState(() => expiresAt = null),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cost,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Custo unitário (€) — opcional'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: supplier,
                    decoration: const InputDecoration(labelText: 'Fornecedor — opcional'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Notas — opcional'),
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
                final unitCost = cost.text.trim().isEmpty
                    ? null
                    : double.tryParse(cost.text.replaceAll(',', '.'));
                if (qty == null || qty <= 0 || lotCode.text.trim().isEmpty) return;
                final item = catalog[itemIndex];
                final location = locations[locationIndex];
                try {
                  await widget.repository.receiveLot(
                    productId: item['product_id'].toString(),
                    variantId: item['variant_id']?.toString(),
                    locationId: location['id'].toString(),
                    lotCode: lotCode.text,
                    quantity: qty,
                    receivedAt: receivedAt,
                    expiresAt: expiresAt,
                    unitCost: unitCost,
                    supplier: supplier.text,
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
              child: const Text('Receber'),
            ),
          ],
        ),
      ),
    );

    lotCode.dispose();
    quantity.dispose();
    cost.dispose();
    supplier.dispose();
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
              title: Text('Lotes, validades e custos são restritos'),
              subtitle: Text(
                'Esta área está disponível para o responsável de inventário e direção.',
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
            return _LotsError(error: snapshot.error!, onRetry: _refresh);
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
                      Icon(Icons.inventory_outlined, size: 54),
                      SizedBox(height: 12),
                      Center(child: Text('Ainda não existem lotes registados.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final days = int.tryParse(row['days_to_expiry']?.toString() ?? '');
                      final warning = row['status'] == 'expired' ||
                          (row['status'] == 'active' && days != null && days <= 30);
                      final cost = row['unit_cost'] == null
                          ? '—'
                          : '${inventoryQuantity(row['unit_cost']).toStringAsFixed(2)} €';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              warning
                                  ? Icons.warning_amber_outlined
                                  : Icons.inventory_2_outlined,
                            ),
                          ),
                          title: Text('${inventoryItemLabel(row)} · Lote ${row['lot_code']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['location_name'] ?? 'Local'} · '
                                '${_qty(inventoryQuantity(row['quantity']))} / '
                                '${_qty(inventoryQuantity(row['initial_quantity']))} un.',
                              ),
                              Text(
                                row['expires_at'] == null
                                    ? 'Sem validade definida'
                                    : 'Validade ${inventoryDateLabel(row['expires_at'])}'
                                        '${days == null ? '' : ' · $days dias'}',
                              ),
                              Text('Custo: $cost${row['supplier'] == null ? '' : ' · ${row['supplier']}'}'),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(inventoryLotStatusLabel(row['status'])),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _receive,
        icon: const Icon(Icons.add_box_outlined),
        label: const Text('Receber lote'),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LotsError extends StatelessWidget {
  const _LotsError({required this.error, required this.onRetry});

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

String _qty(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2);

String _friendly(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '');
