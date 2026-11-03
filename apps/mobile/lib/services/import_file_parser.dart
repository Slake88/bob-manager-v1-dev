import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../core/importing.dart';

class ImportFileParser {
  const ImportFileParser();

  static const int maxFileBytes = 2 * 1024 * 1024;
  static const int maxRows = 1000;
  static const int maxColumns = 50;

  Future<ParsedImportFile?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      throw const ImportParseException(
        'Não foi possível ler o ficheiro selecionado.',
      );
    }
    if (bytes.length > maxFileBytes) {
      throw const ImportParseException(
        'O ficheiro ultrapassa o limite de 2 MB.',
      );
    }

    final extension = (file.extension ?? '').toLowerCase();
    return switch (extension) {
      'csv' => parseCsv(file.name, bytes),
      'xlsx' => parseXlsx(file.name, bytes),
      _ => throw const ImportParseException(
          'Formato não suportado. Usa CSV ou XLSX.',
        ),
    };
  }

  ParsedImportFile parseCsv(String filename, Uint8List bytes) {
    final text = _decodeCsv(bytes);
    final delimiter = _detectDelimiter(text);
    final matrix = _parseDelimited(text, delimiter);
    return _matrixToFile(
      filename: filename,
      format: 'csv',
      matrix: matrix,
    );
  }

  ParsedImportFile parseXlsx(String filename, Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    String? selectedName;
    List<List<String>> matrix = const [];

    for (final name in workbook.tables.keys) {
      final sheet = workbook.tables[name];
      if (sheet == null || sheet.rows.isEmpty) continue;
      final candidate = sheet.rows
          .map(
            (row) => row
                .map((cell) => cell?.value?.toString().trim() ?? '')
                .toList(),
          )
          .toList();
      if (candidate.any((row) => row.any((cell) => cell.isNotEmpty))) {
        selectedName = name;
        matrix = candidate;
        break;
      }
    }

    if (selectedName == null) {
      throw const ImportParseException(
        'O Excel não contém nenhuma folha com dados.',
      );
    }

    return _matrixToFile(
      filename: filename,
      format: 'xlsx',
      matrix: matrix,
      sheetName: selectedName,
    );
  }

  ParsedImportFile _matrixToFile({
    required String filename,
    required String format,
    required List<List<String>> matrix,
    String? sheetName,
  }) {
    final rows = matrix
        .where((row) => row.any((cell) => cell.trim().isNotEmpty))
        .toList();
    if (rows.length < 2) {
      throw const ImportParseException(
        'O ficheiro precisa de cabeçalho e pelo menos uma linha de dados.',
      );
    }

    final rawHeaders = rows.first;
    if (rawHeaders.length > maxColumns) {
      throw const ImportParseException(
        'O ficheiro ultrapassa o limite de 50 colunas.',
      );
    }

    final headers = _uniqueHeaders(rawHeaders);
    final dataRows = rows.skip(1).toList();
    if (dataRows.length > maxRows) {
      throw const ImportParseException(
        'O ficheiro ultrapassa o limite de 1000 linhas.',
      );
    }

    final mapped = <Map<String, String>>[];
    for (final row in dataRows) {
      final values = List<String>.generate(
        headers.length,
        (index) => index < row.length ? row[index].trim() : '',
      );
      mapped.add({
        for (var index = 0; index < headers.length; index++)
          headers[index]: values[index],
      });
    }

    return ParsedImportFile(
      filename: filename,
      format: format,
      headers: headers,
      rows: mapped,
      sheetName: sheetName,
    );
  }

  List<String> _uniqueHeaders(List<String> raw) {
    final used = <String, int>{};
    return List<String>.generate(raw.length, (index) {
      final base = raw[index].trim().isEmpty
          ? 'Coluna ${index + 1}'
          : raw[index].trim();
      final count = (used[base] ?? 0) + 1;
      used[base] = count;
      return count == 1 ? base : '$base ($count)';
    });
  }

  String _decodeCsv(Uint8List bytes) {
    final data = bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? bytes.sublist(3)
        : bytes;
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data);
    }
  }

  String _detectDelimiter(String text) {
    final sample = text.split(RegExp(r'\r?\n')).take(5).join('\n');
    final candidates = [';', ',', '\t'];
    var best = ';';
    var bestCount = -1;
    for (final candidate in candidates) {
      final count = _delimiterCount(sample, candidate);
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  int _delimiterCount(String text, String delimiter) {
    var quoted = false;
    var count = 0;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        if (quoted && index + 1 < text.length && text[index + 1] == '"') {
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && char == delimiter) {
        count++;
      }
    }
    return count;
  }

  List<List<String>> _parseDelimited(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;

    void finishCell() {
      row.add(cell.toString());
      cell = StringBuffer();
    }

    void finishRow() {
      finishCell();
      rows.add(row);
      row = <String>[];
    }

    for (var index = 0; index < text.length; index++) {
      final char = text[index];

      if (char == '"') {
        if (quoted && index + 1 < text.length && text[index + 1] == '"') {
          cell.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
        continue;
      }

      if (!quoted && char == delimiter) {
        finishCell();
        continue;
      }

      if (!quoted && (char == '\n' || char == '\r')) {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        finishRow();
        continue;
      }

      cell.write(char);
    }

    if (quoted) {
      throw const ImportParseException(
        'O CSV contém aspas abertas sem fecho.',
      );
    }

    if (cell.length > 0 || row.isNotEmpty) {
      finishRow();
    }

    return rows;
  }
}

class ImportParseException implements Exception {
  const ImportParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
