import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/bar_repository.dart';
import '../repositories/financial_ocr_repository.dart';
import 'bar_ocr_review_screen.dart';
import 'bar_sales_screen.dart';

class BarScreenV3 extends StatefulWidget {
  const BarScreenV3({super.key});

  @override
  State<BarScreenV3> createState() => _BarScreenV3State();
}

class _BarScreenV3State extends State<BarScreenV3> {
  final BarRepository _repository = BarRepository();
  final FinancialOcrRepository _ocrRepository = FinancialOcrRepository();
  late Future<_BarData> _future;

  bool get _canManage => AppSession.instance.can(AppPermission.manageBar);
  bool get _canSelectAccount =>
      AppSession.instance.can(AppPermission.selectBarFinancialAccount);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      _repository.products(),
      _repository.events(),
      _repository.operations(),
      _canSelectAccount
          ? _repository.treasuryAccounts()
          : Future<List<Map<String, dynamic>>>.value(const []),
    ]).then(
      (values) => _BarData(
        products: List<Map<String, dynamic>>.from(values[0] as List),
        events: List<Map<String, dynamic>>.from(values[1] as List),
        operations: List<Map<String, dynamic>>.from(values[2] as List),
        accounts: List<Map<String, dynamic>>.from(values[3] as List),
      ),
    );
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

  Future<void> _editProduct(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> accounts, [
    Map<String, dynamic>? product,
  ]) async {
    final result = await showDialog<_BarProductInput>(
      context: context,
      builder: (_) => _BarProductDialog(product: product),
    );
    if (result == null) return;

    try {
      final saved = await _repository.saveProduct(
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
      if (!mounted) return;
      setState(_reload);

      if (product == null) {
        final addStock = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Artigo criado'),
            content: Text(
              '${result.name} foi criado com stock zero.\n\nPretendes registar agora a primeira entrada de stock?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Agora não'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Adicionar stock'),
              ),
            ],
          ),
        );
        if (addStock == true && mounted) {
          await _purchase(saved, events, accounts);
        }
      }
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _purchase(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> accounts,
  ) async {
    final result = await showDialog<_PurchaseInput>(
      context: context,
      builder: (_) => _PurchaseDialog(
        product: product,
        events: events,
        accounts: accounts,
        canSelectAccount: _canSelectAccount,
      ),
    );
    if (result == null) return;
    try {
      await _repository.purchase(
        product: product,
        purchaseUnits: result.purchaseUnits,
        costPerPurchaseUnit: result.costPerPurchaseUnit,
        eventId: result.eventId,
        accountId: result.accountId,
        paymentMethod: result.paymentMethod,
        notes: result.notes,
        postFinancial: result.postFinancial,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _barOcr(_BarData data) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        allowMultiple: false,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final jobId = await _ocrRepository.createBarJob();
      await _ocrRepository.uploadBarSource(
        jobId: jobId,
        file: picked.files.single,
      );
      final job = await _ocrRepository.runOcr(jobId);
      if (!mounted) return;

      final status = job['status']?.toString();
      if (status == 'unconfigured') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('OCR preparado, mas ainda não configurado'),
            content: const Text(
              'Falta configurar GOOGLE_VISION_API_KEY e GOOGLE_CLOUD_PROJECT_ID nos secrets do Supabase. '
              'O talão ficou guardado e poderá ser analisado depois, sem voltar a carregá-lo.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      if (status == 'failed') {
        throw StateError(
          job['error_message']?.toString() ?? 'A leitura OCR falhou.',
        );
      }
      if (status != 'ready' && status != 'reviewed') {
        throw StateError('O OCR ainda não está pronto para revisão.');
      }

      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BarOcrReviewScreen(
            job: job,
            products: data.products,
            events: data.events,
            accounts: data.accounts,
            canSelectAccount: _canSelectAccount,
          ),
        ),
      );
      if (changed == true && mounted) setState(_reload);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _operation(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> accounts,
    String operation,
  ) async {
    if (operation == 'purchase') {
      await _purchase(product, events, accounts);
      return;
    }

    final result = await showDialog<_ConsumptionInput>(
      context: context,
      builder: (_) => _ConsumptionDialog(
        product: product,
        events: events,
        accounts: accounts,
        canSelectAccount: _canSelectAccount,
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
        accountId: result.accountId,
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
            .where(
              (p) =>
                  _double(p['current_stock']) <= _double(p['minimum_stock']),
            )
            .length;
        final stockValue = data.products.fold<double>(
          0,
          (sum, p) =>
              sum + _double(p['current_stock']) * _double(p['cost']),
        );

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: const TabBar(
              tabs: [
                Tab(text: 'Stock', icon: Icon(Icons.inventory_2_outlined)),
                Tab(text: 'Venda', icon: Icon(Icons.point_of_sale_outlined)),
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
                          _Metric(
                            'Artigos',
                            '${data.products.length}',
                            Icons.local_bar_outlined,
                          ),
                          _Metric(
                            'Stock baixo',
                            '$lowStock',
                            Icons.warning_amber_outlined,
                          ),
                          _Metric(
                            'Valor teórico',
                            _money(stockValue),
                            Icons.euro_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Card(
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.info_outline),
                          title: Text('Valor teórico'),
                          subtitle: Text(
                            'Valor de custo do stock que existe neste momento. Só aumenta quando é registada uma entrada de stock.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_canManage) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: const Text('Novo artigo do Bar'),
                            subtitle: const Text(
                              'Criar bebida ou consumível e definir embalagem, preço, conversão e stock mínimo.',
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: () =>
                                  _editProduct(data.events, data.accounts),
                              icon: const Icon(Icons.add),
                              label: const Text('Criar'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.document_scanner_outlined),
                            title: const Text('Registar compra a partir de talão / fatura'),
                            subtitle: const Text(
                              'JPG, PNG, WEBP ou PDF. O OCR propõe os dados e só atualiza stock/Tesouraria depois da tua confirmação.',
                            ),
                            trailing: FilledButton.tonalIcon(
                              onPressed: () => _barOcr(data),
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Ler OCR'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (data.products.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.local_bar_outlined),
                            title: Text('Ainda não existem artigos de Bar.'),
                            subtitle: Text(
                              'Cria cerveja, água, refrigerantes, sidra, sangria ou outros consumíveis.',
                            ),
                          ),
                        )
                      else
                        for (final product in data.products)
                          _ProductCard(
                            product: product,
                            canManage: _canManage,
                            onEdit: () => _editProduct(
                              data.events,
                              data.accounts,
                              product,
                            ),
                            onOperation: (value) => _operation(
                              product,
                              data.events,
                              data.accounts,
                              value,
                            ),
                          ),
                    ],
                  ),
                ),
                const BarSalesScreen(),
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
    final averageCost = _double(product['cost']);
    final salePrice = _double(product['sale_price']);
    final margin = salePrice - averageCost;
    final marginPct = salePrice > 0 ? margin / salePrice * 100 : 0;
    final low = stock <= minimum;
    final consumption = product['consumption_unit']?.toString() ?? 'unid.';
    final purchase = product['purchase_unit']?.toString() ?? 'embalagem';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    low
                        ? Icons.warning_amber_outlined
                        : Icons.local_bar_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name']?.toString() ?? 'Artigo',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(product['category']?.toString() ?? 'Bar'),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (value) =>
                        value == 'edit' ? onEdit() : onOperation(value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'purchase',
                        child: Text('Entrada / compra'),
                      ),
                      PopupMenuItem(value: 'offer', child: Text('Oferta')),
                      PopupMenuItem(
                        value: 'internal',
                        child: Text('Consumo interno'),
                      ),
                      PopupMenuItem(
                        value: 'waste',
                        child: Text('Quebra / desperdício'),
                      ),
                      PopupMenuItem(
                        value: 'adjustment_in',
                        child: Text('Ajuste positivo'),
                      ),
                      PopupMenuItem(
                        value: 'adjustment_out',
                        child: Text('Ajuste negativo'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Editar artigo'),
                      ),
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
                  avatar: Icon(
                    low
                        ? Icons.warning_amber_outlined
                        : Icons.inventory_2_outlined,
                    size: 18,
                  ),
                  label: Text('${_number(stock)} $consumption'),
                ),
                Chip(
                  avatar: const Icon(Icons.sync_alt_outlined, size: 18),
                  label: Text('≈ ${_number(purchaseEquivalent)} $purchase'),
                ),
                Chip(
                  avatar: const Icon(Icons.sell_outlined, size: 18),
                  label: Text('${_money(salePrice)} / $consumption'),
                ),
                Chip(
                  avatar: const Icon(Icons.calculate_outlined, size: 18),
                  label: Text('Custo médio ${_money(averageCost)}'),
                ),
                Chip(
                  avatar: const Icon(Icons.trending_up_outlined, size: 18),
                  label: Text(
                    'Margem ${_money(margin)} · ${marginPct.toStringAsFixed(1).replaceAll('.', ',')}%',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Cada $purchase contém ${_number(conversion)} $consumption'),
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
    final transaction = operation['treasury_transactions'];
    final type = operation['operation_type']?.toString() ?? '';
    final productName = product is Map
        ? product['name']?.toString() ?? 'Artigo'
        : 'Artigo';
    final unit = product is Map
        ? product['consumption_unit']?.toString() ?? 'unid.'
        : 'unid.';
    final eventName = event is Map ? event['name']?.toString() : null;
    String? accountName;
    if (transaction is Map) {
      final account = transaction['treasury_accounts'];
      if (account is Map) accountName = account['name']?.toString();
    }
    final created = DateTime.tryParse(
      operation['created_at']?.toString() ?? '',
    )?.toLocal();
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_operationIcon(type))),
        title: Text('${_operationLabel(type)} · $productName'),
        subtitle: Text(
          [
            '${_number(operation['consumption_quantity'])} $unit',
            if (_double(operation['total_amount']) > 0)
              _money(operation['total_amount']),
            if (accountName != null && accountName.isNotEmpty)
              'Conta: $accountName',
            if (eventName != null && eventName.isNotEmpty) eventName,
            if (created != null)
              DateFormat('dd/MM/yyyy HH:mm').format(created),
            operation['notes']?.toString(),
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
        ),
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
    'Barril 50 L → Copo 0,25 L':
        _BarPreset('Barril 50 L', 'Copo 0,25 L', 200),
    'Barril 30 L → Copo 0,25 L':
        _BarPreset('Barril 30 L', 'Copo 0,25 L', 120),
    'Pack 6 → Garrafa 0,25 L':
        _BarPreset('Pack 6', 'Garrafa 0,25 L', 6),
    'Pack 12 → Garrafa 0,25 L':
        _BarPreset('Pack 12', 'Garrafa 0,25 L', 12),
    'Caixa 20 → Garrafa 0,25 L':
        _BarPreset('Caixa 20', 'Garrafa 0,25 L', 20),
    'Caixa 24 → Garrafa 0,25 L':
        _BarPreset('Caixa 24', 'Garrafa 0,25 L', 24),
    'Caixa 30 → Garrafa 0,25 L':
        _BarPreset('Caixa 30', 'Garrafa 0,25 L', 30),
    'Caixa 33 → Garrafa 0,25 L':
        _BarPreset('Caixa 33', 'Garrafa 0,25 L', 33),
    'Garrafa 5 L → Copo 0,25 L':
        _BarPreset('Garrafa 5 L', 'Copo 0,25 L', 20),
    'Garrafa 0,25 L':
        _BarPreset('Garrafa 0,25 L', 'Garrafa 0,25 L', 1),
    'Personalizado': _BarPreset('', '', 1),
  };

  @override
  void initState() {
    super.initState();
    final p = widget.product ?? const <String, dynamic>{};
    _name = TextEditingController(text: p['name']?.toString() ?? '');
    _sku = TextEditingController(text: p['sku']?.toString() ?? '');
    _category = TextEditingController(
      text: p['category']?.toString() ?? 'Bebidas',
    );
    _description = TextEditingController(text: p['description']?.toString() ?? '');
    _supplier = TextEditingController(text: p['supplier']?.toString() ?? '');
    _purchaseUnit = TextEditingController(
      text: p['purchase_unit']?.toString() ?? '',
    );
    _consumptionUnit = TextEditingController(
      text: p['consumption_unit']?.toString() ?? '',
    );
    _conversion = TextEditingController(
      text: _number(p['units_per_purchase'] ?? 1),
    );
    _purchaseCost = TextEditingController(
      text: _number(p['purchase_cost'] ?? 0),
    );
    _salePrice = TextEditingController(
      text: _number(p['sale_price'] ?? 0),
    );
    _minimum = TextEditingController(
      text: _number(p['minimum_stock'] ?? 0),
    );
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
      _consumptionUnit,
      _conversion,
      _purchaseCost,
      _salePrice,
      _minimum,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String? value) {
    if (value == null) return;
    final preset = _presets[value]!;
    setState(() {
      _preset = value;
      if (value != 'Personalizado') {
        _purchaseUnit.text = preset.purchaseUnit;
        _consumptionUnit.text = preset.consumptionUnit;
        _conversion.text = _number(preset.conversion);
      }
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
      padding: const EdgeInsets.only(bottom: 14),
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
    final salePrice = _parse(_salePrice.text);
    final unitCost = conversion > 0 ? purchaseCost / conversion : 0;
    final margin = salePrice - unitCost;

    return AlertDialog(
      title: Text(
        widget.product == null ? 'Novo artigo do Bar' : 'Editar artigo do Bar',
      ),
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
                    decoration: _decoration('Escolher embalagem habitual'),
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
                ),
              ]),
              _section(context, 'Geral', Icons.info_outline, [
                _field(_name, 'Nome *'),
                _field(_sku, 'Código / SKU'),
                _field(_category, 'Categoria'),
                _field(_supplier, 'Fornecedor'),
                _field(_description, 'Descrição', maxLines: 2),
              ]),
              _section(
                context,
                'Como compras e vendes',
                Icons.inventory_2_outlined,
                [
                  _field(
                    _purchaseUnit,
                    'Como compras este artigo?',
                    helper: 'Ex.: Caixa 33, Pack 12, Barril 50 L.',
                  ),
                  _field(
                    _consumptionUnit,
                    'Como é vendido / consumido?',
                    helper: 'Ex.: Garrafa 0,25 L ou Copo 0,25 L.',
                  ),
                  _field(
                    _conversion,
                    'Quantas unidades de consumo existem em cada compra? *',
                    numeric: true,
                  ),
                  if (conversion > 0 &&
                      _purchaseUnit.text.trim().isNotEmpty &&
                      _consumptionUnit.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Card(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.sync_alt_outlined),
                          title: Text(
                            'Cada ${_purchaseUnit.text} contém ${_number(conversion)} ${_consumptionUnit.text}',
                          ),
                        ),
                      ),
                    ),
                  _field(
                    _minimum,
                    'Avisar quando restarem quantas unidades?',
                    helper: 'Stock mínimo contado na unidade vendida/consumida.',
                    numeric: true,
                  ),
                ],
              ),
              _section(context, 'Valores', Icons.euro_outlined, [
                _field(
                  _purchaseCost,
                  'Quanto custa uma embalagem/compra (€)?',
                  helper: 'Ex.: preço total da caixa, pack ou barril.',
                  numeric: true,
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.calculate_outlined),
                    title: const Text('Custo calculado por unidade'),
                    subtitle: Text(
                      '${_money(unitCost)} por ${_consumptionUnit.text.isEmpty ? 'unidade' : _consumptionUnit.text}',
                    ),
                  ),
                ),
                _field(
                  _salePrice,
                  'Preço de venda por unidade (€)',
                  numeric: true,
                ),
                Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.trending_up_outlined),
                    title: const Text('Margem inicial estimada'),
                    subtitle: Text('${_money(margin)} por unidade'),
                  ),
                ),
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
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty ||
                _purchaseUnit.text.trim().isEmpty ||
                _consumptionUnit.text.trim().isEmpty ||
                _parse(_conversion.text) <= 0) {
              return;
            }
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
  const _PurchaseDialog({
    required this.product,
    required this.events,
    required this.accounts,
    required this.canSelectAccount,
  });

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> accounts;
  final bool canSelectAccount;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _units = TextEditingController(text: '1');
  late final TextEditingController _cost;
  final _notes = TextEditingController();
  String? _eventId;
  String? _accountId;
  String _payment = 'Dinheiro';
  bool _financial = true;

  @override
  void initState() {
    super.initState();
    _cost = TextEditingController(
      text: _number(widget.product['purchase_cost']),
    );
    if (widget.canSelectAccount && widget.accounts.isNotEmpty) {
      final preferred = widget.accounts.where(
        (a) => a['name']?.toString().toLowerCase() == 'caixa',
      );
      _accountId = (preferred.isNotEmpty ? preferred.first : widget.accounts.first)['id']
          ?.toString();
    }
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
    final purchase = widget.product['purchase_unit']?.toString() ?? 'embalagem';
    final consumption =
        widget.product['consumption_unit']?.toString() ?? 'unidade';
    final quantity = _parse(_units.text);
    final cost = _parse(_cost.text);

    return AlertDialog(
      title: Text('Entrada de stock · ${widget.product['name']}'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _units,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantos $purchase compraste?',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.sync_alt_outlined),
                  title: Text(
                    'Entram ${_number(quantity * conversion)} $consumption no stock',
                  ),
                  subtitle: Text(
                    'Custo total da compra: ${_money(quantity * cost)}',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Preço de 1 $purchase (€)',
                  helperText:
                      'Pode ser diferente da compra anterior. O custo médio será recalculado automaticamente.',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _EventField(
                events: widget.events,
                value: _eventId,
                onChanged: (value) => setState(() => _eventId = value),
              ),
              if (widget.canSelectAccount && widget.accounts.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AccountField(
                  accounts: widget.accounts,
                  value: _accountId,
                  onChanged: (value) => setState(() => _accountId = value),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _payment,
                decoration: const InputDecoration(
                  labelText: 'Pagamento',
                  border: OutlineInputBorder(),
                ),
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
                    setState(() => _payment = value ?? _payment),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _financial,
                onChanged: (value) => setState(() => _financial = value),
                title: const Text('Registar despesa na Tesouraria'),
                subtitle: widget.canSelectAccount
                    ? const Text('A despesa será lançada na conta selecionada.')
                    : const Text('Será usada a conta predefinida do Bar.'),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notas',
                  border: OutlineInputBorder(),
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
            final units = _parse(_units.text);
            final unitCost = _parse(_cost.text);
            if (units <= 0 || unitCost < 0) return;
            Navigator.pop(
              context,
              _PurchaseInput(
                purchaseUnits: units,
                costPerPurchaseUnit: unitCost,
                eventId: _eventId,
                accountId: _financial && widget.canSelectAccount
                    ? _accountId
                    : null,
                paymentMethod: _payment,
                notes: _notes.text,
                postFinancial: _financial,
              ),
            );
          },
          child: const Text('Registar entrada'),
        ),
      ],
    );
  }
}

class _ConsumptionDialog extends StatefulWidget {
  const _ConsumptionDialog({
    required this.product,
    required this.events,
    required this.accounts,
    required this.canSelectAccount,
    required this.operation,
  });

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> accounts;
  final bool canSelectAccount;
  final String operation;

  @override
  State<_ConsumptionDialog> createState() => _ConsumptionDialogState();
}

class _ConsumptionDialogState extends State<_ConsumptionDialog> {
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _price;
  final _notes = TextEditingController();
  String? _eventId;
  String? _accountId;
  String _payment = 'Dinheiro';
  bool _financial = true;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
      text: _number(widget.product['sale_price']),
    );
    _financial = widget.operation == 'sale';
    if (widget.canSelectAccount && widget.accounts.isNotEmpty) {
      final preferred = widget.accounts.where(
        (a) => a['name']?.toString().toLowerCase() == 'caixa',
      );
      _accountId = (preferred.isNotEmpty ? preferred.first : widget.accounts.first)['id']
          ?.toString();
    }
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
    final consumption =
        widget.product['consumption_unit']?.toString() ?? 'unid.';
    return AlertDialog(
      title: Text(
        '${_operationLabel(widget.operation)} · ${widget.product['name']}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stock atual: ${_number(widget.product['current_stock'])} $consumption',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Quantidade ($consumption)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              _EventField(
                events: widget.events,
                value: _eventId,
                onChanged: (value) => setState(() => _eventId = value),
              ),
              if (isSale) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Preço de venda unitário (€)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (widget.canSelectAccount && widget.accounts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _AccountField(
                    accounts: widget.accounts,
                    value: _accountId,
                    onChanged: (value) =>
                        setState(() => _accountId = value),
                  ),
                ],
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _payment,
                  decoration: const InputDecoration(
                    labelText: 'Pagamento',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Dinheiro',
                    'MB Way',
                    'Transferência bancária',
                    'Cartão consumo',
                  ]
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _payment = value ?? _payment),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _financial,
                  onChanged: (value) => setState(() => _financial = value),
                  title: const Text('Registar receita na Tesouraria'),
                  subtitle: const Text(
                    'Desativa para consumos já pagos por cartão/ficha.',
                  ),
                ),
              ],
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notas / motivo',
                  border: OutlineInputBorder(),
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
            if (quantity <= 0) return;
            Navigator.pop(
              context,
              _ConsumptionInput(
                quantity: quantity,
                eventId: _eventId,
                accountId: isSale && _financial && widget.canSelectAccount
                    ? _accountId
                    : null,
                unitPrice: isSale ? _parse(_price.text) : null,
                paymentMethod: isSale ? _payment : null,
                notes: _notes.text,
                postFinancial: isSale && _financial,
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
  const _EventField({
    required this.events,
    required this.value,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> events;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Evento (opcional)',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Sem evento associado'),
        ),
        ...events.map(
          (event) => DropdownMenuItem<String?>(
            value: event['id']?.toString(),
            child: Text(event['name']?.toString() ?? 'Evento'),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _AccountField extends StatelessWidget {
  const _AccountField({
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Conta / Fundo da Tesouraria',
        helperText: 'Escolhe onde este dinheiro entra ou sai.',
        border: OutlineInputBorder(),
      ),
      items: accounts
          .map(
            (account) => DropdownMenuItem<String>(
              value: account['id']?.toString(),
              child: Text(account['name']?.toString() ?? 'Conta'),
            ),
          )
          .toList(),
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

class _BarData {
  const _BarData({
    required this.products,
    required this.events,
    required this.operations,
    required this.accounts,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> operations;
  final List<Map<String, dynamic>> accounts;
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

  final String name;
  final String sku;
  final String category;
  final String description;
  final String supplier;
  final String purchaseUnit;
  final String consumptionUnit;
  final double unitsPerPurchase;
  final double purchaseCost;
  final double salePrice;
  final double minimumStock;
}

class _PurchaseInput {
  const _PurchaseInput({
    required this.purchaseUnits,
    required this.costPerPurchaseUnit,
    required this.eventId,
    required this.accountId,
    required this.paymentMethod,
    required this.notes,
    required this.postFinancial,
  });

  final double purchaseUnits;
  final double costPerPurchaseUnit;
  final String? eventId;
  final String? accountId;
  final String paymentMethod;
  final String notes;
  final bool postFinancial;
}

class _ConsumptionInput {
  const _ConsumptionInput({
    required this.quantity,
    required this.eventId,
    required this.accountId,
    required this.unitPrice,
    required this.paymentMethod,
    required this.notes,
    required this.postFinancial,
  });

  final double quantity;
  final String? eventId;
  final String? accountId;
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
