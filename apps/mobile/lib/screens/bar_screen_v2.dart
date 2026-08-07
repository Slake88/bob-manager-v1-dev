import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/bar_repository.dart';

class BarScreenV2 extends StatefulWidget {
  const BarScreenV2({super.key});

  @override
  State<BarScreenV2> createState() => _BarScreenV2State();
}

class _BarScreenV2State extends State<BarScreenV2> {
  final BarRepository _repository = BarRepository();
  late Future<_BarData> _future;

  bool get _canManage => AppSession.instance.can(AppPermission.manageBar);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.products(),
      _repository.events(),
      _repository.operations(),
    ]).then((values) => _BarData(
          products: List<Map<String, dynamic>>.from(values[0]),
          events: List<Map<String, dynamic>>.from(values[1]),
          operations: List<Map<String, dynamic>>.from(values[2]),
        ));
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  Future<void> _editProduct([Map<String, dynamic>? product]) async {
    final result = await showDialog<_BarProductInput>(
      context: context,
      builder: (_) => _BarProductDialog(product: product),
    );
    if (result == null) return;
    try {
      await _repository.saveProduct(
        id: product?['id']?.toString(),
        name: result.name,
        sku: result.sku,
        category: result.category,
        description: result.description,
        supplier: result.supplier,
        purchaseUnit: result.purchaseUnit,
        consumptionUnit: result.consumptionUnit,
        unitsPerPurchase: result.unitsPerPurchase,
        purchaseCost: result.purchaseCost,
        salePrice: result.salePrice,
        minimumStock: result.minimumStock,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _operation(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> events,
    String operation,
  ) async {
    if (operation == 'purchase') {
      final result = await showDialog<_PurchaseInput>(
        context: context,
        builder: (_) => _PurchaseDialog(product: product, events: events),
      );
      if (result == null) return;
      try {
        await _repository.purchase(
          product: product,
          purchaseUnits: result.purchaseUnits,
          costPerPurchaseUnit: result.costPerPurchaseUnit,
          eventId: result.eventId,
          paymentMethod: result.paymentMethod,
          notes: result.notes,
          postFinancial: result.postFinancial,
        );
        if (mounted) setState(_reload);
      } catch (error) {
        _error(error);
      }
      return;
    }

    final result = await showDialog<_ConsumptionInput>(
      context: context,
      builder: (_) => _ConsumptionDialog(
        product: product,
        events: events,
        operation: operation,
      ),
    );
    if (result == null) return;
    try {
      await _repository.consume(
        productId: product['id'].toString(),
        operation: operation,
        quantity: result.quantity,
        eventId: result.eventId,
        unitPrice: result.unitPrice,
        paymentMethod: result.paymentMethod,
        notes: result.notes,
        postFinancial: result.postFinancial,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BarData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final lowStock = data.products
            .where((p) => _double(p['current_stock']) <= _double(p['minimum_stock']))
            .length;
        final stockValue = data.products.fold<double>(
          0,
          (sum, p) => sum + _double(p['current_stock']) * _double(p['cost']),
        );

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: const TabBar(
              tabs: [
                Tab(text: 'Stock', icon: Icon(Icons.local_bar_outlined)),
                Tab(text: 'Movimentos', icon: Icon(Icons.history_outlined)),
              ],
            ),
            body: TabBarView(
              children: [
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _Metric('Artigos', '${data.products.length}', Icons.local_bar_outlined),
                          _Metric('Stock baixo', '$lowStock', Icons.warning_amber_outlined),
                          _Metric('Valor teórico', _money(stockValue), Icons.euro_outlined),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Card(
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.info_outline),
                          title: Text('Valor teórico'),
                          subtitle: Text('Valor de custo do stock atualmente existente, calculado pelo custo médio por consumo.'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (data.products.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.local_bar_outlined),
                            title: Text('Ainda não existem artigos de Bar.'),
                            subtitle: Text('Cria cerveja, água, refrigerantes, sidra, sangria ou outros consumíveis.'),
                          ),
                        )
                      else
                        for (final product in data.products)
                          _ProductCard(
                            product: product,
                            canManage: _canManage,
                            onEdit: () => _editProduct(product),
                            onOperation: (value) => _operation(product, data.events, value),
                          ),
                    ],
                  ),
                ),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (data.operations.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.history_outlined),
                            title: Text('Ainda não existem movimentos de Bar.'),
                          ),
                        )
                      else
                        for (final operation in data.operations)
                          _OperationCard(operation: operation),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: _canManage
                ? FloatingActionButton.extended(
                    onPressed: _editProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo artigo Bar'),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.canManage,
    required this.onEdit,
    required this.onOperation,
  });

  final Map<String, dynamic> product;
  final bool canManage;
  final VoidCallback onEdit;
  final ValueChanged<String> onOperation;

  @override
  Widget build(BuildContext context) {
    final stock = _double(product['current_stock']);
    final minimum = _double(product['minimum_stock']);
    final conversion = _double(product['units_per_purchase']);
    final purchaseEquivalent = conversion > 0 ? stock / conversion : 0;
    final costPerConsumption = _double(product['cost']);
    final low = stock <= minimum;
    final consumptionUnit = product['consumption_unit']?.toString() ?? 'unid.';
    final purchaseUnit = product['purchase_unit']?.toString() ?? 'embalagem';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(low ? Icons.warning_amber_outlined : Icons.local_bar_outlined),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name']?.toString() ?? 'Artigo',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(product['category']?.toString() ?? 'Bar'),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (value) => value == 'edit' ? onEdit() : onOperation(value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'purchase', child: Text('Entrada / compra')),
                      PopupMenuItem(value: 'sale', child: Text('Venda')),
                      PopupMenuItem(value: 'offer', child: Text('Oferta')),
                      PopupMenuItem(value: 'internal', child: Text('Consumo interno')),
                      PopupMenuItem(value: 'waste', child: Text('Quebra / desperdício')),
                      PopupMenuItem(value: 'adjustment_in', child: Text('Ajuste positivo')),
                      PopupMenuItem(value: 'adjustment_out', child: Text('Ajuste negativo')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'edit', child: Text('Editar artigo')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(low ? Icons.warning_amber_outlined : Icons.inventory_2_outlined, size: 18),
                  label: Text('${_number(stock)} $consumptionUnit'),
                ),
                Chip(
                  avatar: const Icon(Icons.sync_alt_outlined, size: 18),
                  label: Text('≈ ${_number(purchaseEquivalent)} $purchaseUnit'),
                ),
                Chip(
                  avatar: const Icon(Icons.sell_outlined, size: 18),
                  label: Text('${_money(product['sale_price'])} / $consumptionUnit'),
                ),
                Chip(
                  avatar: const Icon(Icons.calculate_outlined, size: 18),
                  label: Text('Custo ${_money(costPerConsumption)} / $consumptionUnit'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('1 $purchaseUnit = ${_number(conversion)} $consumptionUnit'),
            if ((product['supplier']?.toString() ?? '').isNotEmpty)
              Text('Fornecedor: ${product['supplier']}'),
          ],
        ),
      ),
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation});
  final Map<String, dynamic> operation;

  @override
  Widget build(BuildContext context) {
    final product = operation['products'];
    final event = operation['events'];
    final type = operation['operation_type']?.toString() ?? '';
    final productName = product is Map ? product['name']?.toString() ?? 'Artigo' : 'Artigo';
    final unit = product is Map ? product['consumption_unit']?.toString() ?? 'unid.' : 'unid.';
    final eventName = event is Map ? event['name']?.toString() : null;
    final created = DateTime.tryParse(operation['created_at']?.toString() ?? '')?.toLocal();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_operationIcon(type))),
        title: Text('${_operationLabel(type)} · $productName'),
        subtitle: Text([
          '${_number(operation['consumption_quantity'])} $unit',
          if (_double(operation['total_amount']) > 0) _money(operation['total_amount']),
          if (eventName != null && eventName.isNotEmpty) eventName,
          if (created != null) DateFormat('dd/MM/yyyy HH:mm').format(created),
          operation['notes']?.toString(),
        ].whereType<String>().where((value) => value.isNotEmpty).join(' · ')),
      ),
    );
  }
}

class _BarProductDialog extends StatefulWidget {
  const _BarProductDialog({this.product});
  final Map<String, dynamic>? product;

  @override
  State<_BarProductDialog> createState() => _BarProductDialogState();
}

class _BarProductDialogState extends State<_BarProductDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _supplier;
  late final TextEditingController _purchaseUnit;
  late final TextEditingController _consumptionUnit;
  late final TextEditingController _conversion;
  late final TextEditingController _purchaseCost;
  late final TextEditingController _salePrice;
  late final TextEditingController _minimum;
  String? _preset;

  static const _presets = <String, _BarPreset>{
    'Barril 50 L → Copo 0,25 L': _BarPreset('Barril 50 L', 'Copo 0,25 L', 200),
    'Barril 30 L → Copo 0,25 L': _BarPreset('Barril 30 L', 'Copo 0,25 L', 120),
    'Caixa 24 → Garrafa 0,25 L': _BarPreset('Caixa 24', 'Garrafa 0,25 L', 24),
    'Garrafa 5 L → Copo 0,25 L': _BarPreset('Garrafa 5 L', 'Copo 0,25 L', 20),
    'Garrafa 0,25 L': _BarPreset('Garrafa 0,25 L', 'Garrafa 0,25 L', 1),
  };

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? const <String, dynamic>{};
    _name = TextEditingController(text: p['name']?.toString() ?? '');
    _sku = TextEditingController(text: p['sku']?.toString() ?? '');
    _category = TextEditingController(text: p['category']?.toString() ?? 'Bebidas');
    _description = TextEditingController(text: p['description']?.toString() ?? '');
    _supplier = TextEditingController(text: p['supplier']?.toString() ?? '');
    _purchaseUnit = TextEditingController(text: p['purchase_unit']?.toString() ?? 'Caixa');
    _consumptionUnit = TextEditingController(text: p['consumption_unit']?.toString() ?? 'Unidade');
    _conversion = TextEditingController(text: _number(p['units_per_purchase'] ?? 1));
    _purchaseCost = TextEditingController(text: _number(p['purchase_cost'] ?? 0));
    _salePrice = TextEditingController(text: _number(p['sale_price'] ?? 0));
    _minimum = TextEditingController(text: _number(p['minimum_stock'] ?? 0));
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _category,
      _description,
      _supplier,
      _purchaseUnit,
      _consumptionUnit,
      _conversion,
      _purchaseCost,
      _salePrice,
      _minimum,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String? value) {
    if (value == null) return;
    final preset = _presets[value]!;
    setState(() {
      _preset = value;
      _purchaseUnit.text = preset.purchaseUnit;
      _consumptionUnit.text = preset.consumptionUnit;
      _conversion.text = _number(preset.conversion);
    });
  }

  InputDecoration _decoration(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      );

  Widget _field(TextEditingController controller, String label, {String? helper, int maxLines = 1, bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : null,
        onChanged: (_) => setState(() {}),
        decoration: _decoration(label, helper: helper),
      ),
    );
  }

  Widget _section(BuildContext context, String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversion = _parse(_conversion.text);
    final purchaseCost = _parse(_purchaseCost.text);
    final costPerConsumption = conversion > 0 ? purchaseCost / conversion : 0;

    return AlertDialog(
      title: Text(widget.product == null ? 'Novo artigo do Bar' : 'Editar artigo do Bar'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _section(context, 'Modelo rápido', Icons.auto_awesome_outlined, [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: DropdownButtonFormField<String>(
                    initialValue: _preset,
                    isExpanded: true,
                    decoration: _decoration('Escolher modelo'),
                    items: _presets.keys.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                    onChanged: _applyPreset,
                  ),
                ),
              ]),
              _section(context, 'Geral', Icons.info_outline, [
                _field(_name, 'Nome *'),
                _field(_sku, 'Código / SKU'),
                _field(_category, 'Categoria'),
                _field(_supplier, 'Fornecedor'),
                _field(_description, 'Descrição', maxLines: 2),
              ]),
              _section(context, 'Stock e conversão', Icons.inventory_2_outlined, [
                _field(_purchaseUnit, 'Unidade de compra', helper: 'Ex.: Barril 50 L, Caixa 24, Garrafa 0,25 L'),
                _field(_consumptionUnit, 'Unidade de consumo', helper: 'Ex.: Copo 0,25 L, Garrafa 0,25 L, Unidade'),
                _field(_conversion, 'Consumos por unidade de compra *', numeric: true),
                if (conversion > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Card(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.sync_alt_outlined),
                        title: Text('1 ${_purchaseUnit.text} = ${_number(conversion)} ${_consumptionUnit.text}'),
                      ),
                    ),
                  ),
                _field(_minimum, 'Stock mínimo (unidades de consumo)', numeric: true),
              ]),
              _section(context, 'Valores', Icons.euro_outlined, [
                _field(
                  _purchaseCost,
                  'Custo da embalagem / unidade de compra (€)',
                  helper: 'Preço total do barril, caixa ou garrafa de compra.',
                  numeric: true,
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.calculate_outlined),
                    title: const Text('Custo calculado por consumo'),
                    subtitle: Text('${_money(costPerConsumption)} por ${_consumptionUnit.text.isEmpty ? 'consumo' : _consumptionUnit.text}'),
                  ),
                ),
                _field(_salePrice, 'Preço por consumo (€)', numeric: true),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty || _parse(_conversion.text) <= 0) return;
            Navigator.pop(
              context,
              _BarProductInput(
                name: _name.text,
                sku: _sku.text,
                category: _category.text,
                description: _description.text,
                supplier: _supplier.text,
                purchaseUnit: _purchaseUnit.text,
                consumptionUnit: _consumptionUnit.text,
                unitsPerPurchase: _parse(_conversion.text),
                purchaseCost: _parse(_purchaseCost.text),
                salePrice: _parse(_salePrice.text),
                minimumStock: _parse(_minimum.text),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.product, required this.events});
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> events;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _units = TextEditingController(text: '1');
  late final TextEditingController _cost;
  final _notes = TextEditingController();
  String? _eventId;
  String _payment = 'Dinheiro';
  bool _financial = true;

  @override
  void initState() {
    super.initState();
    _cost = TextEditingController(text: _number(widget.product['purchase_cost']));
  }

  @override
  void dispose() {
    _units.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversion = _double(widget.product['units_per_purchase']);
    final purchaseUnit = widget.product['purchase_unit']?.toString() ?? 'unidade de compra';
    final consumptionUnit = widget.product['consumption_unit']?.toString() ?? 'unidade';
    final quantity = _parse(_units.text);
    final cost = _parse(_cost.text);
    return AlertDialog(
      title: Text('Entrada · ${widget.product['name']}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _units,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade de $purchaseUnit',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.sync_alt_outlined),
                  title: Text('Equivale a ${_number(quantity * conversion)} $consumptionUnit'),
                  subtitle: Text('Custo total desta entrada: ${_money(quantity * cost)}'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Custo de 1 $purchaseUnit (€)',
                  helperText: 'Introduz o preço total da embalagem/unidade de compra.',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _EventField(events: widget.events, value: _eventId, onChanged: (value) => setState(() => _eventId = value)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _payment,
                decoration: const InputDecoration(labelText: 'Pagamento', border: OutlineInputBorder()),
                items: const ['Dinheiro', 'MB Way', 'Transferência bancária']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (value) => setState(() => _payment = value ?? _payment),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _financial,
                onChanged: (value) => setState(() => _financial = value),
                title: const Text('Registar despesa na Tesouraria'),
              ),
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas', border: OutlineInputBorder())),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final units = _parse(_units.text);
            if (units <= 0) return;
            Navigator.pop(context, _PurchaseInput(units, _parse(_cost.text), _eventId, _payment, _notes.text, _financial));
          },
          child: const Text('Registar entrada'),
        ),
      ],
    );
  }
}

class _ConsumptionDialog extends StatefulWidget {
  const _ConsumptionDialog({required this.product, required this.events, required this.operation});
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> events;
  final String operation;

  @override
  State<_ConsumptionDialog> createState() => _ConsumptionDialogState();
}

class _ConsumptionDialogState extends State<_ConsumptionDialog> {
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _price;
  final _notes = TextEditingController();
  String? _eventId;
  String _payment = 'Dinheiro';
  bool _financial = true;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: _number(widget.product['sale_price']));
    _financial = widget.operation == 'sale';
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSale = widget.operation == 'sale';
    return AlertDialog(
      title: Text('${_operationLabel(widget.operation)} · ${widget.product['name']}'),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Stock atual: ${_number(widget.product['current_stock'])} ${widget.product['consumption_unit'] ?? 'unid.'}'),
              const SizedBox(height: 14),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantidade (${widget.product['consumption_unit'] ?? 'unid.'})',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _EventField(events: widget.events, value: _eventId, onChanged: (value) => setState(() => _eventId = value)),
              if (isSale) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Preço unitário (€)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _payment,
                  decoration: const InputDecoration(labelText: 'Pagamento', border: OutlineInputBorder()),
                  items: const ['Dinheiro', 'MB Way', 'Transferência bancária', 'Cartão consumo']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (value) => setState(() => _payment = value ?? _payment),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _financial,
                  onChanged: (value) => setState(() => _financial = value),
                  title: const Text('Registar receita na Tesouraria'),
                  subtitle: const Text('Desativa para consumos já pagos por cartão/ficha.'),
                ),
              ],
              TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas / motivo', border: OutlineInputBorder())),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final quantity = _parse(_quantity.text);
            if (quantity <= 0) return;
            Navigator.pop(
              context,
              _ConsumptionInput(
                quantity,
                _eventId,
                isSale ? _parse(_price.text) : null,
                isSale ? _payment : null,
                _notes.text,
                isSale && _financial,
              ),
            );
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

class _EventField extends StatelessWidget {
  const _EventField({required this.events, required this.value, required this.onChanged});
  final List<Map<String, dynamic>> events;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Evento (opcional)', border: OutlineInputBorder()),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Sem evento associado')),
        ...events.map((event) => DropdownMenuItem<String?>(
              value: event['id']?.toString(),
              child: Text(event['name']?.toString() ?? 'Evento'),
            )),
      ],
      onChanged: onChanged,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Card(
          child: ListTile(
            leading: CircleAvatar(child: Icon(icon)),
            title: Text(label),
            subtitle: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          ),
        ),
      );
}

class _BarData {
  const _BarData({required this.products, required this.events, required this.operations});
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> operations;
}

class _BarPreset {
  const _BarPreset(this.purchaseUnit, this.consumptionUnit, this.conversion);
  final String purchaseUnit;
  final String consumptionUnit;
  final double conversion;
}

class _BarProductInput {
  const _BarProductInput({
    required this.name,
    required this.sku,
    required this.category,
    required this.description,
    required this.supplier,
    required this.purchaseUnit,
    required this.consumptionUnit,
    required this.unitsPerPurchase,
    required this.purchaseCost,
    required this.salePrice,
    required this.minimumStock,
  });
  final String name, sku, category, description, supplier, purchaseUnit, consumptionUnit;
  final double unitsPerPurchase, purchaseCost, salePrice, minimumStock;
}

class _PurchaseInput {
  const _PurchaseInput(this.purchaseUnits, this.costPerPurchaseUnit, this.eventId, this.paymentMethod, this.notes, this.postFinancial);
  final double purchaseUnits, costPerPurchaseUnit;
  final String? eventId;
  final String paymentMethod, notes;
  final bool postFinancial;
}

class _ConsumptionInput {
  const _ConsumptionInput(this.quantity, this.eventId, this.unitPrice, this.paymentMethod, this.notes, this.postFinancial);
  final double quantity;
  final String? eventId;
  final double? unitPrice;
  final String? paymentMethod;
  final String notes;
  final bool postFinancial;
}

String _operationLabel(String operation) => switch (operation) {
      'purchase' => 'Entrada / compra',
      'sale' => 'Venda',
      'offer' => 'Oferta',
      'internal' => 'Consumo interno',
      'waste' => 'Quebra / desperdício',
      'adjustment_in' => 'Ajuste positivo',
      'adjustment_out' => 'Ajuste negativo',
      _ => 'Movimento',
    };

IconData _operationIcon(String operation) => switch (operation) {
      'purchase' => Icons.add_box_outlined,
      'sale' => Icons.point_of_sale_outlined,
      'offer' => Icons.card_giftcard_outlined,
      'internal' => Icons.groups_outlined,
      'waste' => Icons.delete_outline,
      'adjustment_in' || 'adjustment_out' => Icons.tune_outlined,
      _ => Icons.swap_horiz_outlined,
    };

double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
double _parse(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;
String _number(Object? value) {
  final number = _double(value);
  return number == number.roundToDouble() ? number.toInt().toString() : number.toStringAsFixed(2).replaceAll('.', ',');
}
String _money(Object? value) => NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(_double(value));
