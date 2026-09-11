import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/bar_sales_repository.dart';

class BarSalesAdvancedScreen extends StatefulWidget {
  const BarSalesAdvancedScreen({super.key, this.onSaleCompleted});

  final VoidCallback? onSaleCompleted;

  @override
  State<BarSalesAdvancedScreen> createState() => _BarSalesAdvancedScreenState();
}

class _BarSalesAdvancedScreenState extends State<BarSalesAdvancedScreen> {
  final BarSalesRepository _repository = BarSalesRepository();
  final TextEditingController _customer = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _search = TextEditingController();

  late Future<_SaleData> _future;
  final Map<String, double> _optionQuantities = {};
  final Map<String, double> _presetQuantities = {};
  final List<_OtherSaleLine> _otherLines = [];
  final List<Map<String, dynamic>> _attachments = [];

  String _mode = 'manual';
  String _customerType = 'public';
  String? _memberId;
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
      _repository.members(),
    ]);
    return _SaleData(
      products: List<Map<String, dynamic>>.from(values[0] as List),
      presets: List<Map<String, dynamic>>.from(values[1] as List),
      events: List<Map<String, dynamic>>.from(values[2] as List),
      accounts: List<Map<String, dynamic>>.from(values[3] as List),
      members: List<Map<String, dynamic>>.from(values[4] as List),
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
      customerType: _customerType,
      memberId: _memberId,
      eventId: _eventId,
      notes: _notes.text,
    );
    if (mounted) {
      setState(() {
        _draftSaleId = id;
      });
    }
    return id;
  }

  Future<void> _pickCards(_SaleData data) async {
    if (!_repository.canManage || _busy) return;
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: true,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      setState(() {
        _busy = true;
      });
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
            applied += _applyOcrSuggestions(attachment, data);
          }
        }
      });
      if (_mode == 'ocr') {
        _message(
          applied > 0
              ? 'OCR sugeriu $applied linha(s). Confirma sempre a forma e a quantidade antes do pagamento.'
              : 'As fotos ficaram guardadas. O OCR não encontrou uma forma de venda segura; preenche manualmente.',
        );
      } else {
        _message('${uploaded.length} fotografia(s) associada(s) à venda.');
      }
    } catch (error) {
      _message(_friendly(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  int _applyOcrSuggestions(
    Map<String, dynamic> attachment,
    _SaleData data,
  ) {
    var applied = 0;
    for (final suggestion in BarSalesRepository.suggestions(attachment)) {
      final quantity = _double(suggestion['quantity']);
      if (quantity <= 0) continue;
      if (suggestion['kind'] == 'preset') {
        final id = suggestion['preset_id']?.toString();
        if (id == null || id.isEmpty) continue;
        _presetQuantities[id] = (_presetQuantities[id] ?? 0) + quantity;
        applied++;
        continue;
      }
      if (suggestion['kind'] != 'stock') continue;
      final productId = suggestion['product_id']?.toString();
      if (productId == null || productId.isEmpty) continue;
      Map<String, dynamic>? product;
      for (final row in data.products) {
        if (row['id']?.toString() == productId) {
          product = row;
          break;
        }
      }
      if (product == null) continue;
      final options = _saleOptions(product);
      Map<String, dynamic>? option;
      final suggestedOptionId = suggestion['sale_option_id']?.toString();
      if (suggestedOptionId != null && suggestedOptionId.isNotEmpty) {
        for (final row in options) {
          if (row['id']?.toString() == suggestedOptionId) {
            option = row;
            break;
          }
        }
      } else if (options.length == 1) {
        option = options.first;
      }
      if (option == null) continue;
      final optionId = option['id']?.toString() ?? '';
      if (optionId.isEmpty) continue;
      for (var i = 0; i < quantity.toInt(); i++) {
        if (!_canAddOption(product, option)) break;
        _optionQuantities[optionId] = (_optionQuantities[optionId] ?? 0) + 1;
        applied++;
      }
    }
    return applied;
  }

  Future<void> _addOther() async {
    if (!_repository.canManage) return;
    final result = await showDialog<_OtherSaleLine>(
      context: context,
      builder: (_) => const _OtherSaleLineDialog(),
    );
    if (result == null) return;
    setState(() {
      _otherLines.add(result);
    });
  }

  Future<void> _clearSale() async {
    if (_busy) return;
    final draft = _draftSaleId;
    setState(() {
      _busy = true;
    });
    try {
      if (draft != null) await _repository.cancelDraft(draft);
      if (!mounted) return;
      _resetLocal();
      _message('Venda limpa.');
    } catch (error) {
      _message(_friendly(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _resetLocal() {
    setState(() {
      _optionQuantities.clear();
      _presetQuantities.clear();
      _otherLines.clear();
      _attachments.clear();
      _draftSaleId = null;
      _eventId = null;
      _mode = 'manual';
      _customerType = 'public';
      _memberId = null;
      _customer.clear();
      _notes.clear();
      _search.clear();
    });
  }

  List<Map<String, dynamic>> _buildLines(_SaleData data) {
    final lines = <Map<String, dynamic>>[];
    for (final product in data.products) {
      for (final option in _saleOptions(product)) {
        final optionId = option['id']?.toString() ?? '';
        final quantity = _optionQuantities[optionId] ?? 0;
        if (quantity <= 0) continue;
        lines.add({
          'kind': 'stock',
          'product_id': product['id']?.toString(),
          'sale_option_id': optionId,
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

  double _price(Map<String, dynamic> option) => _customerType == 'member'
      ? _double(option['member_price'])
      : _double(option['public_price']);

  double _total(_SaleData data) {
    var total = 0.0;
    for (final product in data.products) {
      for (final option in _saleOptions(product)) {
        final id = option['id']?.toString() ?? '';
        total += (_optionQuantities[id] ?? 0) * _price(option);
      }
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

  double _usedStock(Map<String, dynamic> product) {
    var used = 0.0;
    for (final option in _saleOptions(product)) {
      final id = option['id']?.toString() ?? '';
      used += (_optionQuantities[id] ?? 0) * _double(option['stock_quantity']);
    }
    return used;
  }

  bool _canAddOption(
    Map<String, dynamic> product,
    Map<String, dynamic> option,
  ) {
    final available = _double(product['current_stock']);
    final after = _usedStock(product) + _double(option['stock_quantity']);
    return after <= available + 0.000001;
  }

  void _changeOptionQuantity(
    Map<String, dynamic> product,
    Map<String, dynamic> option,
    int delta,
  ) {
    final id = option['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final current = _optionQuantities[id] ?? 0;
    if (delta > 0 && !_canAddOption(product, option)) {
      _message('Stock insuficiente para adicionar mais ${option['name']}.');
      return;
    }
    final next = (current + delta).clamp(0, 99999).toDouble();
    setState(() {
      if (next <= 0) {
        _optionQuantities.remove(id);
      } else {
        _optionQuantities[id] = next;
      }
    });
  }

  void _changePresetQuantity(String id, int delta) {
    final current = _presetQuantities[id] ?? 0;
    final next = (current + delta).clamp(0, 99999).toDouble();
    setState(() {
      if (next <= 0) {
        _presetQuantities.remove(id);
      } else {
        _presetQuantities[id] = next;
      }
    });
  }

  Future<void> _complete(_SaleData data) async {
    if (!_repository.canManage || _busy) return;
    if (_customerType == 'member' &&
        _memberId == null &&
        _customer.text.trim().isEmpty) {
      _message('Seleciona um membro ou indica o nome da conta de grupo.');
      return;
    }
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

    setState(() {
      _busy = true;
    });
    try {
      final saleId = await _ensureDraft();
      final result = await _repository.completeSale(
        saleId: saleId,
        lines: lines,
        paymentMethod: payment.method,
        customerType: _customerType,
        memberId: _memberId,
        accountId: payment.accountId,
        customerLabel: _customer.text,
        eventId: _eventId,
        notes: _notes.text,
      );
      if (!mounted) return;
      final finalTotal = _double(result['total']);
      _resetLocal();
      setState(() {
        _future = _load();
      });
      widget.onSaleCompleted?.call();
      _message('Venda concluída · ${_money(finalTotal)}. Stock atualizado.');
    } catch (error) {
      _message(_friendly(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _selectMember(_SaleData data, String? memberId) {
    String? label;
    if (memberId != null) {
      for (final member in data.members) {
        if (member['id']?.toString() == memberId) {
          label = _memberLabel(member);
          break;
        }
      }
    }
    setState(() {
      _memberId = memberId;
      if (label != null) _customer.text = label;
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
        final products = data.products.where((product) {
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
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'public',
                        icon: Icon(Icons.public_outlined),
                        label: Text('Público'),
                      ),
                      ButtonSegment(
                        value: 'member',
                        icon: Icon(Icons.groups_outlined),
                        label: Text('Membro'),
                      ),
                    ],
                    selected: {_customerType},
                    onSelectionChanged: _draftSaleId != null
                        ? null
                        : (values) {
                            setState(() {
                              _customerType = values.first;
                              _memberId = null;
                              _customer.clear();
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  if (_customerType == 'member') ...[
                    DropdownButtonFormField<String?>(
                      initialValue: _memberId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Membro (opcional se for conta de grupo)',
                        prefixIcon: Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Conta de grupo / escolher manualmente'),
                        ),
                        ...data.members.map(
                          (member) => DropdownMenuItem<String?>(
                            value: member['id']?.toString(),
                            child: Text(_memberLabel(member)),
                          ),
                        ),
                      ],
                      onChanged: _draftSaleId != null
                          ? null
                          : (value) => _selectMember(data, value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _customer,
                    enabled: _draftSaleId == null,
                    decoration: InputDecoration(
                      labelText: _customerType == 'member'
                          ? 'Membro / nome da conta de grupo'
                          : 'Consumidor / conta (opcional)',
                      hintText: _customerType == 'member'
                          ? 'Ex.: Mesa dos membros, Israel'
                          : 'Ex.: Mesa 2, Visitante João',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                        : (values) => setState(() {
                              _mode = values.first;
                            }),
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
                    onChanged: _draftSaleId != null
                        ? null
                        : (value) => setState(() {
                              _eventId = value;
                            }),
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
                              const Expanded(
                                child: Text(
                                  'Cartões de consumo',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : () => _pickCards(data),
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('Fotos'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _mode == 'ocr'
                                ? 'O OCR sugere consumos. Formas ambíguas, como Shot/Dose, ficam sempre para confirmação manual.'
                                : 'Podes guardar várias fotografias do cartão como comprovativo.',
                          ),
                          if (_attachments.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final attachment in _attachments)
                                  Chip(
                                    avatar: const Icon(Icons.image_outlined, size: 18),
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
                          'Artigos',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      Chip(
                        avatar: Icon(
                          _customerType == 'member'
                              ? Icons.groups_outlined
                              : Icons.public_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _customerType == 'member' ? 'Preço membro' : 'Preço público',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Procurar bebida…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (products.isEmpty)
                    const Card(
                      child: ListTile(
                        leading: Icon(Icons.inventory_2_outlined),
                        title: Text('Sem artigos com stock para esta pesquisa.'),
                      ),
                    )
                  else
                    for (final product in products)
                      _ProductSaleCard(
                        product: product,
                        customerType: _customerType,
                        quantities: _optionQuantities,
                        usedStock: _usedStock(product),
                        canAdd: (option) => _canAddOption(product, option),
                        onMinus: (option) =>
                            _changeOptionQuantity(product, option, -1),
                        onPlus: (option) =>
                            _changeOptionQuantity(product, option, 1),
                      ),
                  if (data.presets.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Itens fixos sem stock',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final preset in data.presets)
                      _SimpleQuantityCard(
                        title: preset['name']?.toString() ?? 'Item',
                        subtitle: _money(preset['unit_price']),
                        quantity: _presetQuantities[preset['id']?.toString()] ?? 0,
                        lineTotal:
                            (_presetQuantities[preset['id']?.toString()] ?? 0) *
                                _double(preset['unit_price']),
                        onMinus: () => _changePresetQuantity(
                          preset['id'].toString(),
                          -1,
                        ),
                        onPlus: () => _changePresetQuantity(
                          preset['id'].toString(),
                          1,
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Outros',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addOther,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar Outro'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < _otherLines.length; i++)
                    Card(
                      child: ListTile(
                        title: Text(_otherLines[i].description),
                        subtitle: Text(
                          '${_number(_otherLines[i].quantity)} × ${_money(_otherLines[i].unitPrice)} = ${_money(_otherLines[i].quantity * _otherLines[i].unitPrice)}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remover',
                          onPressed: () => setState(() {
                            _otherLines.removeAt(i);
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 90),
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
                          _optionQuantities.isNotEmpty ||
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
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
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

class _ProductSaleCard extends StatelessWidget {
  const _ProductSaleCard({
    required this.product,
    required this.customerType,
    required this.quantities,
    required this.usedStock,
    required this.canAdd,
    required this.onMinus,
    required this.onPlus,
  });

  final Map<String, dynamic> product;
  final String customerType;
  final Map<String, double> quantities;
  final double usedStock;
  final bool Function(Map<String, dynamic> option) canAdd;
  final ValueChanged<Map<String, dynamic>> onMinus;
  final ValueChanged<Map<String, dynamic>> onPlus;

  @override
  Widget build(BuildContext context) {
    final options = _saleOptions(product);
    final unit = product['consumption_unit']?.toString() ?? 'unid.';
    final stock = _double(product['current_stock']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.local_bar_outlined)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['name']?.toString() ?? 'Artigo',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Stock ${_number(stock)} $unit · reservado nesta venda ${_number(usedStock)} $unit',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (options.isEmpty)
              const Text('Sem formas de venda configuradas.')
            else
              for (final option in options)
                _SaleOptionRow(
                  option: option,
                  stockUnit: unit,
                  price: customerType == 'member'
                      ? _double(option['member_price'])
                      : _double(option['public_price']),
                  quantity: quantities[option['id']?.toString()] ?? 0,
                  canAdd: canAdd(option),
                  onMinus: () => onMinus(option),
                  onPlus: () => onPlus(option),
                ),
          ],
        ),
      ),
    );
  }
}

class _SaleOptionRow extends StatelessWidget {
  const _SaleOptionRow({
    required this.option,
    required this.stockUnit,
    required this.price,
    required this.quantity,
    required this.canAdd,
    required this.onMinus,
    required this.onPlus,
  });

  final Map<String, dynamic> option;
  final String stockUnit;
  final double price;
  final double quantity;
  final bool canAdd;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final stockPerSale = _double(option['stock_quantity']);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option['name']?.toString() ?? 'Forma',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text('${_number(stockPerSale)} $stockUnit · ${_money(price)}'),
                    if (quantity > 0)
                      Text('Subtotal ${_money(quantity * price)}'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Diminuir',
                onPressed: quantity > 0 ? onMinus : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  _number(quantity),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Adicionar',
                onPressed: canAdd ? onPlus : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleQuantityCard extends StatelessWidget {
  const _SimpleQuantityCard({
    required this.title,
    required this.subtitle,
    required this.quantity,
    required this.lineTotal,
    required this.onMinus,
    required this.onPlus,
  });

  final String title;
  final String subtitle;
  final double quantity;
  final double lineTotal;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          quantity > 0 ? '$subtitle · Subtotal ${_money(lineTotal)}' : subtitle,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: quantity > 0 ? onMinus : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 34,
              child: Text(_number(quantity), textAlign: TextAlign.center),
            ),
            IconButton(
              onPressed: onPlus,
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
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
              onChanged: (value) => setState(() {
                _method = value ?? _method;
              }),
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
                onChanged: (value) => setState(() {
                  _accountId = value;
                }),
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
    required this.members,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> presets;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> members;
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

List<Map<String, dynamic>> _saleOptions(Map<String, dynamic> product) {
  final raw = product['sale_options'] ?? product['bar_product_sale_options'];
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .where((row) => row['active'] != false)
      .toList();
}

String _memberLabel(Map<String, dynamic> member) {
  final nickname = member['nickname']?.toString().trim() ?? '';
  final fullName = member['full_name']?.toString().trim() ?? '';
  final number = member['member_number']?.toString() ?? '';
  final name = nickname.isNotEmpty ? '$nickname · $fullName' : fullName;
  return number.isEmpty ? name : '#$number · $name';
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

String _friendly(Object error) => error
    .toString()
    .replaceFirst('StateError: ', '')
    .replaceFirst('Invalid argument(s): ', '')
    .replaceFirst('PostgrestException(message: ', '');
