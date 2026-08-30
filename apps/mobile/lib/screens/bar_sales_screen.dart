import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/bar_sales_repository.dart';

class BarSalesScreen extends StatefulWidget {
  const BarSalesScreen({super.key});

  @override
  State<BarSalesScreen> createState() => _BarSalesScreenState();
}

class _BarSalesScreenState extends State<BarSalesScreen> {
  final BarSalesRepository _repository = BarSalesRepository();
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _search = TextEditingController();

  late Future<_SaleData> _future;
  final Map<String, double> _productQuantities = {};
  final Map<String, double> _presetQuantities = {};
  final List<_OtherSaleLine> _otherLines = [];
  final List<Map<String, dynamic>> _attachments = [];

  String _mode = 'manual';
  String? _eventId;
  String? _draftSaleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _customer.dispose();
    _notes.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<_SaleData> _load() async {
    final values = await Future.wait<dynamic>([
      _repository.products(),
      _repository.presets(),
      _repository.events(),
      _repository.treasuryAccounts(),
    ]);
    return _SaleData(
      products: List<Map<String, dynamic>>.from(values[0] as List),
      presets: List<Map<String, dynamic>>.from(values[1] as List),
      events: List<Map<String, dynamic>>.from(values[2] as List),
      accounts: List<Map<String, dynamic>>.from(values[3] as List),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<String> _ensureDraft() async {
    final existing = _draftSaleId;
    if (existing != null) return existing;
    final id = await _repository.createDraft(
      sourceMode: _mode,
      customerLabel: _customer.text,
      eventId: _eventId,
      notes: _notes.text,
    );
    if (mounted) setState(() => _draftSaleId = id);
    return id;
  }

  Future<void> _pickCards() async {
    if (!_repository.canManage || _busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      setState(() => _busy = true);
      final saleId = await _ensureDraft();
      final uploaded = await _repository.uploadConsumptionCards(
        saleId: saleId,
        files: picked.files,
        runOcr: _mode == 'ocr',
      );
      if (!mounted) return;

      var applied = 0;
      setState(() {
        _attachments.addAll(uploaded);
        if (_mode == 'ocr') {
          for (final attachment in uploaded) {
            applied += _applyOcrSuggestions(attachment);
          }
        }
      });
      if (_mode == 'ocr') {
        _message(
          applied > 0
              ? 'OCR sugeriu $applied linha(s). Confirma as quantidades antes do pagamento.'
              : 'As fotos ficaram guardadas. O OCR não encontrou quantidades seguras; preenche a venda manualmente.',
        );
      } else {
        _message('${uploaded.length} fotografia(s) associada(s) à venda.');
      }
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _applyOcrSuggestions(Map<String, dynamic> attachment) {
    var applied = 0;
    for (final suggestion in BarSalesRepository.suggestions(attachment)) {
      final quantity = _double(suggestion['quantity']);
      if (quantity <= 0) continue;
      final kind = suggestion['kind']?.toString();
      if (kind == 'stock') {
        final id = suggestion['product_id']?.toString();
        if (id == null || id.isEmpty) continue;
        _productQuantities[id] = (_productQuantities[id] ?? 0) + quantity;
        applied++;
      } else if (kind == 'preset') {
        final id = suggestion['preset_id']?.toString();
        if (id == null || id.isEmpty) continue;
        _presetQuantities[id] = (_presetQuantities[id] ?? 0) + quantity;
        applied++;
      }
    }
    return applied;
  }

  Future<void> _editPreset(Map<String, dynamic> preset) async {
    if (!_repository.canManage) return;
    final controller = TextEditingController(
      text: _number(preset['unit_price']),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Preço · ${preset['name'] ?? 'Item fixo'}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Preço unitário (€)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final price = _parse(controller.text);
              if (price < 0) return;
              Navigator.pop(dialogContext, price);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    try {
      await _repository.updatePresetPrice(
        presetId: preset['id'].toString(),
        price: result,
      );
      if (!mounted) return;
      setState(() => _future = _load());
      _message('Preço atualizado.');
    } catch (error) {
      _message(error.toString());
    }
  }

  Future<void> _addOther() async {
    if (!_repository.canManage) return;
    final result = await showDialog<_OtherSaleLine>(
      context: context,
      builder: (_) => const _OtherSaleLineDialog(),
    );
    if (result == null) return;
    setState(() => _otherLines.add(result));
  }

  Future<void> _clearSale() async {
    if (_busy) return;
    final draft = _draftSaleId;
    setState(() => _busy = true);
    try {
      if (draft != null) await _repository.cancelDraft(draft);
      if (!mounted) return;
      _resetLocal();
      _message('Venda limpa.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetLocal() {
    setState(() {
      _productQuantities.clear();
      _presetQuantities.clear();
      _otherLines.clear();
      _attachments.clear();
      _draftSaleId = null;
      _eventId = null;
      _mode = 'manual';
      _customer.clear();
      _notes.clear();
      _search.clear();
    });
  }

  List<Map<String, dynamic>> _buildLines(_SaleData data) {
    final lines = <Map<String, dynamic>>[];
    for (final product in data.products) {
      final id = product['id']?.toString() ?? '';
      final quantity = _productQuantities[id] ?? 0;
      if (quantity > 0) {
        lines.add({
          'kind': 'stock',
          'product_id': id,
          'quantity': quantity,
        });
      }
    }
    for (final preset in data.presets) {
      final id = preset['id']?.toString() ?? '';
      final quantity = _presetQuantities[id] ?? 0;
      if (quantity > 0) {
        lines.add({
          'kind': 'preset',
          'preset_id': id,
          'quantity': quantity,
        });
      }
    }
    for (final line in _otherLines) {
      lines.add({
        'kind': 'other',
        'description': line.description,
        'quantity': line.quantity,
        'unit_price': line.unitPrice,
      });
    }
    return lines;
  }

  double _total(_SaleData data) {
    var total = 0.0;
    for (final product in data.products) {
      final id = product['id']?.toString() ?? '';
      total += (_productQuantities[id] ?? 0) * _double(product['sale_price']);
    }
    for (final preset in data.presets) {
      final id = preset['id']?.toString() ?? '';
      total += (_presetQuantities[id] ?? 0) * _double(preset['unit_price']);
    }
    for (final line in _otherLines) {
      total += line.quantity * line.unitPrice;
    }
    return total;
  }

  Future<void> _complete(_SaleData data) async {
    if (!_repository.canManage || _busy) return;
    final lines = _buildLines(data);
    if (lines.isEmpty) {
      _message('Adiciona pelo menos um artigo à venda.');
      return;
    }
    final total = _total(data);
    if (total <= 0) {
      _message('O total da venda tem de ser superior a zero.');
      return;
    }

    final payment = await showDialog<_PaymentChoice>(
      context: context,
      builder: (_) => _PaymentDialog(
        total: total,
        accounts: data.accounts,
        canSelectAccount: _repository.canSelectAccount,
      ),
    );
    if (payment == null) return;

    setState(() => _busy = true);
    try {
      final saleId = await _ensureDraft();
      final result = await _repository.completeSale(
        saleId: saleId,
        lines: lines,
        paymentMethod: payment.method,
        accountId: payment.accountId,
        customerLabel: _customer.text,
        eventId: _eventId,
        notes: _notes.text,
      );
      if (!mounted) return;
      final finalTotal = _double(result['total']);
      _resetLocal();
      setState(() => _future = _load());
      _message('Venda concluída · ${_money(finalTotal)}. Stock atualizado.');
    } catch (error) {
      _message(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeProductQuantity(
    Map<String, dynamic> product,
    double delta,
  ) {
    final id = product['id']?.toString() ?? '';
    final available = _double(product['current_stock']);
    final current = _productQuantities[id] ?? 0;
    final next = (current + delta).clamp(0, available).toDouble();
    setState(() {
      if (next <= 0) {
        _productQuantities.remove(id);
      } else {
        _productQuantities[id] = next;
      }
    });
  }

  void _changePresetQuantity(String id, double delta) {
    final current = _presetQuantities[id] ?? 0;
    final next = (current + delta).clamp(0, 9999).toDouble();
    setState(() {
      if (next <= 0) {
        _presetQuantities.remove(id);
      } else {
        _presetQuantities[id] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_repository.canManage) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tens acesso de consulta ao BAR, mas não tens permissão para registar vendas.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return FutureBuilder<_SaleData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final total = _total(data);
        final query = _search.text.trim().toLowerCase();
        final availableProducts = data.products.where((product) {
          if (_double(product['current_stock']) <= 0) return false;
          if (query.isEmpty) return true;
          return (product['name']?.toString().toLowerCase() ?? '').contains(query) ||
              (product['category']?.toString().toLowerCase() ?? '').contains(query);
        }).toList();

        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text(
                    'Nova venda',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Regista rapidamente os consumos, confirma o pagamento e o stock é abatido automaticamente.',
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'manual',
                        icon: Icon(Icons.touch_app_outlined),
                        label: Text('Manual'),
                      ),
                      ButtonSegment(
                        value: 'ocr',
                        icon: Icon(Icons.document_scanner_outlined),
                        label: Text('Cartão OCR'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _draftSaleId != null
                        ? null
                        : (values) => setState(() => _mode = values.first),
                  ),
                  if (_draftSaleId != null) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'O modo fica fixo depois de associares a primeira fotografia.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customer,
                    decoration: const InputDecoration(
                      labelText: 'Consumidor / conta de grupo',
                      hintText: 'Ex.: Israel, Mesa 2, Grupo Road Captains',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _eventId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Evento (opcional)',
                      prefixIcon: Icon(Icons.event_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sem evento associado'),
                      ),
                      ...data.events.map(
                        (event) => DropdownMenuItem<String?>(
                          value: event['id']?.toString(),
                          child: Text(event['name']?.toString() ?? 'Evento'),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _eventId = value),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.photo_camera_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Cartões de consumo',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _pickCards,
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('Fotos'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _mode == 'ocr'
                                ? 'Podes selecionar várias fotos. O OCR apenas sugere artigos/quantidades; confirma sempre antes de pagar.'
                                : 'Mesmo na venda manual podes guardar várias fotos do cartão como comprovativo.',
                          ),
                          if (_attachments.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final attachment in _attachments)
                                  Chip(
                                    avatar: Icon(
                                      attachment['ocr_status'] == 'ready'
                                          ? Icons.auto_awesome_outlined
                                          : Icons.image_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      attachment['original_file_name']?.toString() ??
                                          'Fotografia',
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Artigos em stock',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text('${availableProducts.length} disponíveis'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Procurar cerveja, água, refrigerante…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (availableProducts.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('Sem artigos com stock para esta pesquisa.'),
                      ),
                    )
                  else
                    for (final product in availableProducts)
                      _QuantityCard(
                        title: product['name']?.toString() ?? 'Artigo',
                        subtitle:
                            'Stock ${_number(product['current_stock'])} ${product['consumption_unit'] ?? 'unid.'} · ${_money(product['sale_price'])}',
                        quantity: _productQuantities[product['id']?.toString()] ?? 0,
                        lineTotal:
                            (_productQuantities[product['id']?.toString()] ?? 0) *
                                _double(product['sale_price']),
                        onMinus: () => _changeProductQuantity(product, -1),
                        onPlus: () => _changeProductQuantity(product, 1),
                        canPlus:
                            (_productQuantities[product['id']?.toString()] ?? 0) <
                                _double(product['current_stock']),
                      ),
                  if (data.presets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Itens fixos sem stock',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    for (final preset in data.presets)
                      _QuantityCard(
                        title: preset['name']?.toString() ?? 'Item',
                        subtitle: _double(preset['unit_price']) > 0
                            ? _money(preset['unit_price'])
                            : 'Preço ainda por definir',
                        quantity: _presetQuantities[preset['id']?.toString()] ?? 0,
                        lineTotal:
                            (_presetQuantities[preset['id']?.toString()] ?? 0) *
                                _double(preset['unit_price']),
                        onMinus: () => _changePresetQuantity(
                          preset['id'].toString(),
                          -1,
                        ),
                        onPlus: _double(preset['unit_price']) > 0
                            ? () => _changePresetQuantity(
                                  preset['id'].toString(),
                                  1,
                                )
                            : null,
                        canPlus: _double(preset['unit_price']) > 0,
                        trailing: IconButton(
                          tooltip: 'Alterar preço',
                          onPressed: () => _editPreset(preset),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Outros',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addOther,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar Outro'),
                      ),
                    ],
                  ),
                  if (_otherLines.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (var i = 0; i < _otherLines.length; i++)
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.add_shopping_cart_outlined),
                          ),
                          title: Text(_otherLines[i].description),
                          subtitle: Text(
                            '${_number(_otherLines[i].quantity)} × ${_money(_otherLines[i].unitPrice)} = ${_money(_otherLines[i].quantity * _otherLines[i].unitPrice)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remover',
                            onPressed: () =>
                                setState(() => _otherLines.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Material(
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      if (_draftSaleId != null ||
                          _productQuantities.isNotEmpty ||
                          _presetQuantities.isNotEmpty ||
                          _otherLines.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpar venda',
                          onPressed: _busy ? null : _clearSale,
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total a pagar'),
                            Text(
                              _money(total),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy || total <= 0 ? null : () => _complete(data),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.payments_outlined),
                        label: const Text('Pagamento'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _QuantityCard extends StatelessWidget {
  const _QuantityCard({
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.lineTotal,
    required this.onMinus,
    required this.onPlus,
    required this.canPlus,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final double quantity;
  final double lineTotal;
  final VoidCallback onMinus;
  final VoidCallback? onPlus;
  final bool canPlus;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(subtitle),
                  if (quantity > 0)
                    Text(
                      'Subtotal ${_money(lineTotal)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            IconButton(
              tooltip: 'Diminuir',
              onPressed: quantity > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 36,
              child: Text(
                _number(quantity),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: 'Adicionar',
              onPressed: canPlus ? onPlus : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _OtherSaleLineDialog extends StatefulWidget {
  const _OtherSaleLineDialog();

  @override
  State<_OtherSaleLineDialog> createState() => _OtherSaleLineDialogState();
}

class _OtherSaleLineDialogState extends State<_OtherSaleLineDialog> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _price = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Outro'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _description,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex.: Refeição especial',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantidade',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Preço unitário (€)',
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
            final description = _description.text.trim();
            final quantity = _parse(_quantity.text);
            final price = _parse(_price.text);
            if (description.isEmpty || quantity <= 0 || price < 0) return;
            Navigator.pop(
              context,
              _OtherSaleLine(
                description: description,
                quantity: quantity,
                unitPrice: price,
              ),
            );
          },
          child: const Text('Adicionar'),
        ),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.total,
    required this.accounts,
    required this.canSelectAccount,
  });

  final double total;
  final List<Map<String, dynamic>> accounts;
  final bool canSelectAccount;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _method = 'Dinheiro';
  String? _accountId;

  @override
  void initState() {
    super.initState();
    if (widget.canSelectAccount && widget.accounts.isNotEmpty) {
      final caixa = widget.accounts.where(
        (account) => account['name']?.toString().toLowerCase() == 'caixa',
      );
      _accountId = (caixa.isNotEmpty ? caixa.first : widget.accounts.first)['id']
          ?.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Concluir pagamento'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.euro_outlined),
                title: const Text('Total a pagar'),
                subtitle: Text(
                  _money(widget.total),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Método de pagamento',
                border: OutlineInputBorder(),
              ),
              items: const [
                'Dinheiro',
                'MB Way',
                'Transferência bancária',
                'Cartão',
                'Outro',
              ]
                  .map(
                    (method) => DropdownMenuItem(
                      value: method,
                      child: Text(method),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _method = value ?? _method),
            ),
            if (widget.canSelectAccount && widget.accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta / fundo da Tesouraria',
                  border: OutlineInputBorder(),
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account['id']?.toString(),
                        child: Text(account['name']?.toString() ?? 'Conta'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _accountId = value),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Voltar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(
            context,
            _PaymentChoice(method: _method, accountId: _accountId),
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Confirmar venda'),
        ),
      ],
    );
  }
}

class _SaleData {
  const _SaleData({
    required this.products,
    required this.presets,
    required this.events,
    required this.accounts,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> presets;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> accounts;
}

class _OtherSaleLine {
  const _OtherSaleLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  final String description;
  final double quantity;
  final double unitPrice;
}

class _PaymentChoice {
  const _PaymentChoice({required this.method, required this.accountId});

  final String method;
  final String? accountId;
}

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
