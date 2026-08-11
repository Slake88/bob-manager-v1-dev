import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/shop_repository.dart';
import '../widgets/product_image_gallery.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _repository = ShopRepository();
  late Future<_ShopData> _future;

  bool get _canManage =>
      AppSession.instance.can(AppPermission.manageMerchandising);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.products(),
      _repository.orders(),
      _repository.members(),
    ]).then(
      (values) => _ShopData(
        products: List<Map<String, dynamic>>.from(values[0]),
        orders: List<Map<String, dynamic>>.from(values[1]),
        members: List<Map<String, dynamic>>.from(values[2]),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _newProduct() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(repository: _repository),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ShopData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: const TabBar(
              tabs: [
                Tab(text: 'Artigos', icon: Icon(Icons.storefront_outlined)),
                Tab(
                  text: 'Encomendas',
                  icon: Icon(Icons.shopping_bag_outlined),
                ),
              ],
            ),
            body: TabBarView(
              children: [
                _ProductsTab(
                  products: data.products,
                  members: data.members,
                  repository: _repository,
                  onChanged: _refresh,
                ),
                _OrdersTab(
                  orders: data.orders,
                  repository: _repository,
                  onChanged: _refresh,
                ),
              ],
            ),
            floatingActionButton: _canManage
                ? FloatingActionButton.extended(
                    onPressed: _newProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo artigo'),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({
    required this.products,
    required this.members,
    required this.repository,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> members;
  final ShopRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final allVariants = products.expand(_variants).toList();
    final low = allVariants
        .where((v) => _available(v) <= _double(v['minimum_stock']))
        .length;
    final empty = allVariants.where((v) => _available(v) <= 0).length;

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric('Artigos', products.length.toString(), Icons.inventory_2_outlined),
              _Metric('Variantes', allVariants.length.toString(), Icons.style_outlined),
              _Metric('Stock baixo', low.toString(), Icons.warning_amber_outlined),
              _Metric('Sem stock', empty.toString(), Icons.remove_shopping_cart_outlined),
            ],
          ),
          const SizedBox(height: 16),
          if (products.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.storefront_outlined),
                title: Text('Ainda não existem artigos na Loja.'),
                subtitle: Text(
                  'Cria um artigo e adiciona depois tamanhos/variantes.',
                ),
              ),
            )
          else
            for (final product in products)
              _ProductCard(
                product: product,
                members: members,
                repository: repository,
                onChanged: onChanged,
              ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.members,
    required this.repository,
    required this.onChanged,
  });

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> members;
  final ShopRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final variants = _variants(product);
    final imageUrl = repository.publicImageUrl(product['photo_path']);
    final available = variants.isEmpty
        ? _double(product['current_stock']) - _double(product['reserved_stock'])
        : variants.fold<double>(0, (sum, row) => sum + _available(row));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(
                repository: repository,
                product: product,
                members: members,
              ),
            ),
          );
          await onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: imageUrl == null
                      ? const ColoredBox(
                          color: Color(0xFFECEFF1),
                          child: Icon(Icons.image_outlined, size: 36),
                        )
                      : Image.network(imageUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product['name']?.toString() ?? 'Artigo',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (product['institutional_delivery'] == true)
                          const Tooltip(
                            message: 'Entrega institucional',
                            child: Icon(Icons.workspace_premium_outlined),
                          ),
                      ],
                    ),
                    Text(product['category']?.toString() ?? 'Merchandising'),
                    const SizedBox(height: 6),
                    if (variants.isEmpty)
                      Text(
                        'Disponível: ${_number(available)} · ${_money(product['sale_price'])}',
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: variants.take(8).map((variant) {
                          final stock = _available(variant);
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              stock > 0
                                  ? Icons.check_circle_outline
                                  : Icons.schedule_outlined,
                              size: 17,
                            ),
                            label: Text(
                              '${variant['name']} · ${_number(stock)}',
                            ),
                          );
                        }).toList(),
                      ),
                    if (variants.length > 8)
                      Text('+ ${variants.length - 8} variantes'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.repository,
    required this.product,
    required this.members,
  });

  final ShopRepository repository;
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> members;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Map<String, dynamic> _product;

  bool get _canManage =>
      AppSession.instance.can(AppPermission.manageMerchandising);

  @override
  void initState() {
    super.initState();
    _product = Map<String, dynamic>.from(widget.product);
  }

  Future<void> _reloadProduct() async {
    final rows = await widget.repository.products();
    Map<String, dynamic>? updated;
    for (final row in rows) {
      if (row['id'] == _product['id']) {
        updated = row;
        break;
      }
    }
    if (updated != null && mounted) setState(() => _product = updated!);
  }

  Future<void> _editVariant([Map<String, dynamic>? variant]) async {
    final result = await showDialog<_VariantInput>(
      context: context,
      builder: (_) => _VariantDialog(product: _product, variant: variant),
    );
    if (result == null) return;
    try {
      await widget.repository.saveVariant(
        id: variant?['id']?.toString(),
        productId: _product['id'].toString(),
        name: result.name,
        sku: result.sku,
        currentStock: result.stock,
        minimumStock: result.minimum,
        cost: result.cost,
        salePrice: result.price,
      );
      await _reloadProduct();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _order(Map<String, dynamic>? variant) async {
    final result = await showDialog<_OrderInput>(
      context: context,
      builder: (_) => _OrderDialog(
        product: _product,
        variant: variant,
        members: widget.members,
      ),
    );
    if (result == null) return;
    try {
      final orderId = await widget.repository.createOrder(
        productId: _product['id'].toString(),
        variantId: variant?['id']?.toString(),
        quantity: result.quantity,
        unitPrice: result.unitPrice,
        memberId: result.memberId,
        externalName: result.externalName,
        externalContact: result.externalContact,
        notes: result.notes,
      );
      if (result.payNow > 0) {
        await widget.repository.payOrder(
          orderId: orderId,
          amount: result.payNow,
          paymentMethod: result.paymentMethod,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encomenda registada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reserve(Map<String, dynamic> variant) async {
    final controller = TextEditingController(text: '1');
    final quantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reservar ${variant['name']}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantidade',
            helperText: 'Disponível: ${_number(_available(variant))}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Reservar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (quantity == null) return;
    try {
      await widget.repository.reserveVariant(
        productId: _product['id'].toString(),
        variantId: variant['id'].toString(),
        quantity: quantity,
      );
      await _reloadProduct();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final variants = _variants(_product);

    return Scaffold(
      appBar: AppBar(
        title: Text(_product['name']?.toString() ?? 'Artigo'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Editar artigo',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ProductEditorScreen(
                      repository: widget.repository,
                      product: _product,
                    ),
                  ),
                );
                if (changed == true) await _reloadProduct();
              },
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          ProductImageGallery(
            repository: widget.repository,
            productId: _product['id'].toString(),
            coverPath: _product['photo_path']?.toString(),
            canManage: _canManage,
            onChanged: _reloadProduct,
          ),
          const SizedBox(height: 12),
          Text(_product['description']?.toString() ?? 'Sem descrição.'),
          if ((_product['supplier']?.toString() ?? '').isNotEmpty)
            Text('Fornecedor: ${_product['supplier']}'),
          if (_product['institutional_delivery'] == true)
            const Card(
              child: ListTile(
                leading: Icon(Icons.workspace_premium_outlined),
                title: Text('Artigo de entrega institucional'),
                subtitle: Text(
                  'Preparado para atribuição automática a membros, sem venda.',
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Variantes / tamanhos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (_canManage)
                FilledButton.tonalIcon(
                  onPressed: _editVariant,
                  icon: const Icon(Icons.add),
                  label: const Text('Variante'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (variants.isEmpty)
            Card(
              child: ListTile(
                title: const Text('Sem variantes'),
                subtitle: const Text(
                  'Adiciona tamanhos como S, M, L, XL ou outras versões deste artigo.',
                ),
                trailing: _canManage
                    ? TextButton(
                        onPressed: _editVariant,
                        child: const Text('Adicionar'),
                      )
                    : null,
              ),
            )
          else
            for (final variant in variants)
              Card(
                child: ListTile(
                  title: Text(variant['name']?.toString() ?? 'Variante'),
                  subtitle: Text(
                    'Stock: ${_number(variant['current_stock'])} · '
                    'Reservado: ${_number(variant['reserved_stock'])} · '
                    'Disponível: ${_number(_available(variant))}\n'
                    'Preço: ${_money(variant['sale_price'] ?? _product['sale_price'])}',
                  ),
                  isThreeLine: true,
                  onTap: _canManage ? () => _editVariant(variant) : null,
                  trailing: _canManage
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'reserve') _reserve(variant);
                            if (value == 'order') _order(variant);
                          },
                          itemBuilder: (_) => [
                            if (_available(variant) > 0)
                              const PopupMenuItem(
                                value: 'reserve',
                                child: Text('Reservar stock'),
                              ),
                            const PopupMenuItem(
                              value: 'order',
                              child: Text('Encomendar para cliente'),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
          const SizedBox(height: 12),
          if (_canManage && variants.isEmpty)
            FilledButton.icon(
              onPressed: () => _order(null),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Registar encomenda'),
            ),
        ],
      ),
    );
  }
}

class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({
    super.key,
    required this.repository,
    this.product,
  });

  final ShopRepository repository;
  final Map<String, dynamic>? product;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _supplier;
  late final TextEditingController _cost;
  late final TextEditingController _price;
  late final TextEditingController _minimum;
  bool _institutional = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?['name']?.toString() ?? '');
    _sku = TextEditingController(text: product?['sku']?.toString() ?? '');
    _category = TextEditingController(
      text: product?['category']?.toString() ?? 'Merchandising',
    );
    _description = TextEditingController(
      text: product?['description']?.toString() ?? '',
    );
    _supplier = TextEditingController(
      text: product?['supplier']?.toString() ?? '',
    );
    _cost = TextEditingController(
      text: _double(product?['cost']).toStringAsFixed(2),
    );
    _price = TextEditingController(
      text: _double(product?['sale_price']).toStringAsFixed(2),
    );
    _minimum = TextEditingController(
      text: _double(product?['minimum_stock']).toStringAsFixed(0),
    );
    _institutional = product?['institutional_delivery'] == true;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sku,
      _category,
      _description,
      _supplier,
      _cost,
      _price,
      _minimum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.saveProduct(
        id: widget.product?['id']?.toString(),
        name: _name.text,
        sku: _sku.text,
        category: _category.text,
        description: _description.text,
        supplier: _supplier.text,
        cost: _parse(_cost.text),
        salePrice: _parse(_price.text),
        minimumStock: _parse(_minimum.text),
        institutionalDelivery: _institutional,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'Novo artigo' : 'Editar artigo'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nome / design *'),
          ),
          TextField(
            controller: _sku,
            decoration: const InputDecoration(labelText: 'Código / SKU'),
          ),
          TextField(
            controller: _category,
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Descrição'),
          ),
          TextField(
            controller: _supplier,
            decoration: const InputDecoration(labelText: 'Fornecedor'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _cost,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Custo base'),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço base'),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _minimum,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Stock mínimo base'),
                ),
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Entrega institucional'),
            subtitle: const Text(
              'Ex.: Patch de costas entregue ao passar a Full Color; não é uma venda.',
            ),
            value: _institutional,
            onChanged: (value) => setState(() => _institutional = value),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar artigo'),
          ),
        ],
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({
    required this.orders,
    required this.repository,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> orders;
  final ShopRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final outstanding = orders.fold<double>(
      0,
      (sum, order) =>
          sum + _double(order['total_amount']) - _double(order['paid_amount']),
    );

    return RefreshIndicator(
      onRefresh: onChanged,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(
                'Pendentes',
                orders
                    .where((order) => order['status'] != 'delivered')
                    .length
                    .toString(),
                Icons.pending_actions_outlined,
              ),
              _Metric('Por receber', _money(outstanding), Icons.payments_outlined),
            ],
          ),
          const SizedBox(height: 14),
          if (orders.isEmpty)
            const Card(
              child: ListTile(
                title: Text('Não existem encomendas pendentes.'),
              ),
            )
          else
            for (final order in orders)
              _OrderCard(
                order: order,
                repository: repository,
                onChanged: onChanged,
              ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.repository,
    required this.onChanged,
  });

  final Map<String, dynamic> order;
  final ShopRepository repository;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final member = order['members'];
    final client = member is Map
        ? member['full_name']?.toString()
        : order['external_name']?.toString();
    final items = List<Map<String, dynamic>>.from(
      order['shop_order_items'] as List? ?? const [],
    );
    final total = _double(order['total_amount']);
    final paid = _double(order['paid_amount']);
    final remaining = total - paid;
    var itemLabel = 'Encomenda';

    if (items.isNotEmpty) {
      final item = items.first;
      final product = item['products'];
      final variant = item['product_variants'];
      final productName = product is Map ? product['name'] : 'Artigo';
      final variantName = variant is Map ? ' — ${variant['name']}' : '';
      itemLabel = '$productName$variantName × ${_number(item['quantity'])}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    client ?? 'Cliente',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _StatusChip(order['status']?.toString() ?? 'pending'),
              ],
            ),
            Text(itemLabel),
            Text(
              'Total: ${_money(total)} · Pago: ${_money(paid)} · '
              'Falta: ${_money(remaining)}',
            ),
            if ((order['notes']?.toString() ?? '').isNotEmpty)
              Text('Nota: ${order['notes']}'),
            Text(
              DateFormat('dd/MM/yyyy HH:mm').format(
                DateTime.parse(order['created_at'].toString()).toLocal(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (remaining > 0)
                  FilledButton.tonalIcon(
                    onPressed: () => _receive(context, remaining),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text('Receber ${_money(remaining)}'),
                  ),
                PopupMenuButton<String>(
                  onSelected: (status) async {
                    await repository.updateOrderStatus(
                      order['id'].toString(),
                      status,
                    );
                    await onChanged();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pending', child: Text('Pendente')),
                    PopupMenuItem(
                      value: 'ordered',
                      child: Text('Encomendado ao fornecedor'),
                    ),
                    PopupMenuItem(value: 'received', child: Text('Recebido')),
                    PopupMenuItem(
                      value: 'delivered',
                      child: Text('Entregue ao cliente'),
                    ),
                    PopupMenuItem(value: 'cancelled', child: Text('Cancelar')),
                  ],
                  child: const Chip(label: Text('Alterar estado')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _receive(BuildContext context, double remaining) async {
    final amount = TextEditingController(text: remaining.toStringAsFixed(2));
    var method = 'Dinheiro';
    final result = await showDialog<(double, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Receber pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor'),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Método'),
                items: const [
                  'Dinheiro',
                  'MB Way',
                  'Transferência bancária',
                ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => method = value ?? method),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (_parse(amount.text), method),
              ),
              child: const Text('Receber'),
            ),
          ],
        ),
      ),
    );
    amount.dispose();
    if (result == null || result.$1 <= 0) return;
    try {
      await repository.payOrder(
        orderId: order['id'].toString(),
        amount: result.$1,
        paymentMethod: result.$2,
      );
      await onChanged();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _VariantDialog extends StatefulWidget {
  const _VariantDialog({required this.product, this.variant});

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  @override
  State<_VariantDialog> createState() => _VariantDialogState();
}

class _VariantDialogState extends State<_VariantDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _stock;
  late final TextEditingController _minimum;
  late final TextEditingController _cost;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    final variant = widget.variant;
    _name = TextEditingController(text: variant?['name']?.toString() ?? '');
    _sku = TextEditingController(text: variant?['sku']?.toString() ?? '');
    _stock = TextEditingController(
      text: _double(variant?['current_stock']).toStringAsFixed(0),
    );
    _minimum = TextEditingController(
      text: _double(variant?['minimum_stock']).toStringAsFixed(0),
    );
    _cost = TextEditingController(
      text: _double(variant?['cost'] ?? widget.product['cost'])
          .toStringAsFixed(2),
    );
    _price = TextEditingController(
      text: _double(variant?['sale_price'] ?? widget.product['sale_price'])
          .toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sku,
      _stock,
      _minimum,
      _cost,
      _price,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.variant == null
            ? 'Nova variante / tamanho'
            : 'Editar variante',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Tamanho / variante *',
              ),
            ),
            TextField(
              controller: _sku,
              decoration: const InputDecoration(labelText: 'SKU da variante'),
            ),
            TextField(
              controller: _stock,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock atual'),
            ),
            TextField(
              controller: _minimum,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Stock mínimo'),
            ),
            TextField(
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Custo unitário'),
            ),
            TextField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Preço de venda'),
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
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _VariantInput(
                _name.text,
                _sku.text,
                _parse(_stock.text),
                _parse(_minimum.text),
                _parse(_cost.text),
                _parse(_price.text),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _OrderDialog extends StatefulWidget {
  const _OrderDialog({
    required this.product,
    required this.variant,
    required this.members,
  });

  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;
  final List<Map<String, dynamic>> members;

  @override
  State<_OrderDialog> createState() => _OrderDialogState();
}

class _OrderDialogState extends State<_OrderDialog> {
  String? _memberId;
  bool _external = false;
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _price;
  final _payNow = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _method = 'Dinheiro';

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: _double(
        widget.variant?['sale_price'] ?? widget.product['sale_price'],
      ).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _contact,
      _quantity,
      _price,
      _payNow,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _parse(_quantity.text) * _parse(_price.text);
    final variantName = widget.variant == null ? '' : ' / ${widget.variant!['name']}';

    return AlertDialog(
      title: Text('Encomendar — ${widget.product['name']}$variantName'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Membro'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Externo'),
                    icon: Icon(Icons.person_add_alt_outlined),
                  ),
                ],
                selected: {_external},
                onSelectionChanged: (values) =>
                    setState(() => _external = values.first),
              ),
              if (!_external)
                DropdownButtonFormField<String>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(labelText: 'Membro'),
                  items: widget.members
                      .map(
                        (member) => DropdownMenuItem(
                          value: member['id'].toString(),
                          child: Text(
                            member['full_name']?.toString() ?? 'Membro',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _memberId = value),
                )
              else ...[
                TextField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Nome do cliente *'),
                ),
                TextField(
                  controller: _contact,
                  decoration: const InputDecoration(
                    labelText: 'Contacto (opcional)',
                  ),
                ),
              ],
              TextField(
                controller: _quantity,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantidade'),
              ),
              TextField(
                controller: _price,
                onChanged: (_) => setState(() {}),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Preço unitário'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Total: ${_money(total)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextField(
                controller: _payNow,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Pagar agora (0 = não pago)',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration:
                    const InputDecoration(labelText: 'Método do pagamento'),
                items: const [
                  'Dinheiro',
                  'MB Way',
                  'Transferência bancária',
                ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _method = value ?? _method),
              ),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota / próxima encomenda',
                ),
              ),
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
          onPressed: () {
            final quantity = _parse(_quantity.text);
            final unitPrice = _parse(_price.text);
            final payment = _parse(_payNow.text);
            final orderTotal = quantity * unitPrice;
            if (quantity <= 0 ||
                unitPrice < 0 ||
                payment < 0 ||
                payment > orderTotal) {
              return;
            }
            if ((!_external && _memberId == null) ||
                (_external && _name.text.trim().isEmpty)) {
              return;
            }
            Navigator.pop(
              context,
              _OrderInput(
                memberId: _external ? null : _memberId,
                externalName: _external ? _name.text.trim() : '',
                externalContact: _external ? _contact.text.trim() : '',
                quantity: quantity,
                unitPrice: unitPrice,
                payNow: payment,
                paymentMethod: _method,
                notes: _notes.text.trim(),
              ),
            );
          },
          child: const Text('Registar encomenda'),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'ordered' => 'Encomendado',
      'received' => 'Recebido',
      'delivered' => 'Entregue',
      'cancelled' => 'Cancelado',
      _ => 'Pendente',
    };
    return Chip(label: Text(label));
  }
}

class _ShopData {
  const _ShopData({
    required this.products,
    required this.orders,
    required this.members,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> members;
}

class _VariantInput {
  const _VariantInput(
    this.name,
    this.sku,
    this.stock,
    this.minimum,
    this.cost,
    this.price,
  );

  final String name;
  final String sku;
  final double stock;
  final double minimum;
  final double cost;
  final double price;
}

class _OrderInput {
  const _OrderInput({
    required this.memberId,
    required this.externalName,
    required this.externalContact,
    required this.quantity,
    required this.unitPrice,
    required this.payNow,
    required this.paymentMethod,
    required this.notes,
  });

  final String? memberId;
  final String externalName;
  final String externalContact;
  final double quantity;
  final double unitPrice;
  final double payNow;
  final String paymentMethod;
  final String notes;
}

List<Map<String, dynamic>> _variants(Map<String, dynamic> product) {
  final raw = product['product_variants'];
  if (raw is! List) return const [];
  final rows = List<Map<String, dynamic>>.from(raw);
  rows.sort(
    (a, b) =>
        (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''),
  );
  return rows.where((row) => row['active'] != false).toList();
}

double _available(Map<String, dynamic> variant) =>
    _double(variant['current_stock']) - _double(variant['reserved_stock']);

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

double _parse(String value) =>
    double.tryParse(value.replaceAll(',', '.')) ?? 0;

String _number(Object? value) {
  final number = _double(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2).replaceAll('.', ',');
}

String _money(Object? value) =>
    NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(_double(value));
