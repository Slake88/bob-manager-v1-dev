import 'package:flutter/material.dart';

import '../repositories/inventory_advanced_repository.dart';

class InventoryReservationsScreen extends StatefulWidget {
  const InventoryReservationsScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final InventoryAdvancedRepository repository;
  final VoidCallback onChanged;

  @override
  State<InventoryReservationsScreen> createState() =>
      _InventoryReservationsScreenState();
}

class _InventoryReservationsScreenState
    extends State<InventoryReservationsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = widget.repository.reservations();

  void _refresh() {
    if (!mounted) return;
    setState(_reload);
    widget.onChanged();
  }

  Future<void> _create() async {
    List<Map<String, dynamic>> stock;
    try {
      stock = (await widget.repository.stockRows())
          .where((row) => inventoryQuantity(row['available_quantity']) > 0)
          .toList();
    } catch (error) {
      if (!mounted) return;
      _snack(_friendlyError(error));
      return;
    }
    if (!mounted) return;
    if (stock.isEmpty) {
      _snack('Não existe stock disponível para reservar.');
      return;
    }

    final quantity = TextEditingController(text: '1');
    final notes = TextEditingController();
    var selected = 0;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Nova reserva'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Artigo / local'),
                  items: [
                    for (var index = 0; index < stock.length; index++)
                      DropdownMenuItem<int>(
                        value: index,
                        child: Text(
                          '${inventoryItemLabel(stock[index])} · '
                          '${stock[index]['location_name']} '
                          '(${_qty(inventoryQuantity(stock[index]['available_quantity']))} disp.)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selected = value);
                    }
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
                  decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'A reserva é válida por 30 dias e é libertada automaticamente no fim do prazo.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final value = double.tryParse(quantity.text.replaceAll(',', '.'));
                if (value == null || value <= 0) return;
                final row = stock[selected];
                try {
                  await widget.repository.createReservation(
                    productId: row['product_id'].toString(),
                    variantId: row['variant_id']?.toString(),
                    locationId: row['location_id'].toString(),
                    quantity: value,
                    notes: notes.text,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text(_friendlyError(error))),
                    );
                  }
                }
              },
              child: const Text('Reservar'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    notes.dispose();
    if (saved == true) _refresh();
  }

  Future<void> _close(Map<String, dynamic> row, String action) async {
    final label = action == 'release' ? 'libertar' : 'cancelar';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${action == 'release' ? 'Libertar' : 'Cancelar'} reserva?'),
        content: Text(
          '${inventoryItemLabel(row)} · ${_qty(inventoryQuantity(row['quantity']))} un.\n'
          'Pretendes $label esta reserva?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repository.closeReservation(
        row['id'].toString(),
        action: action,
      );
      if (!mounted) return;
      _refresh();
      _snack(action == 'release' ? 'Reserva libertada.' : 'Reserva cancelada.');
    } catch (error) {
      if (!mounted) return;
      _snack(_friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(error: snapshot.error!, onRetry: _refresh);
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
                      Icon(Icons.bookmark_add_outlined, size: 54),
                      SizedBox(height: 12),
                      Center(child: Text('Ainda não existem reservas.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: rows.length,
                    itemBuilder: (_, index) {
                      final row = rows[index];
                      final active = row['status'] == 'active';
                      final days = int.tryParse(row['days_remaining']?.toString() ?? '');
                      final expiring = active && days != null && days <= 3;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                expiring ? Icons.alarm_outlined : Icons.bookmark_outline,
                              ),
                            ),
                            title: Text(inventoryItemLabel(row)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['location_name'] ?? 'Local'} · '
                                  '${_qty(inventoryQuantity(row['quantity']))} un.',
                                ),
                                if (widget.repository.canManage)
                                  Text('Membro: ${row['member_name'] ?? '—'}'),
                                Text(
                                  active
                                      ? 'Expira em ${days ?? '—'} dias · '
                                          '${inventoryDateLabel(row['expires_at'])}'
                                      : inventoryReservationStatusLabel(row['status']),
                                ),
                              ],
                            ),
                            trailing: active && row['can_cancel'] == true
                                ? PopupMenuButton<String>(
                                    onSelected: (value) => _close(row, value),
                                    itemBuilder: (_) => [
                                      if (!widget.repository.canManage)
                                        const PopupMenuItem(
                                          value: 'cancel',
                                          child: Text('Cancelar reserva'),
                                        ),
                                      if (widget.repository.canManage)
                                        const PopupMenuItem(
                                          value: 'release',
                                          child: Text('Libertar stock'),
                                        ),
                                    ],
                                  )
                                : Chip(
                                    label: Text(
                                      inventoryReservationStatusLabel(row['status']),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Reservar'),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

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
            Text(_friendlyError(error), textAlign: TextAlign.center),
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

String _qty(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}

String _friendlyError(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
  return raw.isEmpty ? 'Ocorreu um erro.' : raw;
}
