import 'package:flutter/material.dart';

import '../repositories/financial_ocr_repository.dart';

class BarOcrReviewScreen extends StatefulWidget {
  const BarOcrReviewScreen({
    super.key,
    required this.job,
    required this.products,
    required this.events,
    required this.accounts,
    required this.canSelectAccount,
  });

  final Map<String, dynamic> job;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> accounts;
  final bool canSelectAccount;

  @override
  State<BarOcrReviewScreen> createState() => _BarOcrReviewScreenState();
}

class _BarOcrReviewScreenState extends State<BarOcrReviewScreen> {
  final FinancialOcrRepository _repository = FinancialOcrRepository();
  final TextEditingController _total = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  final List<_OcrBarLine> _lines = [];
  String? _eventId;
  String? _accountId;
  String _paymentMethod = 'Dinheiro';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _total.text = _numberText(widget.job['total']);
    final ocrLines = FinancialOcrRepository.lineItems(widget.job);
    for (final source in ocrLines) {
      final description = source['description']?.toString() ?? '';
      final productId = FinancialOcrRepository.suggestProductId(
        description,
        widget.products,
      );
      Map<String, dynamic>? product;
      if (productId != null) {
        for (final candidate in widget.products) {
          if (candidate['id']?.toString() == productId) {
            product = candidate;
            break;
          }
        }
      }
      final quantity = FinancialOcrRepository.number(source['quantity']);
      final lineTotal = FinancialOcrRepository.number(source['line_total']);
      var unitPrice = FinancialOcrRepository.number(source['unit_price']);
      if ((unitPrice == null || unitPrice <= 0) &&
          quantity != null &&
          quantity > 0 &&
          lineTotal != null) {
        unitPrice = lineTotal / quantity;
      }
      if ((unitPrice == null || unitPrice <= 0) && product != null) {
        unitPrice = FinancialOcrRepository.number(product['purchase_cost']);
      }
      _lines.add(
        _OcrBarLine(
          source: source,
          productId: productId,
          included: productId != null,
          purchaseUnits: TextEditingController(
            text: quantity != null && quantity > 0 ? _numberText(quantity) : '1',
          ),
          unitPrice: TextEditingController(
            text: unitPrice != null ? _numberText(unitPrice) : '',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _total.dispose();
    _notes.dispose();
    for (final line in _lines) {
      line.purchaseUnits.dispose();
      line.unitPrice.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    final selected = <Map<String, dynamic>>[];
    for (final line in _lines.where((item) => item.included)) {
      if (line.productId == null || line.productId!.isEmpty) {
        throw ArgumentError('Associa um artigo do Bar a todas as linhas selecionadas.');
      }
      final quantity = _parse(line.purchaseUnits.text);
      final unitPrice = _parse(line.unitPrice.text);
      if (quantity <= 0) {
        throw ArgumentError('A quantidade de compra deve ser superior a zero.');
      }
      if (unitPrice < 0) {
        throw ArgumentError('O preço de compra não pode ser negativo.');
      }
      selected.add({
        'product_id': line.productId,
        'purchase_units': quantity,
        'unit_price': unitPrice,
        'description': line.source['description']?.toString() ?? '',
      });
    }
    if (selected.isEmpty) {
      throw ArgumentError('Seleciona pelo menos uma linha do talão.');
    }
    final total = _parse(_total.text);
    if (total <= 0) throw ArgumentError('Confirma o total do documento.');

    final lineTotal = selected.fold<double>(
      0,
      (sum, line) =>
          sum +
          (line['purchase_units'] as double) *
              (line['unit_price'] as double),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar compra do Bar'),
        content: Text(
          '${selected.length} linha(s) vão atualizar o stock.\n'
          'Será criada uma única despesa de ${_money(total)} na Tesouraria.\n\n'
          'Total das linhas de stock: ${_money(lineTotal)}\n'
          'Total do documento: ${_money(total)}\n\n'
          'Confirma estes dados depois de verificares o talão original?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await _repository.saveReview(
        job: widget.job,
        supplierName: widget.job['supplier_name']?.toString() ?? '',
        supplierTaxId: widget.job['supplier_tax_id']?.toString() ?? '',
        documentNumber: widget.job['document_number']?.toString() ?? '',
        documentDate: DateTime.tryParse(widget.job['document_date']?.toString() ?? ''),
        currency: widget.job['currency']?.toString() ?? 'EUR',
        subtotal: FinancialOcrRepository.number(widget.job['subtotal']),
        taxTotal: FinancialOcrRepository.number(widget.job['tax_total']),
        total: total,
        paymentMethod: _paymentMethod,
        lineItems: FinancialOcrRepository.lineItems(widget.job),
        warnings: FinancialOcrRepository.warnings(widget.job),
      );
      await _repository.confirmBarPurchase(
        jobId: widget.job['id'].toString(),
        lines: selected,
        eventId: _eventId,
        accountId: _accountId,
        paymentMethod: _paymentMethod,
        total: total,
        notes: _notes.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compra OCR confirmada: stock e Tesouraria atualizados.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final warnings = FinancialOcrRepository.warnings(widget.job);
    final confidence = FinancialOcrRepository.number(widget.job['confidence']);
    final selectedTotal = _selectedLineTotal();
    final documentTotal = _parse(_total.text);
    final mismatch = (selectedTotal - documentTotal).abs() > 0.01;

    return Scaffold(
      appBar: AppBar(title: const Text('Rever compra por OCR')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.job['supplier_name']?.toString().isNotEmpty == true
                        ? widget.job['supplier_name'].toString()
                        : 'Documento sem fornecedor identificado',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if ((widget.job['supplier_tax_id']?.toString() ?? '').isNotEmpty)
                        'NIF ${widget.job['supplier_tax_id']}',
                      widget.job['document_number']?.toString(),
                      widget.job['document_date']?.toString(),
                      if (confidence != null) 'Confiança ${(confidence * 100).round()}%',
                    ].whereType<String>().where((v) => v.isNotEmpty).join(' • '),
                  ),
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final warning in warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_outlined, size: 18),
                            const SizedBox(width: 6),
                            Expanded(child: Text(warning)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_lines.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.warning_amber_outlined),
                title: Text('O OCR não encontrou linhas de artigos.'),
                subtitle: Text('Não é possível atualizar stock sem linhas confirmadas.'),
              ),
            )
          else
            for (var index = 0; index < _lines.length; index++)
              _lineCard(index, _lines[index]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lançamento financeiro', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _total,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Total do documento (€)'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _eventId ?? '',
                    decoration: const InputDecoration(labelText: 'Evento (opcional)'),
                    items: [
                      const DropdownMenuItem<String>(value: '', child: Text('Sem evento')),
                      ...widget.events.map((event) => DropdownMenuItem<String>(value: event['id']?.toString() ?? '', child: Text(event['name']?.toString() ?? 'Evento'))),
                    ],
                    onChanged: (value) => setState(() => _eventId = value == null || value.isEmpty ? null : value),
                  ),
                  if (widget.canSelectAccount) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _accountId ?? '',
                      decoration: const InputDecoration(labelText: 'Conta da Tesouraria'),
                      items: [
                        const DropdownMenuItem<String>(value: '', child: Text('Automática (Caixa)')),
                        ...widget.accounts.map((account) => DropdownMenuItem<String>(value: account['id']?.toString() ?? '', child: Text(account['name']?.toString() ?? 'Conta'))),
                      ],
                      onChanged: (value) => setState(() => _accountId = value == null || value.isEmpty ? null : value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Método de pagamento'),
                    items: const [
                      DropdownMenuItem(value: 'Dinheiro', child: Text('Dinheiro')),
                      DropdownMenuItem(value: 'MB Way', child: Text('MB Way')),
                      DropdownMenuItem(value: 'Transferência bancária', child: Text('Transferência bancária')),
                      DropdownMenuItem(value: 'Cartão', child: Text('Cartão')),
                      DropdownMenuItem(value: 'Outro', child: Text('Outro')),
                    ],
                    onChanged: (value) => setState(() => _paymentMethod = value ?? 'Dinheiro'),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas')), 
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text('Linhas selecionadas ${_lines.where((line) => line.included).length}')),
                      Chip(label: Text('Linhas ${_money(selectedTotal)}')),
                      Chip(label: Text('Documento ${_money(documentTotal)}')),
                      if (mismatch)
                        const Chip(
                          avatar: Icon(Icons.info_outline, size: 18),
                          label: Text('Totais diferentes — confirma descontos/depósitos/outros'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Nenhum valor é lançado automaticamente. Só ao confirmar abaixo são atualizados stock e Tesouraria numa única operação.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : () async {
              try {
                await _confirm();
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            },
            icon: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fact_check_outlined),
            label: const Text('Confirmar entrada de stock + despesa'),
          ),
        ),
      ),
    );
  }

  Widget _lineCard(int index, _OcrBarLine line) {
    final description = line.source['description']?.toString() ?? 'Linha ${index + 1}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: line.included,
              title: Text(description),
              subtitle: Text(
                [
                  if (line.source['quantity'] != null) 'Qtd OCR ${line.source['quantity']}',
                  if (line.source['unit_price'] != null) 'Preço OCR ${line.source['unit_price']}',
                  if (line.source['line_total'] != null) 'Total OCR ${line.source['line_total']}',
                ].join(' • '),
              ),
              onChanged: (value) => setState(() => line.included = value ?? false),
            ),
            DropdownButtonFormField<String>(
              initialValue: line.productId ?? '',
              decoration: const InputDecoration(labelText: 'Artigo do Bar'),
              items: [
                const DropdownMenuItem<String>(value: '', child: Text('Não associado')),
                ...widget.products.map((product) => DropdownMenuItem<String>(value: product['id']?.toString() ?? '', child: Text(product['name']?.toString() ?? 'Artigo'))),
              ],
              onChanged: (value) {
                setState(() {
                  final selected = value == null || value.isEmpty ? null : value;
                  line.productId = selected;
                  if (selected != null) line.included = true;
                  if (selected != null && _parse(line.unitPrice.text) <= 0) {
                    Map<String, dynamic>? product;
                    for (final candidate in widget.products) {
                      if (candidate['id']?.toString() == selected) {
                        product = candidate;
                        break;
                      }
                    }
                    final purchaseCost = FinancialOcrRepository.number(product?['purchase_cost']);
                    if (purchaseCost != null) line.unitPrice.text = _numberText(purchaseCost);
                  }
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: line.purchaseUnits,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qtd. embalagens compra'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: line.unitPrice,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Preço / embalagem (€)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _selectedLineTotal() {
    var total = 0.0;
    for (final line in _lines.where((item) => item.included)) {
      total += _parse(line.purchaseUnits.text) * _parse(line.unitPrice.text);
    }
    return total;
  }

  static double _parse(String value) => double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;

  static String _numberText(Object? value) {
    final number = FinancialOcrRepository.number(value);
    if (number == null) return '';
    return number == number.roundToDouble()
        ? number.toInt().toString()
        : number.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String _money(Object? value) {
    final number = value is num ? value.toDouble() : _parse(value?.toString() ?? '');
    return '${number.toStringAsFixed(2).replaceAll('.', ',')} €';
  }
}

class _OcrBarLine {
  _OcrBarLine({
    required this.source,
    required this.productId,
    required this.included,
    required this.purchaseUnits,
    required this.unitPrice,
  });

  final Map<String, dynamic> source;
  String? productId;
  bool included;
  final TextEditingController purchaseUnits;
  final TextEditingController unitPrice;
}
