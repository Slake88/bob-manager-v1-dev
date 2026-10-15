import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/inventory_control_repository.dart';

class InventoryMovementsScreen extends StatefulWidget {
  const InventoryMovementsScreen({super.key});

  @override
  State<InventoryMovementsScreen> createState() =>
      _InventoryMovementsScreenState();
}

class _InventoryMovementsScreenState extends State<InventoryMovementsScreen> {
  final InventoryControlRepository _repository = InventoryControlRepository();
  late Future<List<Map<String, dynamic>>> _future;
  final TextEditingController _search = TextEditingController();
  String _kind = 'all';
  String _area = 'all';

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

  void _reload() => _future = _repository.movements();

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final query = _search.text.trim().toLowerCase();
          final rows = all.where((row) {
            final product = row['products'];
            final variant = row['product_variants'];
            final event = row['events'];
            final user = row['profiles'];
            final from = row['from_location'];
            final to = row['to_location'];

            final text = '${product is Map ? product['name'] : ''} '
                    '${variant is Map ? variant['name'] : ''} '
                    '${event is Map ? event['name'] : ''} '
                    '${user is Map ? user['full_name'] : ''} '
                    '${from is Map ? from['name'] : ''} '
                    '${to is Map ? to['name'] : ''} '
                    '${row['notes'] ?? ''}'
                .toLowerCase();

            final area = product is Map
                ? product['inventory_area']?.toString() ?? ''
                : '';

            return (query.isEmpty || text.contains(query)) &&
                (_kind == 'all' || row['kind'] == _kind) &&
                (_area == 'all' || area == _area);
          }).toList();

          final inQty = rows
              .where((row) =>
                  row['kind'] != 'transfer' && _num(row['quantity']) > 0)
              .fold<double>(
                0,
                (value, row) => value + _num(row['quantity']),
              );

          final outQty = rows
              .where((row) =>
                  row['kind'] != 'transfer' && _num(row['quantity']) < 0)
              .fold<double>(
                0,
                (value, row) => value + _num(row['quantity']).abs(),
              );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Movimentos de Inventário',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Histórico unificado de entradas, vendas, transferências, consumos, perdas, devoluções e ajustes.',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _metric(
                      context,
                      'Movimentos',
                      '${rows.length}',
                      Icons.swap_horiz,
                    ),
                    _metric(
                      context,
                      'Entradas',
                      _qty(inQty),
                      Icons.south_west,
                    ),
                    _metric(
                      context,
                      'Saídas',
                      _qty(outQty),
                      Icons.north_east,
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
                          labelText: 'Pesquisar',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                        initialValue: _kind,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: const {
                          'all': 'Todos',
                          'purchase': 'Compra',
                          'sale': 'Venda',
                          'adjustment': 'Ajuste',
                          'loss': 'Perda',
                          'transfer': 'Transferência',
                          'event_consumption': 'Consumo evento',
                          'return': 'Devolução',
                        }
                            .entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _kind = value ?? 'all'),
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
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Todas'),
                          ),
                          DropdownMenuItem(
                            value: 'shop',
                            child: Text('Loja'),
                          ),
                          DropdownMenuItem(
                            value: 'bar',
                            child: Text('Bar'),
                          ),
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
                      title: Text(
                        'Sem movimentos para os filtros selecionados.',
                      ),
                    ),
                  )
                else
                  for (final row in rows) _movementCard(row),
              ],
            ),
          );
        },
      );

  Widget _movementCard(Map<String, dynamic> row) {
    final product = row['products'];
    final variant = row['product_variants'];
    final event = row['events'];
    final user = row['profiles'];
    final from = row['from_location'];
    final to = row['to_location'];
    final quantity = _num(row['quantity']);

    final name =
        product is Map ? product['name']?.toString() ?? 'Artigo' : 'Artigo';
    final variantText =
        variant is Map ? ' · ${variant['name']?.toString() ?? ''}' : '';

    final locationText = from is Map && to is Map
        ? '${from['name']} → ${to['name']}'
        : from is Map
            ? 'Saída: ${from['name']}'
            : to is Map
                ? 'Entrada: ${to['name']}'
                : null;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            row['kind'] == 'transfer'
                ? Icons.swap_horiz
                : quantity >= 0
                    ? Icons.add
                    : Icons.remove,
          ),
        ),
        title: Text('$name$variantText'),
        subtitle: Text(
          [
            _kindLabel(row['kind']?.toString()),
            if (locationText != null) locationText,
            if (event is Map) 'Evento: ${event['name']}',
            if (user is Map) 'Utilizador: ${user['full_name']}',
            if ((row['notes']?.toString() ?? '').isNotEmpty)
              row['notes'].toString(),
            _dateTime(row['created_at']),
          ].join(' · '),
        ),
        trailing: Text(
          row['kind'] == 'transfer'
              ? _qty(quantity.abs())
              : '${quantity > 0 ? '+' : ''}${_qty(quantity)}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
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

String _qty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceAll('.', ',');

String _dateTime(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? '—'
      : DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
}

String _kindLabel(String? value) => switch (value) {
      'purchase' => 'Compra',
      'sale' => 'Venda',
      'adjustment' => 'Ajuste',
      'loss' => 'Perda',
      'transfer' => 'Transferência',
      'event_consumption' => 'Consumo evento',
      'return' => 'Devolução',
      _ => 'Movimento',
    };
