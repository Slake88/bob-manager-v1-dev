import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/reporting.dart';

class ReportExportService {
  const ReportExportService._();

  static Future<void> exportPdf(
    BuildContext context,
    ReportData data,
  ) async {
    final regularFont = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
    );

    final table = <List<dynamic>>[
      data.columns.map((column) => column.label).toList(),
      ...data.rows.map(
        (row) => data.columns
            .map((column) => formatValue(row[column.key], column.type))
            .toList(),
      ),
    ];

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(26),
        build: (_) => [
          pw.Text(
            'BLUE ON BLACK — ${data.definition.title}',
            style: pw.TextStyle(
              fontSize: 19,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Gerado em ${_generatedAt()}'),
          pw.SizedBox(height: 3),
          pw.Text(data.filtersDescription),
          pw.SizedBox(height: 10),
          if (data.metrics.isNotEmpty)
            pw.Wrap(
              spacing: 14,
              runSpacing: 5,
              children: data.metrics.entries
                  .map(
                    (entry) => pw.Text(
                      '${entry.key}: ${entry.value}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  )
                  .toList(),
            ),
          pw.SizedBox(height: 12),
          if (data.rows.isEmpty)
            pw.Text('Sem registos para os filtros selecionados.')
          else
            pw.TableHelper.fromTextArray(
              data: table,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 7.5,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellPadding: const pw.EdgeInsets.all(3),
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await document.save(),
      filename: fileName(data, 'pdf'),
    );
  }

  static Future<void> exportCsv(
    BuildContext context,
    ReportData data,
  ) async {
    final bytes = csvBytes(data);
    await _shareBytes(
      context,
      bytes,
      fileName(data, 'csv'),
      'text/csv',
      data.definition.title,
    );
  }

  static Future<void> exportExcel(
    BuildContext context,
    ReportData data,
  ) async {
    final workbook = ex.Excel.createExcel();
    final sheet = workbook['Relatório'];
    sheet.appendRow(
      data.columns.map((column) => ex.TextCellValue(column.label)).toList(),
    );

    for (final row in data.rows) {
      sheet.appendRow(
        data.columns
            .map((column) => _excelValue(row[column.key], column.type))
            .toList(),
      );
    }

    final summary = workbook['Resumo'];
    summary.appendRow([
      ex.TextCellValue('Relatório'),
      ex.TextCellValue(data.definition.title),
    ]);
    summary.appendRow([
      ex.TextCellValue('Gerado em'),
      ex.TextCellValue(_generatedAt()),
    ]);
    summary.appendRow([
      ex.TextCellValue('Filtros'),
      ex.TextCellValue(data.filtersDescription),
    ]);
    summary.appendRow([
      ex.TextCellValue('Registos'),
      ex.TextCellValue(data.rows.length.toString()),
    ]);
    for (final entry in data.metrics.entries) {
      summary.appendRow([
        ex.TextCellValue(entry.key),
        ex.TextCellValue(entry.value),
      ]);
    }

    final bytes = workbook.save();
    if (bytes == null) {
      throw StateError('Não foi possível gerar o ficheiro Excel.');
    }
    await _shareBytes(
      context,
      Uint8List.fromList(bytes),
      fileName(data, 'xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      data.definition.title,
    );
  }

  static Uint8List csvBytes(ReportData data) {
    final rows = <List<String>>[
      data.columns.map((column) => column.label).toList(),
      ...data.rows.map(
        (row) => data.columns
            .map((column) => formatValue(row[column.key], column.type))
            .toList(),
      ),
    ];
    final csv = '\ufeff${rows.map((row) => row.map(csvCell).join(';')).join('\r\n')}';
    return Uint8List.fromList(utf8.encode(csv));
  }

  static String csvCell(String value) => '"${value.replaceAll('"', '""')}"';

  static String formatValue(Object? value, ReportValueType type) {
    if (value == null || value.toString().trim().isEmpty) return '';
    return switch (type) {
      ReportValueType.currency => _money(_num(value)),
      ReportValueType.number => _number(_num(value)),
      ReportValueType.date => _formatDate(value, withTime: false),
      ReportValueType.dateTime => _formatDate(value, withTime: true),
      ReportValueType.boolean => value == true || value.toString() == 'true' ? 'Sim' : 'Não',
      ReportValueType.text => value.toString(),
    };
  }

  static String fileName(ReportData data, String extension) {
    final safe = data.definition.title
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'BOB_${safe}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.$extension';
  }

  static ex.CellValue _excelValue(Object? value, ReportValueType type) {
    if (value == null || value.toString().trim().isEmpty) {
      return ex.TextCellValue('');
    }
    return switch (type) {
      ReportValueType.currency || ReportValueType.number =>
        ex.DoubleCellValue(_num(value)),
      ReportValueType.boolean =>
        ex.TextCellValue(value == true || value.toString() == 'true' ? 'Sim' : 'Não'),
      ReportValueType.date =>
        ex.TextCellValue(_formatDate(value, withTime: false)),
      ReportValueType.dateTime =>
        ex.TextCellValue(_formatDate(value, withTime: true)),
      ReportValueType.text => ex.TextCellValue(value.toString()),
    };
  }

  static Future<void> _shareBytes(
    BuildContext context,
    Uint8List bytes,
    String filename,
    String mimeType,
    String title,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType)],
        fileNameOverrides: [filename],
        title: 'BOB — $title',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

String _generatedAt() => DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
String _formatDate(Object? value, {required bool withTime}) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return value?.toString() ?? '';
  return DateFormat(withTime ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy').format(date.toLocal());
}
double _num(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
String _money(double value) => '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
String _number(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 2).replaceAll('.', ',');
