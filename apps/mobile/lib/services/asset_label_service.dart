import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AssetLabelService {
  static String payload(String qrCode) => 'BOB:ASSET:${qrCode.trim().toUpperCase()}';

  static Future<void> printLabel({
    required String assetNumber,
    required String qrCode,
    required String name,
    required String category,
  }) async {
    await Printing.layoutPdf(
      name: 'BOB_${assetNumber}_etiqueta.pdf',
      onLayout: (_) => buildLabel(
        assetNumber: assetNumber,
        qrCode: qrCode,
        name: name,
        category: category,
      ),
    );
  }

  static Future<Uint8List> buildLabel({
    required String assetNumber,
    required String qrCode,
    required String name,
    required String category,
  }) async {
    final document = pw.Document();
    final data = payload(qrCode);
    const labelFormat = PdfPageFormat(85 * PdfPageFormat.mm, 55 * PdfPageFormat.mm);

    document.addPage(
      pw.Page(
        pageFormat: labelFormat,
        margin: const pw.EdgeInsets.all(6 * PdfPageFormat.mm),
        build: (_) => pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 1.2),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          padding: const pw.EdgeInsets.all(8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 34 * PdfPageFormat.mm,
                height: 34 * PdfPageFormat.mm,
                color: PdfColors.white,
                padding: const pw.EdgeInsets.all(5),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: data,
                  color: PdfColors.black,
                  backgroundColor: PdfColors.white,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('BLUE ON BLACK', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.Text('PATRIMÓNIO', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 6),
                    pw.Text(name, maxLines: 2, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(category, style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 6),
                    pw.Text(assetNumber, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text(data, style: const pw.TextStyle(fontSize: 7)),
                    pw.SizedBox(height: 4),
                    pw.Text('NÃO REMOVER', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return document.save();
  }
}
