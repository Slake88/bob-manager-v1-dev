import 'package:flutter/material.dart';

import '../repositories/financial_documents_repository.dart';
import '../repositories/financial_ocr_repository.dart';

class FinancialOcrPanel extends StatefulWidget {
  const FinancialOcrPanel({
    super.key,
    required this.transactionId,
    required this.transactionAmount,
  });

  final String transactionId;
  final Object? transactionAmount;

  @override
  State<FinancialOcrPanel> createState() => _FinancialOcrPanelState();
}

class _FinancialOcrPanelState extends State<FinancialOcrPanel> {
  final FinancialDocumentsRepository _documents = FinancialDocumentsRepository();
  final FinancialOcrRepository _ocr = FinancialOcrRepository();
  late Future<_FinancialOcrData> _future;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait<dynamic>([
      _documents.listForTransaction(widget.transactionId),
      _ocr.jobsForTransaction(widget.transactionId),
    ]).then(
      (values) => _FinancialOcrData(
        documents: List<Map<String, dynamic>>.from(values[0] as List),
        jobs: List<Map<String, dynamic>>.from(values[1] as List),
      ),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _run(Map<String, dynamic> document) async {
    final id = document['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      final jobId = await _ocr.startForDocument(id);
      final result = await _ocr.runOcr(jobId);
      if (!mounted) return;
      setState(_reload);
      _showStatus(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _retry(Map<String, dynamic> job) async {
    final id = job['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() => _busyId = id);
    try {
      final result = await _ocr.retry(id);
      if (!mounted) return;
      setState(_reload);
      _showStatus(result);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _showStatus(Map<String, dynamic> job) {
    final status = job['status']?.toString();
    if (status == 'unconfigured') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O serviço OCR está preparado, mas falta configurar GOOGLE_VISION_API_KEY e GOOGLE_CLOUD_PROJECT_ID no Supabase.',
          ),
        ),
      );
    } else if (status == 'failed') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            job['error_message']?.toString() ?? 'A leitura OCR falhou.',
          ),
        ),
      );
    }
  }

  Future<void> _review(Map<String, dynamic> job) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _FinancialOcrReviewDialog(
        repository: _ocr,
        job: job,
      ),
    );
    if (saved == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ocr.canRunFinancialOcr) return const SizedBox.shrink();
    return FutureBuilder<_FinancialOcrData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Leitura OCR'),
              subtitle: Text('Não foi possível carregar o OCR: ${snapshot.error}'),
              trailing: IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snapshot.data!;
        final supported = data.documents
            .where((doc) => FinancialOcrRepository.isSupportedMime(
                  doc['mime_type']?.toString(),
                ))
            .toList();

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.document_scanner_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Leitura OCR',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Atualizar',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Extrai fornecedor, NIF, data, totais e linhas para revisão. '
                  'O OCR nunca altera o movimento financeiro automaticamente.',
                ),
                const SizedBox(height: 12),
                if (supported.isEmpty)
                  const Text(
                    'Adiciona uma imagem JPG/PNG/WEBP ou um PDF para poder executar OCR.',
                  )
                else
                  for (final document in supported) ...[
                    _documentTile(data, document),
                    const Divider(height: 20),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _documentTile(
    _FinancialOcrData data,
    Map<String, dynamic> document,
  ) {
    Map<String, dynamic>? job;
    for (final candidate in data.jobs) {
      if (candidate['document_id']?.toString() == document['id']?.toString()) {
        job = candidate;
        break;
      }
    }
    final status = job?['status']?.toString();
    final busy = _busyId == document['id']?.toString() ||
        (job != null && _busyId == job['id']?.toString());
    final discrepancy = job != null &&
        FinancialOcrRepository.hasAmountDiscrepancy(
          widget.transactionAmount,
          job['total'],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            FinancialDocumentsRepository.isPdf(document)
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
          ),
          title: Text(
            document['original_file_name']?.toString() ?? 'Documento',
          ),
          subtitle: Text(
            job == null
                ? 'Ainda sem leitura OCR.'
                : FinancialOcrRepository.statusLabel(status),
          ),
          trailing: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : job == null
                  ? FilledButton.tonalIcon(
                      onPressed: () => _run(document),
                      icon: const Icon(Icons.document_scanner_outlined),
                      label: const Text('Ler'),
                    )
                  : null,
        ),
        if (job != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((job['supplier_name']?.toString() ?? '').isNotEmpty)
                Chip(label: Text(job['supplier_name'].toString())),
              if (job['document_date'] != null)
                Chip(label: Text(job['document_date'].toString())),
              if (job['total'] != null)
                Chip(label: Text('Total ${_money(job['total'])}')),
              if (job['confidence'] != null)
                Chip(
                  label: Text(
                    'Confiança ${((FinancialOcrRepository.number(job['confidence']) ?? 0) * 100).round()}%',
                  ),
                ),
              if (discrepancy)
                const Chip(
                  avatar: Icon(Icons.warning_amber_outlined, size: 18),
                  label: Text('Total difere do movimento'),
                ),
            ],
          ),
          if ((job['error_message']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              job['error_message'].toString(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (status == 'ready' || status == 'reviewed')
                OutlinedButton.icon(
                  onPressed: () => _review(job!),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(status == 'reviewed' ? 'Rever novamente' : 'Rever OCR'),
                ),
              if (status == 'failed' || status == 'unconfigured')
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _retry(job!),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tentar novamente'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _money(Object? value) {
    final amount = FinancialOcrRepository.number(value) ?? 0;
    return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
  }
}

class _FinancialOcrReviewDialog extends StatefulWidget {
  const _FinancialOcrReviewDialog({
    required this.repository,
    required this.job,
  });

  final FinancialOcrRepository repository;
  final Map<String, dynamic> job;

  @override
  State<_FinancialOcrReviewDialog> createState() =>
      _FinancialOcrReviewDialogState();
}

class _FinancialOcrReviewDialogState
    extends State<_FinancialOcrReviewDialog> {
  late final TextEditingController supplier;
  late final TextEditingController nif;
  late final TextEditingController number;
  late final TextEditingController date;
  late final TextEditingController currency;
  late final TextEditingController subtotal;
  late final TextEditingController tax;
  late final TextEditingController total;
  late final TextEditingController payment;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    supplier = TextEditingController(text: widget.job['supplier_name']?.toString() ?? '');
    nif = TextEditingController(text: widget.job['supplier_tax_id']?.toString() ?? '');
    number = TextEditingController(text: widget.job['document_number']?.toString() ?? '');
    date = TextEditingController(text: widget.job['document_date']?.toString() ?? '');
    currency = TextEditingController(text: widget.job['currency']?.toString() ?? 'EUR');
    subtotal = TextEditingController(text: _numText(widget.job['subtotal']));
    tax = TextEditingController(text: _numText(widget.job['tax_total']));
    total = TextEditingController(text: _numText(widget.job['total']));
    payment = TextEditingController(text: widget.job['payment_method']?.toString() ?? '');
  }

  @override
  void dispose() {
    for (final controller in [supplier, nif, number, date, currency, subtotal, tax, total, payment]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final parsedDate = date.text.trim().isEmpty
          ? null
          : DateTime.tryParse(date.text.trim());
      if (date.text.trim().isNotEmpty && parsedDate == null) {
        throw ArgumentError('Usa a data no formato AAAA-MM-DD.');
      }
      await widget.repository.saveReview(
        job: widget.job,
        supplierName: supplier.text,
        supplierTaxId: nif.text,
        documentNumber: number.text,
        documentDate: parsedDate,
        currency: currency.text,
        subtotal: _parseNullable(subtotal.text),
        taxTotal: _parseNullable(tax.text),
        total: _parseNullable(total.text),
        paymentMethod: payment.text,
        lineItems: FinancialOcrRepository.lineItems(widget.job),
        warnings: FinancialOcrRepository.warnings(widget.job),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = FinancialOcrRepository.lineItems(widget.job);
    final warnings = FinancialOcrRepository.warnings(widget.job);
    return AlertDialog(
      title: const Text('Rever leitura OCR'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Fornecedor')),
              TextField(controller: nif, decoration: const InputDecoration(labelText: 'NIF fornecedor')),
              TextField(controller: number, decoration: const InputDecoration(labelText: 'N.º documento')),
              TextField(controller: date, decoration: const InputDecoration(labelText: 'Data (AAAA-MM-DD)')),
              Row(
                children: [
                  Expanded(child: TextField(controller: subtotal, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Subtotal'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: tax, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'IVA'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: total, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Total'))),
                ],
              ),
              Row(
                children: [
                  Expanded(child: TextField(controller: currency, decoration: const InputDecoration(labelText: 'Moeda'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: payment, decoration: const InputDecoration(labelText: 'Pagamento detetado'))),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${lines.length} linhas detetadas', style: Theme.of(context).textTheme.titleSmall),
              ),
              for (final line in lines.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(line['description']?.toString() ?? 'Linha'),
                  trailing: line['line_total'] == null ? null : Text(_FinancialOcrPanelState._money(line['line_total'])),
                ),
              if (warnings.isNotEmpty) ...[
                const Divider(),
                for (final warning in warnings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: Text(warning),
                  ),
              ],
              const SizedBox(height: 8),
              const Text(
                'Guardar a revisão não altera a Tesouraria. O movimento financeiro mantém os valores já registados.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('Guardar revisão'),
        ),
      ],
    );
  }

  static String _numText(Object? value) {
    final number = FinancialOcrRepository.number(value);
    return number == null ? '' : number.toStringAsFixed(2).replaceAll('.', ',');
  }

  static double? _parseNullable(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return null;
    final parsed = double.tryParse(clean.replaceAll(',', '.'));
    if (parsed == null) throw ArgumentError('Valor numérico inválido: $value');
    return parsed;
  }
}

class _FinancialOcrData {
  const _FinancialOcrData({required this.documents, required this.jobs});
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> jobs;
}
