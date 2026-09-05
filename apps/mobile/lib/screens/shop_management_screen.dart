import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/shop_repository.dart';

class ShopManagementScreen extends StatefulWidget {
  const ShopManagementScreen({super.key});

  @override
  State<ShopManagementScreen> createState() => _ShopManagementScreenState();
}

class _ShopManagementScreenState extends State<ShopManagementScreen> {
  final _repository = ShopRepository();
  late Future<_ManagementData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.products(),
      _repository.orders(),
    ]).then(
      (values) => _ManagementData(
        products: List<Map<String, dynamic>>.from(values[0]),
        orders: List<Map<String, dynamic>>.from(values[1]),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSession.instance.can(AppPermission.manageMerchandising)) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Gestão da Loja'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sem permissão para gerir a Loja e o merchandising.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gestão da Loja'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Públicos e preços', icon: Icon(Icons.groups_outlined)),
              Tab(
                  text: 'A encomendar',
                  icon: Icon(Icons.shopping_cart_checkout_outlined)),
            ],
          ),
        ),
        body: FutureBuilder<_ManagementData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Erro: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return TabBarView(
              children: [
                _AudienceTab(
                  products: data.products,
                  repository: _repository,
                  onChanged: _refresh,
                ),
                _NeedsTab(orders: data.orders),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AudienceTab extends StatelessWidget {
  const _AudienceTab({
    required this.products,
    required this.repository,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> products;
  final ShopRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Quem pode comprar?'),
              subtitle: Text(
                'Cada artigo pode ser público, exclusivo para Prospects/Full Colors ou ter preços diferentes por público.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (products.isEmpty)
            const Card(child: ListTile(title: Text('Sem artigos.')))
          else
            for (final product in products)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.sell_outlined)),
                  title: Text(product['name']?.toString() ?? 'Artigo'),
                  subtitle:
                      Text(product['category']?.toString() ?? 'Merchandising'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _configure(context, product),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _configure(
    BuildContext context,
    Map<String, dynamic> product,
  ) async {
    final current = await repository.audience(product['id'].toString());
    if (!context.mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AudienceDialog(
        product: product,
        initial: current,
        repository: repository,
      ),
    );
    if (changed == true) await onChanged();
  }
}

class _AudienceDialog extends StatefulWidget {
  const _AudienceDialog({
    required this.product,
    required this.initial,
    required this.repository,
  });

  final Map<String, dynamic> product;
  final Map<String, dynamic> initial;
  final ShopRepository repository;

  @override
  State<_AudienceDialog> createState() => _AudienceDialogState();
}

class _AudienceDialogState extends State<_AudienceDialog> {
  late Map<String, bool> _visibility;
  late Map<String, TextEditingController> _prices;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final visible = Map<String, bool>.from(
      widget.initial['visibility'] as Map? ?? const {},
    );
    final priceValues = Map<String, double>.from(
      widget.initial['prices'] as Map? ?? const {},
    );
    _visibility = {
      'public': visible['public'] ?? true,
      'prospect': visible['prospect'] ?? true,
      'full_color': visible['full_color'] ?? true,
    };
    final base = _double(widget.product['sale_price']);
    _prices = {
      for (final key in const ['public', 'prospect', 'full_color'])
        key: TextEditingController(
          text: (priceValues[key] ?? base).toStringAsFixed(2),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _prices.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveAudience(
        productId: widget.product['id'].toString(),
        visibility: _visibility,
        prices: {
          for (final entry in _prices.entries)
            entry.key: _parse(entry.value.text),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product['name']?.toString() ?? 'Artigo'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _audienceRow('public', 'Público'),
              _audienceRow('prospect', 'Prospect'),
              _audienceRow('full_color', 'Full Color'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _audienceRow(String key, String label) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: _visibility[key] ?? false,
              onChanged: (value) => setState(() => _visibility[key] = value),
            ),
            TextField(
              controller: _prices[key],
              enabled: _visibility[key] == true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeedsTab extends StatelessWidget {
  const _NeedsTab({required this.orders});

  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final needs = <String, _Need>{};
    for (final order in orders) {
      final status = order['status']?.toString();
      if (status == 'delivered' || status == 'cancelled') continue;
      final items = List<Map<String, dynamic>>.from(
        order['shop_order_items'] as List? ?? const [],
      );
      for (final item in items) {
        final product = item['products'];
        final variant = item['product_variants'];
        final productName =
            product is Map ? product['name']?.toString() ?? 'Artigo' : 'Artigo';
        final variantName =
            variant is Map ? variant['name']?.toString() ?? '' : '';
        final key = '$productName|$variantName';
        final quantity = _double(item['quantity']);
        final current = needs[key];
        needs[key] = _Need(
          product: productName,
          variant: variantName,
          quantity: (current?.quantity ?? 0) + quantity,
        );
      }
    }
    final rows = needs.values.toList()
      ..sort((a, b) {
        final product = a.product.compareTo(b.product);
        return product != 0 ? product : a.variant.compareTo(b.variant);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.shopping_cart_checkout_outlined),
            title: Text('Necessidades para a próxima encomenda'),
            subtitle: Text(
              'Agrupa automaticamente as encomendas ainda não entregues por artigo e tamanho/variante.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline),
              title: Text('Não existem artigos pendentes para encomendar.'),
            ),
          )
        else
          for (final need in rows)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(_number(need.quantity)),
                ),
                title: Text(need.product),
                subtitle: Text(
                  need.variant.isEmpty ? 'Sem variante' : need.variant,
                ),
                trailing: Text(
                  '× ${_number(need.quantity)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
      ],
    );
  }
}

class _ManagementData {
  const _ManagementData({required this.products, required this.orders});
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> orders;
}

class _Need {
  const _Need({
    required this.product,
    required this.variant,
    required this.quantity,
  });
  final String product;
  final String variant;
  final double quantity;
}

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

double _parse(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;

String _number(Object? value) {
  final number = _double(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2).replaceAll('.', ',');
}
