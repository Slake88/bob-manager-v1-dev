import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/inventory_location_rules.dart';
import '../core/permissions.dart';
import '../repositories/inventory_control_repository.dart';

class InventoryLocationsScreen extends StatefulWidget {
  const InventoryLocationsScreen({super.key});

  @override
  State<InventoryLocationsScreen> createState() =>
      _InventoryLocationsScreenState();
}

class _InventoryLocationsScreenState extends State<InventoryLocationsScreen> {
  final InventoryControlRepository _repository = InventoryControlRepository();
  final TextEditingController _search = TextEditingController();

  late Future<_LocationData> _future;
  String _location = 'all';
  String _area = 'all';

  bool get _canManage => AppSession.instance.can(AppPermission.manageInventory);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _future = _load();
  }

  Future<_LocationData> _load() async {
    final data = await Future.wait([
      _repository.stockByLocation(),
      _repository.locations(),
    ]);
    return _LocationData(
      stock: data[0],
      locations: data[1],
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _transfer(
    Map<String, dynamic> row,
    _LocationData data,
  ) async {
    final fromId = row['location_id']?.toString();
    if (fromId == null) return;

    final destinations = data.locations
        .where((location) => location['id']?.toString() != fromId)
        .toList();

    if (destinations.isEmpty) {
      _message('Não existe outro local ativo para receber o stock.');
      return;
    }

    final input = await showDialog<_TransferInput>(
      context: context,
      builder: (_) => _TransferDialog(
        row: row,
        destinations: destinations,
      ),
    );
    if (input == null) return;

    final available = _num(row['available_quantity']);
    final error = InventoryLocationRules.validateTransfer(
      fromLocationId: fromId,
      toLocationId: input.toLocationId,
      quantity: input.quantity,
      available: available,
    );
    if (error != null) {
      _message(error);
      return;
    }

    try {
      await _repository.transferStock(
        productId: row['product_id'].toString(),
        variantId: row['variant_id']?.toString(),
        fromLocationId: fromId,
        toLocationId: input.toLocationId,
        quantity: input.quantity,
        notes: input.notes,
      );
      if (!mounted) return;
      _message('Transferência concluída.');
      setState(_reload);
    } catch (error) {
      _message(error.toString());
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_LocationData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final query = _search.text.trim().toLowerCase();
        final rows = data.stock.where((row) {
          final product = row['product_name']?.toString() ?? '';
          final variant = row['variant_name']?.toString() ?? '';
          final sku = row['sku']?.toString() ?? '';
          final location = row['location_name']?.toString() ?? '';
          final text = '$product $variant $sku $location'.toLowerCase();

          return (query.isEmpty || text.contains(query)) &&
              (_location == 'all' ||
                  row['location_id']?.toString() == _location) &&
              (_area == 'all' || row['inventory_area'] == _area);
        }).toList();

        final total = rows.fold<double>(
          0,
          (value, row) => value + _num(row['quantity']),
        );
        final available = rows.fold<double>(
          0,
          (value, row) => value + _num(row['available_quantity']),
        );
        final locationCount =
            rows.map((row) => row['location_id']?.toString()).toSet().length;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Stock por Localização',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Transferir stock altera a distribuição entre locais sem alterar o total global.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _metric(
                    context,
                    'Locais',
                    '$locationCount',
                    Icons.place_outlined,
                  ),
                  _metric(
                    context,
                    'Stock',
                    _qty(total),
                    Icons.inventory_2_outlined,
                  ),
                  _metric(
                    context,
                    'Disponível',
                    _qty(available),
                    Icons.check_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Pesquisar artigo, SKU ou local',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _location,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Local',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos os locais'),
                        ),
                        ...data.locations.map(
                          (location) => DropdownMenuItem(
                            value: location['id'].toString(),
                            child: Text(
                              location['name']?.toString() ?? 'Local',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _location = value ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      initialValue: _area,
                      decoration: const InputDecoration(
                        labelText: 'Área',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Todas')),
                        DropdownMenuItem(value: 'shop', child: Text('Loja')),
                        DropdownMenuItem(value: 'bar', child: Text('Bar')),
                      ],
                      onChanged: (value) =>
                          setState(() => _area = value ?? 'all'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Sem stock para os filtros selecionados.'),
                  ),
                )
              else
                for (final row in rows)
                  _stockCard(
                    context,
                    row,
                    onTransfer:
                        _canManage && _num(row['available_quantity']) > 0
                            ? () => _transfer(row, data)
                            : null,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _LocationData {
  const _LocationData({
    required this.stock,
    required this.locations,
  });

  final List<Map<String, dynamic>> stock;
  final List<Map<String, dynamic>> locations;
}

class _TransferInput {
  const _TransferInput({
    required this.toLocationId,
    required this.quantity,
    required this.notes,
  });

  final String toLocationId;
  final double quantity;
  final String notes;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    required this.row,
    required this.destinations,
  });

  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> destinations;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  late String _toLocationId;
  final TextEditingController _quantity = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _toLocationId = widget.destinations.first['id'].toString();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = _num(widget.row['available_quantity']);
    final product = widget.row['product_name']?.toString() ?? 'Artigo';
    final variant = widget.row['variant_name']?.toString();
    final name =
        variant == null || variant.isEmpty ? product : '$product · $variant';

    return AlertDialog(
      title: const Text('Transferir stock'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Origem: ${widget.row['location_name']} · '
              'Disponível: ${_qty(available)}',
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _toLocationId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Destino',
                border: OutlineInputBorder(),
              ),
              items: widget.destinations
                  .map(
                    (location) => DropdownMenuItem(
                      value: location['id'].toString(),
                      child: Text(
                        location['name']?.toString() ?? 'Local',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _toLocationId = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final quantity = _parse(_quantity.text);
            final error = InventoryLocationRules.validateTransfer(
              fromLocationId: widget.row['location_id']?.toString(),
              toLocationId: _toLocationId,
              quantity: quantity,
              available: available,
            );
            if (error != null) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(error)));
              return;
            }
            Navigator.pop(
              context,
              _TransferInput(
                toLocationId: _toLocationId,
                quantity: quantity,
                notes: _notes.text,
              ),
            );
          },
          child: const Text('Transferir'),
        ),
      ],
    );
  }
}

Widget _stockCard(
  BuildContext context,
  Map<String, dynamic> row, {
  VoidCallback? onTransfer,
}) {
  final product = row['product_name']?.toString() ?? 'Artigo';
  final variant = row['variant_name']?.toString();
  final name =
      variant == null || variant.isEmpty ? product : '$product · $variant';
  final quantity = _num(row['quantity']);
  final reserved = _num(row['reserved_quantity']);
  final available = _num(row['available_quantity']);

  return Card(
    child: ListTile(
      leading: CircleAvatar(
        child: Icon(
          row['inventory_area'] == 'bar'
              ? Icons.local_bar_outlined
              : Icons.storefront_outlined,
        ),
      ),
      title: Text(name),
      subtitle: Text(
        [
          row['location_name']?.toString() ?? 'Local',
          if ((row['sku']?.toString() ?? '').isNotEmpty) 'SKU ${row['sku']}',
          'Stock ${_qty(quantity)}',
          if (reserved > 0) 'Reservado ${_qty(reserved)}',
          'Disponível ${_qty(available)}',
        ].join(' · '),
      ),
      trailing: onTransfer == null
          ? null
          : IconButton(
              tooltip: 'Transferir stock',
              onPressed: onTransfer,
              icon: const Icon(Icons.swap_horiz),
            ),
    ),
  );
}

Widget _metric(
  BuildContext context,
  String label,
  String value,
  IconData icon,
) {
  return SizedBox(
    width: 190,
    child: Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(label),
        subtitle: Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
      ),
    ),
  );
}

double _num(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString() ?? '') ?? 0;

double _parse(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;

String _qty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceAll('.', ',');
