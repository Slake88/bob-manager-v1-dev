import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/inventory_repository.dart';
import 'entity_form_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final InventoryRepository _repository = InventoryRepository();
  late Future<Map<String, dynamic>> _future;

  AppRole get _role => AppRole.fromValue(AppSession.instance.role);
  bool get _canManage =>
      PermissionPolicy.allows(_role, AppPermission.manageInventory);
  bool get _canSell =>
      PermissionPolicy.allows(_role, AppPermission.sellInventory);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.summary();

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _editProduct([Map<String, dynamic>? product]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: inventoryDefinition,
          initialValues: product,
          onSave: (values, id) async {
            await _repository.saveProduct(values, productId: id);
          },
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _adjust(Map<String, dynamic> product) async {
    final result = await showDialog<_StockActionResult>(
      context: context,
      builder: (_) => _StockActionDialog(
        title: 'Ajustar stock — ${product['name']}',
        quantityLabel: 'Quantidade (+ entrada / - saída)',
        actionLabel: 'Aplicar ajuste',
      ),
    );
    if (result == null) return;
    try {
      await _repository.adjustStock(
        productId: product['id'].toString(),
        quantity: result.quantity,
        reason: result.description,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _reserve(Map<String, dynamic> product) async {
    final result = await showDialog<_StockActionResult>(
      context: context,
      builder: (_) => _StockActionDialog(
        title: 'Reservar — ${product['name']}',
        quantityLabel: 'Quantidade a reservar',
        actionLabel: 'Reservar',
      ),
    );
    if (result == null) return;
    try {
      await _repository.reserveStock(
        productId: product['id'].toString(),
        quantity: result.quantity,
        description: result.description,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _sale(Map<String, dynamic> product) async {
    final result = await showDialog<_SaleResult>(
      context: context,
      builder: (_) => _SaleDialog(product: product),
    );
    if (result == null) return;
    try {
      await _repository.recordSale(
        productId: product['id'].toString(),
        quantity: result.quantity,
        unitPrice: result.unitPrice,
        paymentMethod: result.paymentMethod,
        description: result.description,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final products = List<Map<String, dynamic>>.from(
            data['products'] as List<dynamic>? ?? const [],
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: 'Artigos',
                      value: '${data['product_count'] ?? 0}',
                      icon: Icons.inventory_2_outlined,
                    ),
                    _MetricCard(
                      label: 'Unidades disponíveis',
                      value: _number(data['available_units']),
                      icon: Icons.layers_outlined,
                    ),
                    _MetricCard(
                      label: 'Valor de custo',
                      value: '${_money(data['stock_value'])} €',
                      icon: Icons.euro_outlined,
                    ),
                    _MetricCard(
                      label: 'Stock baixo',
                      value: '${data['low_stock'] ?? 0}',
                      icon: Icons.warning_amber_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Inventário e Merchandising',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (products.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.inventory_2_outlined),
                      title: Text('Sem artigos registados.'),
                    ),
                  )
                else
                  ...products.map((product) {
                    final current = _asDouble(product['current_stock']);
                    final reserved = _asDouble(product['reserved_stock']);
                    final minimum = _asDouble(product['minimum_stock']);
                    final available = current - reserved;
                    final low = current <= minimum;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(low
                              ? Icons.warning_amber_outlined
                              : Icons.inventory_2_outlined),
                        ),
                        title: Text(product['name']?.toString() ?? 'Artigo'),
                        subtitle: Text(
                          '${product['variant'] ?? product['category'] ?? ''}\n'
                          'Disponível: ${_number(available)} • Reservado: ${_number(reserved)} • Preço: ${_money(product['sale_price'])} €',
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'sale') _sale(product);
                            if (action == 'reserve') _reserve(product);
                            if (action == 'adjust') _adjust(product);
                            if (action == 'edit') _editProduct(product);
                          },
                          itemBuilder: (_) => [
                            if (_canSell)
                              const PopupMenuItem(
                                value: 'sale',
                                child: Text('Registar venda'),
                              ),
                            if (_canManage)
                              const PopupMenuItem(
                                value: 'reserve',
                                child: Text('Reservar stock'),
                              ),
                            if (_canManage)
                              const PopupMenuItem(
                                value: 'adjust',
                                child: Text('Ajustar stock'),
                              ),
                            if (_canManage)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Editar artigo'),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _editProduct,
              icon: const Icon(Icons.add),
              label: const Text('Novo artigo'),
            )
          : null,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label),
                    Text(value,
                        style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StockActionResult {
  const _StockActionResult(this.quantity, this.description);
  final double quantity;
  final String description;
}

class _StockActionDialog extends StatefulWidget {
  const _StockActionDialog({
    required this.title,
    required this.quantityLabel,
    required this.actionLabel,
  });

  final String title;
  final String quantityLabel;
  final String actionLabel;

  @override
  State<_StockActionDialog> createState() => _StockActionDialogState();
}

class _StockActionDialogState extends State<_StockActionDialog> {
  final _quantity = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _quantity.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantity,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: widget.quantityLabel),
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Descrição/motivo'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final quantity =
                double.tryParse(_quantity.text.replaceAll(',', '.'));
            if (quantity == null) return;
            Navigator.pop(
              context,
              _StockActionResult(quantity, _description.text.trim()),
            );
          },
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _SaleResult {
  const _SaleResult({
    required this.quantity,
    required this.unitPrice,
    required this.paymentMethod,
    required this.description,
  });

  final double quantity;
  final double unitPrice;
  final String paymentMethod;
  final String description;
}

class _SaleDialog extends StatefulWidget {
  const _SaleDialog({required this.product});
  final Map<String, dynamic> product;

  @override
  State<_SaleDialog> createState() => _SaleDialogState();
}

class _SaleDialogState extends State<_SaleDialog> {
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _price;
  final _description = TextEditingController();
  String _paymentMethod = 'Dinheiro';

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: _asDouble(widget.product['sale_price']).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Venda — ${widget.product['name']}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantidade'),
          ),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Preço unitário'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(labelText: 'Pagamento'),
            items: const ['Dinheiro', 'MB Way', 'Transferência bancária']
                .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _paymentMethod = value);
            },
          ),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Descrição'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final quantity =
                double.tryParse(_quantity.text.replaceAll(',', '.'));
            final price = double.tryParse(_price.text.replaceAll(',', '.'));
            if (quantity == null || price == null) return;
            Navigator.pop(
              context,
              _SaleResult(
                quantity: quantity,
                unitPrice: price,
                paymentMethod: _paymentMethod,
                description: _description.text.trim(),
              ),
            );
          },
          child: const Text('Registar venda'),
        ),
      ],
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _money(Object? value) => _asDouble(value).toStringAsFixed(2);
String _number(Object? value) {
  final number = _asDouble(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2);
}
