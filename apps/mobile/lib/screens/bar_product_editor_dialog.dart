import 'package:flutter/material.dart';

class BarProductEditorDialog extends StatefulWidget {
  const BarProductEditorDialog({super.key, this.product});

  final Map<String, dynamic>? product;

  @override
  State<BarProductEditorDialog> createState() => _BarProductEditorDialogState();
}

class _BarProductEditorDialogState extends State<BarProductEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _category;
  late final TextEditingController _description;
  late final TextEditingController _supplier;
  late final TextEditingController _purchaseUnit;
  late final TextEditingController _stockUnit;
  late final TextEditingController _conversion;
  late final TextEditingController _purchaseCost;
  late final TextEditingController _minimum;
  final List<_SaleOptionEditor> _options = [];
  String? _preset;

  static const _presets = <String, _ProductPreset>{
    'Barril 50 L → Copo 0,25 L': _ProductPreset(
      purchaseUnit: 'Barril 50 L',
      stockUnit: 'Copo 0,25 L',
      conversion: 200,
      options: [
        _PresetOption('Copo 0,25 L', 1),
      ],
    ),
    'Barril 30 L → Copo 0,25 L': _ProductPreset(
      purchaseUnit: 'Barril 30 L',
      stockUnit: 'Copo 0,25 L',
      conversion: 120,
      options: [
        _PresetOption('Copo 0,25 L', 1),
      ],
    ),
    'Garrafa 700 ml → Shot / Dose': _ProductPreset(
      purchaseUnit: 'Garrafa 700 ml',
      stockUnit: 'ml',
      conversion: 700,
      options: [
        _PresetOption('Shot', 25),
        _PresetOption('Dose', 50),
      ],
    ),
    'Garrafa 750 ml → Shot / Dose': _ProductPreset(
      purchaseUnit: 'Garrafa 750 ml',
      stockUnit: 'ml',
      conversion: 750,
      options: [
        _PresetOption('Shot', 25),
        _PresetOption('Dose', 50),
      ],
    ),
    'Garrafa 1 L → Shot / Dose': _ProductPreset(
      purchaseUnit: 'Garrafa 1 L',
      stockUnit: 'ml',
      conversion: 1000,
      options: [
        _PresetOption('Shot', 25),
        _PresetOption('Dose', 50),
      ],
    ),
    'Pack 6 → Unidade': _ProductPreset(
      purchaseUnit: 'Pack 6',
      stockUnit: 'unidade',
      conversion: 6,
      options: [
        _PresetOption('Unidade', 1),
      ],
    ),
    'Caixa 24 → Unidade': _ProductPreset(
      purchaseUnit: 'Caixa 24',
      stockUnit: 'unidade',
      conversion: 24,
      options: [
        _PresetOption('Unidade', 1),
      ],
    ),
    'Caixa 33 → Unidade': _ProductPreset(
      purchaseUnit: 'Caixa 33',
      stockUnit: 'unidade',
      conversion: 33,
      options: [
        _PresetOption('Unidade', 1),
      ],
    ),
    'Personalizado': _ProductPreset(
      purchaseUnit: '',
      stockUnit: '',
      conversion: 1,
      options: [
        _PresetOption('Unidade', 1),
      ],
    ),
  };

  @override
  void initState() {
    super.initState();
    final product = widget.product ?? const <String, dynamic>{};
    _name = TextEditingController(text: product['name']?.toString() ?? '');
    _sku = TextEditingController(text: product['sku']?.toString() ?? '');
    _category = TextEditingController(
      text: product['category']?.toString() ?? 'Bebidas',
    );
    _description = TextEditingController(
      text: product['description']?.toString() ?? '',
    );
    _supplier = TextEditingController(
      text: product['supplier']?.toString() ?? '',
    );
    _purchaseUnit = TextEditingController(
      text: product['purchase_unit']?.toString() ?? '',
    );
    _stockUnit = TextEditingController(
      text: product['consumption_unit']?.toString() ?? 'unidade',
    );
    _conversion = TextEditingController(
      text: _number(product['units_per_purchase'] ?? 1),
    );
    _purchaseCost = TextEditingController(
      text: _number(product['purchase_cost'] ?? 0),
    );
    _minimum = TextEditingController(
      text: _number(product['minimum_stock'] ?? 0),
    );

    final raw = product['sale_options'] ?? product['bar_product_sale_options'];
    if (raw is List) {
      for (final value in raw.whereType<Map>()) {
        if (value['active'] == false) continue;
        _options.add(
          _SaleOptionEditor(
            id: value['id']?.toString(),
            name: value['name']?.toString() ?? 'Unidade',
            stockQuantity: _number(value['stock_quantity'] ?? 1),
            publicPrice: _number(value['public_price'] ?? product['sale_price'] ?? 0),
            memberPrice: _number(value['member_price'] ?? product['sale_price'] ?? 0),
          ),
        );
      }
    }
    if (_options.isEmpty) {
      final price = _number(product['sale_price'] ?? 0);
      _options.add(
        _SaleOptionEditor(
          name: _defaultOptionName(_stockUnit.text),
          stockQuantity: '1',
          publicPrice: price,
          memberPrice: price,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _sku,
      _category,
      _description,
      _supplier,
      _purchaseUnit,
      _stockUnit,
      _conversion,
      _purchaseCost,
      _minimum,
    ]) {
      controller.dispose();
    }
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String? value) {
    if (value == null) return;
    final preset = _presets[value]!;
    setState(() {
      _preset = value;
      if (value == 'Personalizado') return;
      _purchaseUnit.text = preset.purchaseUnit;
      _stockUnit.text = preset.stockUnit;
      _conversion.text = _number(preset.conversion);
      for (final option in _options) {
        option.dispose();
      }
      _options
        ..clear()
        ..addAll(
          preset.options.map(
            (option) => _SaleOptionEditor(
              name: option.name,
              stockQuantity: _number(option.stockQuantity),
              publicPrice: '0',
              memberPrice: '0',
            ),
          ),
        );
    });
  }

  void _addOption() {
    setState(() {
      _options.add(
        _SaleOptionEditor(
          name: '',
          stockQuantity: '1',
          publicPrice: '0',
          memberPrice: '0',
        ),
      );
    });
  }

  void _removeOption(int index) {
    if (_options.length <= 1) return;
    setState(() {
      final removed = _options.removeAt(index);
      removed.dispose();
    });
  }

  InputDecoration _decoration(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: const OutlineInputBorder(),
        alignLabelWithHint: true,
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? helper,
    int maxLines = 1,
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        onChanged: (_) => setState(() {}),
        decoration: _decoration(label, helper: helper),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
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
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _name.text.trim();
    final purchaseUnit = _purchaseUnit.text.trim();
    final stockUnit = _stockUnit.text.trim();
    final conversion = _parse(_conversion.text);
    if (name.isEmpty || purchaseUnit.isEmpty || stockUnit.isEmpty || conversion <= 0) {
      _show('Preenche nome, unidade de compra, unidade base de stock e conversão.');
      return;
    }
    if (_parse(_purchaseCost.text) < 0 || _parse(_minimum.text) < 0) {
      _show('Custos e stock mínimo não podem ser negativos.');
      return;
    }
    final options = <Map<String, dynamic>>[];
    final names = <String>{};
    for (final option in _options) {
      final optionName = option.name.text.trim();
      final stockQuantity = _parse(option.stockQuantity.text);
      final publicPrice = _parse(option.publicPrice.text);
      final memberPrice = _parse(option.memberPrice.text);
      if (optionName.isEmpty || stockQuantity <= 0) {
        _show('Cada forma de venda precisa de nome e quantidade de stock superior a zero.');
        return;
      }
      if (publicPrice < 0 || memberPrice < 0) {
        _show('Os preços não podem ser negativos.');
        return;
      }
      final normalized = optionName.toLowerCase();
      if (!names.add(normalized)) {
        _show('Não podes ter duas formas de venda com o mesmo nome.');
        return;
      }
      options.add({
        if (option.id != null) 'id': option.id,
        'name': optionName,
        'stock_quantity': stockQuantity,
        'public_price': publicPrice,
        'member_price': memberPrice,
      });
    }

    Navigator.pop(
      context,
      BarProductInput(
        name: name,
        sku: _sku.text,
        category: _category.text,
        description: _description.text,
        supplier: _supplier.text,
        purchaseUnit: purchaseUnit,
        stockUnit: stockUnit,
        unitsPerPurchase: conversion,
        purchaseCost: _parse(_purchaseCost.text),
        minimumStock: _parse(_minimum.text),
        saleOptions: options,
      ),
    );
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final conversion = _parse(_conversion.text);
    final purchaseCost = _parse(_purchaseCost.text);
    final baseCost = conversion > 0 ? purchaseCost / conversion : 0;

    return AlertDialog(
      title: Text(widget.product == null ? 'Novo artigo do BAR' : 'Editar artigo do BAR'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _section(context, 'Modelo rápido', Icons.auto_awesome_outlined, [
                DropdownButtonFormField<String>(
                  initialValue: _preset,
                  isExpanded: true,
                  decoration: _decoration('Modelo de embalagem / serviço'),
                  items: _presets.keys
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: _applyPreset,
                ),
                const SizedBox(height: 12),
              ]),
              _section(context, 'Geral', Icons.info_outline, [
                _field(_name, 'Nome *'),
                _field(_sku, 'Código / SKU'),
                _field(_category, 'Categoria'),
                _field(_supplier, 'Fornecedor'),
                _field(_description, 'Descrição', maxLines: 2),
              ]),
              _section(context, 'Stock base', Icons.inventory_2_outlined, [
                _field(
                  _purchaseUnit,
                  'Como compras este artigo? *',
                  helper: 'Ex.: Garrafa 700 ml, Caixa 24, Barril 50 L.',
                ),
                _field(
                  _stockUnit,
                  'Unidade base que fica em stock *',
                  helper: 'Ex.: ml, unidade, Copo 0,25 L. Shots/Doses usam esta base.',
                ),
                _field(
                  _conversion,
                  'Quantas unidades base entram por compra? *',
                  numeric: true,
                ),
                if (conversion > 0)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.sync_alt_outlined),
                      title: Text(
                        '1 ${_purchaseUnit.text.trim().isEmpty ? 'compra' : _purchaseUnit.text} = ${_number(conversion)} ${_stockUnit.text.trim().isEmpty ? 'unidades base' : _stockUnit.text}',
                      ),
                    ),
                  ),
                _field(
                  _purchaseCost,
                  'Custo de 1 ${_purchaseUnit.text.trim().isEmpty ? 'embalagem' : _purchaseUnit.text} (€)',
                  numeric: true,
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.calculate_outlined),
                    title: const Text('Custo teórico por unidade base'),
                    subtitle: Text('${_money(baseCost)} / ${_stockUnit.text}'),
                  ),
                ),
                _field(
                  _minimum,
                  'Stock mínimo (${_stockUnit.text.trim().isEmpty ? 'unidade base' : _stockUnit.text})',
                  numeric: true,
                ),
              ]),
              _section(context, 'Formas de venda e preços', Icons.point_of_sale_outlined, [
                const Text(
                  'Cada forma usa o mesmo stock do artigo. Define quanto consome e o preço para Público e Membro.',
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < _options.length; index++)
                  _SaleOptionCard(
                    editor: _options[index],
                    stockUnit: _stockUnit.text,
                    canRemove: _options.length > 1,
                    onChanged: () => setState(() {}),
                    onRemove: () => _removeOption(index),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar forma de venda'),
                  ),
                ),
                const SizedBox(height: 12),
              ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar artigo'),
        ),
      ],
    );
  }
}

class _SaleOptionCard extends StatelessWidget {
  const _SaleOptionCard({
    required this.editor,
    required this.stockUnit,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _SaleOptionEditor editor;
  final String stockUnit;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Forma de venda',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Remover',
                  onPressed: canRemove ? onRemove : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextField(
              controller: editor.name,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Nome · ex.: Shot, Dose, Unidade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 620;
                final fields = [
                  Expanded(
                    child: TextField(
                      controller: editor.stockQuantity,
                      onChanged: (_) => onChanged(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Consome (${stockUnit.isEmpty ? 'stock' : stockUnit})',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8, height: 8),
                  Expanded(
                    child: TextField(
                      controller: editor.publicPrice,
                      onChanged: (_) => onChanged(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço público (€)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8, height: 8),
                  Expanded(
                    child: TextField(
                      controller: editor.memberPrice,
                      onChanged: (_) => onChanged(),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço membro (€)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ];
                if (!narrow) return Row(children: fields);
                return Column(
                  children: [
                    for (final child in fields)
                      if (child is SizedBox)
                        const SizedBox(height: 8)
                      else
                        SizedBox(width: double.infinity, child: child),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BarProductInput {
  const BarProductInput({
    required this.name,
    required this.sku,
    required this.category,
    required this.description,
    required this.supplier,
    required this.purchaseUnit,
    required this.stockUnit,
    required this.unitsPerPurchase,
    required this.purchaseCost,
    required this.minimumStock,
    required this.saleOptions,
  });

  final String name;
  final String sku;
  final String category;
  final String description;
  final String supplier;
  final String purchaseUnit;
  final String stockUnit;
  final double unitsPerPurchase;
  final double purchaseCost;
  final double minimumStock;
  final List<Map<String, dynamic>> saleOptions;
}

class _SaleOptionEditor {
  _SaleOptionEditor({
    this.id,
    required String name,
    required String stockQuantity,
    required String publicPrice,
    required String memberPrice,
  })  : name = TextEditingController(text: name),
        stockQuantity = TextEditingController(text: stockQuantity),
        publicPrice = TextEditingController(text: publicPrice),
        memberPrice = TextEditingController(text: memberPrice);

  final String? id;
  final TextEditingController name;
  final TextEditingController stockQuantity;
  final TextEditingController publicPrice;
  final TextEditingController memberPrice;

  void dispose() {
    name.dispose();
    stockQuantity.dispose();
    publicPrice.dispose();
    memberPrice.dispose();
  }
}

class _ProductPreset {
  const _ProductPreset({
    required this.purchaseUnit,
    required this.stockUnit,
    required this.conversion,
    required this.options,
  });

  final String purchaseUnit;
  final String stockUnit;
  final double conversion;
  final List<_PresetOption> options;
}

class _PresetOption {
  const _PresetOption(this.name, this.stockQuantity);

  final String name;
  final double stockQuantity;
}

String _defaultOptionName(String stockUnit) {
  final value = stockUnit.trim();
  if (value.isEmpty || value == '1' || value.toLowerCase() == 'unidade') {
    return 'Unidade';
  }
  return value;
}

double _parse(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

String _number(Object? value) {
  final number = _double(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2).replaceAll('.', ',');
}

String _money(Object? value) => '${_double(value).toStringAsFixed(2).replaceAll('.', ',')} €';
