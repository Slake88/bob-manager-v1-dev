import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/bar_repository.dart';
import '../repositories/financial_ocr_repository.dart';
import 'bar_ocr_review_screen.dart';
import 'bar_product_editor_dialog.dart';
import 'bar_sales_advanced_screen.dart';

class BarScreenV4 extends StatefulWidget {
  const BarScreenV4({super.key});

  @override
  State<BarScreenV4> createState() => _BarScreenV4State();
}

class _BarScreenV4State extends State<BarScreenV4> {
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
    setState(() {
      _reload();
    });
    await _future;
  }

  void _refreshAfterSale() {
    if (!mounted) return;
    setState(() {
      _reload();
    });
  }

  void _error(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_friendly(error))),
    );
  }

  Future<void> _editProduct(
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> accounts, [
    Map<String, dynamic>? product,
  ]) async {
    final result = await showDialog<BarProductInput>(
      context: context,
      builder: (_) => BarProductEditorDialog(product: product),
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
        consumptionUnit: result.stockUnit,
        unitsPerPurchase: result.unitsPerPurchase,
        purchaseCost: result.purchaseCost,
        minimumStock: result.minimumStock,
        saleOptions: result.saleOptions,
      );
      if (!mounted) return;
      setState(() {
        _reload();
      });

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
      if (mounted) {
        setState(() {
          _reload();
        });
      }
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
              'Falta configurar os serviços OCR do Supabase. O documento ficou guardado e pode ser analisado posteriormente.',
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
      if (changed == true && mounted) {
        setState(() {
          _reload();
        });
      }
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
        notes: result.notes,
      );
      if (mounted) {
        setState(() {
          _reload();
        });
      }
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
              (product) =>
                  _double(product['current_stock']) <=
                  _double(product['minimum_stock']),
            )
            .length;
        final stockValue = data.products.fold<double>(
          0,
          (sum, product) =>
              sum +
              _double(product['current_stock']) * _double(product['cost']),
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
                            label: 'Artigos',
                            value: '${data.products.length}',
                            icon: Icons.local_bar_outlined,
                          ),
                          _Metric(
                            label: 'Stock baixo',
                            value: '$lowStock',
                            icon: Icons.warning_amber_outlined,
                          ),
                          _Metric(
                            label: 'Valor teórico',
                            value: _money(stockValue),
                            icon: Icons.euro_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_canManage) ...[
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: const Text('Novo artigo do BAR'),
                            subtitle: const Text(
                              'Define embalagem, stock base, formas de venda, preço público e preço de membro.',
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
                            title: const Text('Registar compra por talão / fatura'),
                            subtitle: const Text(
                              'O OCR propõe os dados e só atualiza stock e Tesouraria depois da confirmação.',
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
                            title: Text('Ainda não existem artigos no BAR.'),
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
                BarSalesAdvancedScreen(onSaleCompleted: _refreshAfterSale),
                RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      const Card(
                        child: ListTile(
                          leading: Icon(Icons.verified_user_outlined),
                          title: Text('Rastreabilidade'),
                          subtitle: Text(
                            'Cada movimento mostra o utilizador que o registou e a data/hora. Esta regra será aplicada aos restantes módulos durante a estabilização RC1.',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (data.operations.isEmpty)
                        const Card(
                          child: ListTile(
                            leading: Icon(Icons.history_outlined),
                            title: Text('Ainda não existem movimentos de BAR.'),
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
    final averageCost = _double(product['cost']);
    final low = stock <= minimum;
    final stockUnit = product['consumption_unit']?.toString() ?? 'unid.';
    final purchaseUnit = product['purchase_unit']?.toString() ?? 'embalagem';
    final options = _saleOptions(product);

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
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(product['category']?.toString() ?? 'Bebidas'),
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
                        child: Text('Editar artigo e preços'),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text('${_number(stock)} $stockUnit'),
                ),
                Chip(
                  avatar: const Icon(Icons.sync_alt_outlined, size: 18),
                  label: Text('1 $purchaseUnit = ${_number(conversion)} $stockUnit'),
                ),
                Chip(
                  avatar: const Icon(Icons.calculate_outlined, size: 18),
                  label: Text('Custo base ${_money(averageCost)}'),
                ),
              ],
            ),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Formas de venda',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    Chip(
                      avatar: const Icon(Icons.point_of_sale_outlined, size: 18),
                      label: Text(
                        '${option['name']} · ${_number(option['stock_quantity'])} $stockUnit · Público ${_money(option['public_price'])} · Membro ${_money(option['member_price'])}',
                      ),
                    ),
                ],
              ),
            ],
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
    final actor = operation['actor'];
    final type = operation['operation_type']?.toString() ?? '';
    final productName = product is Map
        ? product['name']?.toString() ?? 'Artigo'
        : 'Artigo';
    final unit = product is Map
        ? product['consumption_unit']?.toString() ?? 'unid.'
        : 'unid.';
    final eventName = event is Map ? event['name']?.toString() : null;
    final actorName = actor is Map
        ? (actor['full_name']?.toString().trim().isNotEmpty == true
            ? actor['full_name']?.toString()
            : actor['email']?.toString())
        : operation['actor_label']?.toString();
    String? accountName;
    if (transaction is Map) {
      final account = transaction['treasury_accounts'];
      if (account is Map) accountName = account['name']?.toString();
    }
    final created = DateTime.tryParse(
      operation['created_at']?.toString() ?? '',
    )?.toLocal();
    final saleOption = operation['sale_option_name']?.toString();
    final customerType = operation['customer_type']?.toString();

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(_operationIcon(type))),
        title: Text(
          '${_operationLabel(type)} · $productName${saleOption != null && saleOption.isNotEmpty ? ' · $saleOption' : ''}',
        ),
        subtitle: Text(
          [
            '${_number(operation['consumption_quantity'])} $unit',
            if (_double(operation['total_amount']) > 0)
              _money(operation['total_amount']),
            if (customerType == 'member') 'Preço: Membro',
            if (customerType == 'public') 'Preço: Público',
            if (accountName != null && accountName.isNotEmpty)
              'Conta: $accountName',
            if (eventName != null && eventName.isNotEmpty) eventName,
            if (actorName != null && actorName.isNotEmpty)
              'Registado por: $actorName',
            if (created != null)
              DateFormat('dd/MM/yyyy HH:mm:ss').format(created),
            operation['notes']?.toString(),
          ].whereType<String>().where((value) => value.isNotEmpty).join(' · '),
        ),
      ),
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
  final TextEditingController _units = TextEditingController(text: '1');
  late final TextEditingController _cost;
  final TextEditingController _notes = TextEditingController();
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
        (account) => account['name']?.toString().toLowerCase() == 'caixa',
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
    final stockUnit = widget.product['consumption_unit']?.toString() ?? 'unidade';
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Quantos $purchase compraste?',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.sync_alt_outlined),
                  title: Text(
                    'Entram ${_number(quantity * conversion)} $stockUnit no stock',
                  ),
                  subtitle: Text('Custo total: ${_money(quantity * cost)}'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cost,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Preço de 1 $purchase (€)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _EventField(
                events: widget.events,
                value: _eventId,
                onChanged: (value) => setState(() {
                  _eventId = value;
                }),
              ),
              if (widget.canSelectAccount && widget.accounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                _AccountField(
                  accounts: widget.accounts,
                  value: _accountId,
                  onChanged: (value) => setState(() {
                    _accountId = value;
                  }),
                ),
              ],
              const SizedBox(height: 12),
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
                onChanged: (value) => setState(() {
                  _payment = value ?? _payment;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _financial,
                onChanged: (value) => setState(() {
                  _financial = value;
                }),
                title: const Text('Registar despesa na Tesouraria'),
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
    required this.operation,
  });

  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> events;
  final String operation;

  @override
  State<_ConsumptionDialog> createState() => _ConsumptionDialogState();
}

class _ConsumptionDialogState extends State<_ConsumptionDialog> {
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _notes = TextEditingController();
  String? _eventId;

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockUnit = widget.product['consumption_unit']?.toString() ?? 'unid.';
    return AlertDialog(
      title: Text('${_operationLabel(widget.operation)} · ${widget.product['name']}'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Stock atual: ${_number(widget.product['current_stock'])} $stockUnit',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantidade ($stockUnit)',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _EventField(
              events: widget.events,
              value: _eventId,
              onChanged: (value) => setState(() {
                _eventId = value;
              }),
            ),
            const SizedBox(height: 12),
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
                notes: _notes.text,
              ),
            );
          },
          child: const Text('Registar'),
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
          child: Text('Sem evento'),
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
        labelText: 'Conta da Tesouraria',
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
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
    required this.notes,
  });

  final double quantity;
  final String? eventId;
  final String notes;
}

List<Map<String, dynamic>> _saleOptions(Map<String, dynamic> product) {
  final raw = product['sale_options'] ?? product['bar_product_sale_options'];
  if (raw is! List) return const [];
  final options = raw
      .whereType<Map>()
      .map((value) => Map<String, dynamic>.from(value))
      .where((value) => value['active'] != false)
      .toList();
  options.sort((a, b) {
    final aSort = (a['sort_order'] as num?)?.toInt() ?? 0;
    final bSort = (b['sort_order'] as num?)?.toInt() ?? 0;
    return aSort.compareTo(bSort);
  });
  return options;
}

String _operationLabel(String value) => switch (value) {
      'purchase' => 'Entrada / compra',
      'sale' => 'Venda',
      'offer' => 'Oferta',
      'internal' => 'Consumo interno',
      'waste' => 'Quebra / desperdício',
      'adjustment_in' => 'Ajuste positivo',
      'adjustment_out' => 'Ajuste negativo',
      _ => value,
    };

IconData _operationIcon(String value) => switch (value) {
      'purchase' => Icons.add_box_outlined,
      'sale' => Icons.point_of_sale_outlined,
      'offer' => Icons.card_giftcard_outlined,
      'internal' => Icons.local_cafe_outlined,
      'waste' => Icons.delete_outline,
      'adjustment_in' => Icons.add_circle_outline,
      'adjustment_out' => Icons.remove_circle_outline,
      _ => Icons.swap_vert,
    };

double _double(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;

double _parse(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

String _number(Object? value) {
  final number = _double(value);
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toStringAsFixed(2).replaceAll('.', ',');
}

String _money(Object? value) =>
    NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(_double(value));

String _friendly(Object error) => error
    .toString()
    .replaceFirst('StateError: ', '')
    .replaceFirst('Invalid argument(s): ', '');
