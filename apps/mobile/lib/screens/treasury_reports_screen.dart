import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../repositories/treasury_reports_repository.dart';

class TreasuryReportsScreen extends StatefulWidget {
  const TreasuryReportsScreen({super.key});

  @override
  State<TreasuryReportsScreen> createState() => _TreasuryReportsScreenState();
}

class _TreasuryReportsScreenState extends State<TreasuryReportsScreen> {
  final TreasuryReportsRepository _repository = TreasuryReportsRepository();
  late DateTime _from;
  late DateTime _to;
  String? _accountId;
  String? _costCenterId;
  String? _kind;
  late Future<TreasuryReportData> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0);
    _reload();
  }

  void _reload() {
    _future = _repository.load(
      from: _from,
      to: _to,
      accountId: _accountId,
      costCenterId: _costCenterId,
      kind: _kind,
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _applyPreset(String value) {
    final now = DateTime.now();
    setState(() {
      if (value == 'month') {
        _from = DateTime(now.year, now.month, 1);
        _to = DateTime(now.year, now.month + 1, 0);
      } else if (value == 'year') {
        _from = DateTime(now.year, 1, 1);
        _to = DateTime(now.year, 12, 31);
      } else if (value == 'previous_month') {
        final previous = DateTime(now.year, now.month - 1, 1);
        _from = previous;
        _to = DateTime(previous.year, previous.month + 1, 0);
      }
      _reload();
    });
  }

  Future<void> _pickFrom() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      _from = value;
      if (_to.isBefore(_from)) _to = _from;
      _reload();
    });
  }

  Future<void> _pickTo() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (value == null) return;
    setState(() {
      _to = value;
      if (_to.isBefore(_from)) _from = _to;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Extratos e Relatórios Financeiros')),
      body: FutureBuilder<TreasuryReportData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _filters(data),
                const SizedBox(height: 12),
                _metrics(data),
                const SizedBox(height: 12),
                _exports(data),
                const SizedBox(height: 16),
                Text('Evolução mensal', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _monthlyChart(data),
                const SizedBox(height: 16),
                Text('Extrato', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (data.movements.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Sem movimentos para os filtros selecionados.'),
                    ),
                  )
                else
                  ...data.movements.map(_movementCard),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters(TreasuryReportData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(onPressed: () => _applyPreset('month'), child: const Text('Este mês')),
                OutlinedButton(onPressed: () => _applyPreset('previous_month'), child: const Text('Mês anterior')),
                OutlinedButton(onPressed: () => _applyPreset('year'), child: const Text('Este ano')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text('De ${_date(_from)}'),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Até ${_date(_to)}'),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(labelText: 'Conta'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todas as contas')),
                      ...data.accounts.map((row) => DropdownMenuItem<String?>(
                            value: row['id']?.toString(),
                            child: Text(row['name']?.toString() ?? 'Conta'),
                          )),
                    ],
                    onChanged: (value) => setState(() {
                      _accountId = value;
                      _reload();
                    }),
                  ),
                ),
                SizedBox(
                  width: 230,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _costCenterId,
                    decoration: const InputDecoration(labelText: 'Centro de custo'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Todos os centros')),
                      ...data.costCenters.map((row) => DropdownMenuItem<String?>(
                            value: row['id']?.toString(),
                            child: Text(row['name']?.toString() ?? 'Centro'),
                          )),
                    ],
                    onChanged: (value) => setState(() {
                      _costCenterId = value;
                      _reload();
                    }),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _kind,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                      DropdownMenuItem<String?>(value: 'income', child: Text('Receitas')),
                      DropdownMenuItem<String?>(value: 'expense', child: Text('Despesas')),
                      DropdownMenuItem<String?>(value: 'transfer', child: Text('Transferências')),
                    ],
                    onChanged: (value) => setState(() {
                      _kind = value;
                      _reload();
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metrics(TreasuryReportData data) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _metric('Saldo inicial', _money(data.openingBalance), Icons.flag_outlined),
        _metric('Receitas', _money(data.income), Icons.south_west),
        _metric('Despesas', _money(data.expense), Icons.north_east),
        _metric('Resultado', _money(data.result), Icons.trending_up),
        _metric('Saldo final', _money(data.closingBalance), Icons.account_balance_wallet_outlined),
        _metric('Movimentos', '${data.movements.length}', Icons.receipt_long_outlined),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon) {
    return SizedBox(
      width: 205,
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(label),
          subtitle: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }

  Widget _exports(TreasuryReportData data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _exportPdf(data),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => _exportExcel(data),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Excel'),
            ),
            OutlinedButton.icon(
              onPressed: () => _exportCsv(data),
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('CSV'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthlyChart(TreasuryReportData data) {
    if (data.monthly.isEmpty) {
      return const Card(child: ListTile(title: Text('Sem dados para gráfico.')));
    }
    final maxValue = data.monthly.fold<double>(0, (max, row) {
      final local = row.income > row.expense ? row.income : row.expense;
      return local > max ? local : max;
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: data.monthly.map((row) {
            final label = DateFormat('MMM yyyy', 'pt_PT').format(DateTime(row.year, row.month));
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  _bar('Receitas', row.income, maxValue),
                  const SizedBox(height: 4),
                  _bar('Despesas', row.expense, maxValue),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _bar(String label, double value, double maxValue) {
    final factor = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(child: LinearProgressIndicator(value: factor, minHeight: 12)),
        const SizedBox(width: 8),
        SizedBox(width: 95, child: Text(_money(value), textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _movementCard(Map<String, dynamic> movement) {
    final kind = movement['kind']?.toString();
    final isIncome = kind == 'income';
    final isTransfer = kind == 'transfer';
    return Card(
      child: ListTile(
        leading: Icon(isTransfer ? Icons.swap_horiz : isIncome ? Icons.arrow_downward : Icons.arrow_upward),
        title: Text(movement['description']?.toString() ?? 'Movimento'),
        subtitle: Text([
          movement['transaction_date'],
          if (isTransfer)
            '${movement['account_name'] ?? '—'} → ${movement['destination_account_name'] ?? '—'}'
          else
            movement['account_name'],
          movement['cost_center_name'],
        ].where((value) => value != null && value.toString().isNotEmpty).join(' • ')),
        trailing: Text('${isIncome ? '+' : isTransfer ? '' : '-'}${_money(_num(movement['amount']))}'),
      ),
    );
  }

  Future<void> _exportPdf(TreasuryReportData data) async {
    final document = pw.Document();
    final tableData = <List<dynamic>>[
      ['Data', 'Tipo', 'Descrição', 'Conta', 'Centro', 'Valor'],
      ...data.movements.map((row) => [
            row['transaction_date']?.toString() ?? '',
            _kindLabel(row['kind']?.toString()),
            row['description']?.toString() ?? '',
            row['account_name']?.toString() ?? '',
            row['cost_center_name']?.toString() ?? '',
            _money(_signed(row)),
          ]),
    ];
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text('BLUE ON BLACK — Extrato Financeiro', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Período: ${_date(_from)} a ${_date(_to)}'),
          pw.SizedBox(height: 12),
          pw.Wrap(spacing: 16, runSpacing: 6, children: [
            pw.Text('Saldo inicial: ${_money(data.openingBalance)}'),
            pw.Text('Receitas: ${_money(data.income)}'),
            pw.Text('Despesas: ${_money(data.expense)}'),
            pw.Text('Resultado: ${_money(data.result)}'),
            pw.Text('Saldo final: ${_money(data.closingBalance)}'),
          ]),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(data: tableData, headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold), cellStyle: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
    await Printing.sharePdf(bytes: await document.save(), filename: _fileName('pdf'));
  }

  Future<void> _exportCsv(TreasuryReportData data) async {
    final rows = <List<String>>[
      ['Data', 'Tipo', 'Descrição', 'Conta', 'Conta destino', 'Centro de custo', 'Valor'],
      ...data.movements.map((row) => [
            row['transaction_date']?.toString() ?? '',
            _kindLabel(row['kind']?.toString()),
            row['description']?.toString() ?? '',
            row['account_name']?.toString() ?? '',
            row['destination_account_name']?.toString() ?? '',
            row['cost_center_name']?.toString() ?? '',
            _signed(row).toStringAsFixed(2),
          ]),
    ];
    final csv = '\ufeff${rows.map((row) => row.map(_csvCell).join(';')).join('\r\n')}';
    await _shareBytes(Uint8List.fromList(utf8.encode(csv)), _fileName('csv'), 'text/csv');
  }

  Future<void> _exportExcel(TreasuryReportData data) async {
    final workbook = ex.Excel.createExcel();
    final sheet = workbook['Extrato'];
    sheet.appendRow([
      ex.TextCellValue('Data'),
      ex.TextCellValue('Tipo'),
      ex.TextCellValue('Descrição'),
      ex.TextCellValue('Conta'),
      ex.TextCellValue('Conta destino'),
      ex.TextCellValue('Centro de custo'),
      ex.TextCellValue('Valor'),
    ]);
    for (final row in data.movements) {
      sheet.appendRow([
        ex.TextCellValue(row['transaction_date']?.toString() ?? ''),
        ex.TextCellValue(_kindLabel(row['kind']?.toString())),
        ex.TextCellValue(row['description']?.toString() ?? ''),
        ex.TextCellValue(row['account_name']?.toString() ?? ''),
        ex.TextCellValue(row['destination_account_name']?.toString() ?? ''),
        ex.TextCellValue(row['cost_center_name']?.toString() ?? ''),
        ex.DoubleCellValue(_signed(row)),
      ]);
    }
    final summary = workbook['Resumo'];
    summary.appendRow([ex.TextCellValue('Período'), ex.TextCellValue('${_date(_from)} a ${_date(_to)}')]);
    summary.appendRow([ex.TextCellValue('Saldo inicial'), ex.DoubleCellValue(data.openingBalance)]);
    summary.appendRow([ex.TextCellValue('Receitas'), ex.DoubleCellValue(data.income)]);
    summary.appendRow([ex.TextCellValue('Despesas'), ex.DoubleCellValue(data.expense)]);
    summary.appendRow([ex.TextCellValue('Resultado'), ex.DoubleCellValue(data.result)]);
    summary.appendRow([ex.TextCellValue('Saldo final'), ex.DoubleCellValue(data.closingBalance)]);
    final bytes = workbook.save();
    if (bytes == null) throw StateError('Não foi possível gerar o Excel.');
    await _shareBytes(Uint8List.fromList(bytes), _fileName('xlsx'), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  Future<void> _shareBytes(Uint8List bytes, String filename, String mimeType) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType)],
        fileNameOverrides: [filename],
        title: 'Extrato financeiro BOB',
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  String _fileName(String extension) =>
      'BOB_Extrato_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}.$extension';
}

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';
String _kindLabel(String? value) => switch (value) {
      'income' => 'Receita',
      'expense' => 'Despesa',
      'transfer' => 'Transferência',
      _ => 'Movimento',
    };
String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
String _money(double value) => '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
double _num(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
double _signed(Map<String, dynamic> row) {
  final amount = _num(row['amount']);
  return row['kind'] == 'expense' ? -amount : row['kind'] == 'income' ? amount : 0;
}
