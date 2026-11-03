from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def fail(message: str):
    raise SystemExit(f"\nERRO: {message}\n")

def replace_once(path: str, old: str, new: str):
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    if new in text:
        return
    if old not in text:
        fail(f"Não encontrei o ponto esperado em {path}. Não alterei esse ficheiro.")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")

def write_file(path: str, content: str):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")

FILES = {'apps/mobile/lib/repositories/financial_ocr_repository.dart': "import 'dart:typed_data';\n"
                                                               '\n'
                                                               "import 'package:file_picker/file_picker.dart';\n"
                                                               'import '
                                                               "'package:supabase_flutter/supabase_flutter.dart';\n"
                                                               '\n'
                                                               "import '../core/app_config.dart';\n"
                                                               "import '../core/app_session.dart';\n"
                                                               "import '../core/permissions.dart';\n"
                                                               "import 'financial_documents_repository.dart';\n"
                                                               '\n'
                                                               'class FinancialOcrRepository {\n'
                                                               '  static const String bucketName = '
                                                               'FinancialDocumentsRepository.bucketName;\n'
                                                               '  static const int maxFileBytes = '
                                                               'FinancialDocumentsRepository.maxFileBytes;\n'
                                                               '\n'
                                                               '  SupabaseClient get _client => '
                                                               'Supabase.instance.client;\n'
                                                               '  String get _clubId => AppSession.instance.clubId;\n'
                                                               '\n'
                                                               '  bool get canRunFinancialOcr =>\n'
                                                               '      '
                                                               'AppSession.instance.can(AppPermission.createTreasuryMovement) '
                                                               '||\n'
                                                               '      '
                                                               'AppSession.instance.can(AppPermission.approveExpenseRequests);\n'
                                                               '\n'
                                                               '  bool get canRunBarOcr => '
                                                               'AppSession.instance.can(AppPermission.manageBar);\n'
                                                               '\n'
                                                               '  Future<List<Map<String, dynamic>>> '
                                                               'jobsForTransaction(\n'
                                                               '    String transactionId,\n'
                                                               '  ) async {\n'
                                                               '    if (AppConfig.demoMode) return const [];\n'
                                                               '    final response = await _client\n'
                                                               "        .from('financial_ocr_jobs')\n"
                                                               '        .select()\n'
                                                               "        .eq('club_id', _clubId)\n"
                                                               "        .eq('transaction_id', transactionId)\n"
                                                               "        .order('created_at', ascending: false);\n"
                                                               '    return List<Map<String, dynamic>>.from(response);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<Map<String, dynamic>> job(String jobId) async '
                                                               '{\n'
                                                               '    if (AppConfig.demoMode) {\n'
                                                               "      throw StateError('OCR não disponível em "
                                                               "Demo.');\n"
                                                               '    }\n'
                                                               '    final response = await _client\n'
                                                               "        .from('financial_ocr_jobs')\n"
                                                               '        .select()\n'
                                                               "        .eq('club_id', _clubId)\n"
                                                               "        .eq('id', jobId)\n"
                                                               '        .single();\n'
                                                               '    return Map<String, dynamic>.from(response);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<String> startForDocument(String documentId) '
                                                               'async {\n'
                                                               '    if (!canRunFinancialOcr) {\n'
                                                               "      throw StateError('Sem permissão para executar "
                                                               "OCR financeiro.');\n"
                                                               '    }\n'
                                                               '    if (AppConfig.demoMode) {\n'
                                                               "      throw StateError('OCR não disponível em "
                                                               "Demo.');\n"
                                                               '    }\n'
                                                               '    final response = await _client.rpc(\n'
                                                               "      'start_financial_document_ocr_v1',\n"
                                                               '      params: {\n'
                                                               "        'target_club': _clubId,\n"
                                                               "        'p_document': documentId,\n"
                                                               '      },\n'
                                                               '    );\n'
                                                               '    return response.toString();\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<String> createBarJob() async {\n'
                                                               '    if (!canRunBarOcr) {\n'
                                                               "      throw StateError('Sem permissão para usar OCR no "
                                                               "Bar.');\n"
                                                               '    }\n'
                                                               '    if (AppConfig.demoMode) {\n'
                                                               "      throw StateError('OCR não disponível em "
                                                               "Demo.');\n"
                                                               '    }\n'
                                                               '    final response = await _client.rpc(\n'
                                                               "      'create_bar_ocr_job_v1',\n"
                                                               "      params: {'target_club': _clubId},\n"
                                                               '    );\n'
                                                               '    return response.toString();\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<Map<String, dynamic>> uploadBarSource({\n'
                                                               '    required String jobId,\n'
                                                               '    required PlatformFile file,\n'
                                                               '  }) async {\n'
                                                               '    if (!canRunBarOcr) {\n'
                                                               "      throw StateError('Sem permissão para usar OCR no "
                                                               "Bar.');\n"
                                                               '    }\n'
                                                               '    final Uint8List? bytes = file.bytes;\n'
                                                               '    if (bytes == null || bytes.isEmpty) {\n'
                                                               '      throw StateError(\n'
                                                               "        'Não foi possível ler ${file.name}. Seleciona "
                                                               "novamente o ficheiro.',\n"
                                                               '      );\n'
                                                               '    }\n'
                                                               '    if (bytes.length > maxFileBytes) {\n'
                                                               "      throw StateError('${file.name} ultrapassa o "
                                                               "limite de 20 MB.');\n"
                                                               '    }\n'
                                                               '    final mimeType =\n'
                                                               '        '
                                                               'FinancialDocumentsRepository.mimeTypeForExtension(file.extension);\n'
                                                               '    if (!isSupportedMime(mimeType)) {\n'
                                                               "      throw StateError('Formato não suportado. Usa "
                                                               "JPG, PNG, WEBP ou PDF.');\n"
                                                               '    }\n'
                                                               '\n'
                                                               '    final timestamp = '
                                                               'DateTime.now().microsecondsSinceEpoch;\n'
                                                               '    final safeName = safeFileName(file.name);\n'
                                                               '    final path = '
                                                               "'$_clubId/ocr/$jobId/${timestamp}_$safeName';\n"
                                                               '\n'
                                                               '    await '
                                                               '_client.storage.from(bucketName).uploadBinary(\n'
                                                               '          path,\n'
                                                               '          bytes,\n'
                                                               '          fileOptions: FileOptions(contentType: '
                                                               'mimeType, upsert: false),\n'
                                                               '        );\n'
                                                               '    try {\n'
                                                               '      await _client.rpc(\n'
                                                               "        'attach_bar_ocr_source_v1',\n"
                                                               '        params: {\n'
                                                               "          'target_club': _clubId,\n"
                                                               "          'p_job': jobId,\n"
                                                               "          'p_storage_path': path,\n"
                                                               "          'p_original_file_name': file.name,\n"
                                                               "          'p_mime_type': mimeType,\n"
                                                               "          'p_file_size': bytes.length,\n"
                                                               '        },\n'
                                                               '      );\n'
                                                               '    } catch (_) {\n'
                                                               '      await '
                                                               '_client.storage.from(bucketName).remove([path]);\n'
                                                               '      rethrow;\n'
                                                               '    }\n'
                                                               '    return job(jobId);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<Map<String, dynamic>> runOcr(String jobId) '
                                                               'async {\n'
                                                               '    if (AppConfig.demoMode) {\n'
                                                               "      throw StateError('OCR não disponível em "
                                                               "Demo.');\n"
                                                               '    }\n'
                                                               '    try {\n'
                                                               '      await _client.functions.invoke(\n'
                                                               "        'financial-ocr',\n"
                                                               "        body: {'job_id': jobId},\n"
                                                               '      );\n'
                                                               '    } catch (_) {\n'
                                                               '      final latest = await job(jobId);\n'
                                                               "      final status = latest['status']?.toString();\n"
                                                               "      if (status == 'unconfigured' || status == "
                                                               "'failed') return latest;\n"
                                                               '      rethrow;\n'
                                                               '    }\n'
                                                               '    return job(jobId);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<Map<String, dynamic>> retry(String jobId) '
                                                               'async {\n'
                                                               '    if (AppConfig.demoMode) {\n'
                                                               "      throw StateError('OCR não disponível em "
                                                               "Demo.');\n"
                                                               '    }\n'
                                                               '    await _client.rpc(\n'
                                                               "      'retry_financial_ocr_job_v1',\n"
                                                               "      params: {'target_club': _clubId, 'p_job': "
                                                               'jobId},\n'
                                                               '    );\n'
                                                               '    return runOcr(jobId);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<void> saveReview({\n'
                                                               '    required Map<String, dynamic> job,\n'
                                                               '    required String supplierName,\n'
                                                               '    required String supplierTaxId,\n'
                                                               '    required String documentNumber,\n'
                                                               '    required DateTime? documentDate,\n'
                                                               '    required String currency,\n'
                                                               '    required double? subtotal,\n'
                                                               '    required double? taxTotal,\n'
                                                               '    required double? total,\n'
                                                               '    required String paymentMethod,\n'
                                                               '    required List<Map<String, dynamic>> lineItems,\n'
                                                               '    required List<String> warnings,\n'
                                                               '  }) async {\n'
                                                               '    if (AppConfig.demoMode) return;\n'
                                                               '    await _client.rpc(\n'
                                                               "      'save_financial_ocr_review_v1',\n"
                                                               '      params: {\n'
                                                               "        'target_club': _clubId,\n"
                                                               "        'p_job': job['id'].toString(),\n"
                                                               "        'p_supplier_name': supplierName.trim(),\n"
                                                               "        'p_supplier_tax_id': supplierTaxId.trim(),\n"
                                                               "        'p_document_number': documentNumber.trim(),\n"
                                                               "        'p_document_date': "
                                                               "documentDate?.toIso8601String().split('T').first,\n"
                                                               "        'p_currency': currency.trim(),\n"
                                                               "        'p_subtotal': subtotal,\n"
                                                               "        'p_tax_total': taxTotal,\n"
                                                               "        'p_total': total,\n"
                                                               "        'p_payment_method': paymentMethod.trim(),\n"
                                                               "        'p_confidence': number(job['confidence']),\n"
                                                               "        'p_line_items': lineItems,\n"
                                                               "        'p_warnings': warnings,\n"
                                                               '      },\n'
                                                               '    );\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  Future<Map<String, dynamic>> confirmBarPurchase({\n'
                                                               '    required String jobId,\n'
                                                               '    required List<Map<String, dynamic>> lines,\n'
                                                               '    required String? eventId,\n'
                                                               '    required String? accountId,\n'
                                                               '    required String paymentMethod,\n'
                                                               '    required double total,\n'
                                                               '    required String notes,\n'
                                                               '  }) async {\n'
                                                               '    if (!canRunBarOcr) {\n'
                                                               "      throw StateError('Sem permissão para confirmar "
                                                               "compras OCR no Bar.');\n"
                                                               '    }\n'
                                                               '    if (lines.isEmpty) {\n'
                                                               "      throw ArgumentError('Seleciona pelo menos uma "
                                                               "linha para entrada em stock.');\n"
                                                               '    }\n'
                                                               "    if (total <= 0) throw ArgumentError('O total deve "
                                                               "ser superior a zero.');\n"
                                                               '    final response = await _client.rpc(\n'
                                                               "      'confirm_bar_ocr_purchase_v1',\n"
                                                               '      params: {\n'
                                                               "        'target_club': _clubId,\n"
                                                               "        'p_job': jobId,\n"
                                                               "        'p_lines': lines,\n"
                                                               "        'p_event': eventId,\n"
                                                               "        'p_account': accountId,\n"
                                                               "        'p_payment_method': paymentMethod,\n"
                                                               "        'p_total': total,\n"
                                                               "        'p_notes': notes.trim(),\n"
                                                               '      },\n'
                                                               '    );\n'
                                                               '    return Map<String, dynamic>.from(response as '
                                                               'Map);\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  static bool isSupportedMime(String? mime) => const '
                                                               '{\n'
                                                               "        'image/jpeg',\n"
                                                               "        'image/png',\n"
                                                               "        'image/webp',\n"
                                                               "        'application/pdf',\n"
                                                               '      }.contains(mime?.toLowerCase());\n'
                                                               '\n'
                                                               '  static String statusLabel(String? status) => switch '
                                                               '(status) {\n'
                                                               "        'draft' => 'A preparar',\n"
                                                               "        'pending' => 'A aguardar leitura',\n"
                                                               "        'processing' => 'A analisar',\n"
                                                               "        'ready' => 'Pronto para revisão',\n"
                                                               "        'reviewed' => 'Revisto',\n"
                                                               "        'unconfigured' => 'OCR por configurar',\n"
                                                               "        'failed' => 'Falhou',\n"
                                                               "        'confirmed' => 'Confirmado',\n"
                                                               "        'cancelled' => 'Cancelado',\n"
                                                               "        _ => 'OCR',\n"
                                                               '      };\n'
                                                               '\n'
                                                               '  static List<Map<String, dynamic>> '
                                                               'lineItems(Map<String, dynamic> job) {\n'
                                                               "    final value = job['line_items'];\n"
                                                               '    if (value is! List) return const [];\n'
                                                               '    return value\n'
                                                               '        .whereType<Map>()\n'
                                                               '        .map((item) => Map<String, '
                                                               'dynamic>.from(item))\n'
                                                               '        .toList();\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  static List<String> warnings(Map<String, dynamic> '
                                                               'job) {\n'
                                                               "    final value = job['warnings'];\n"
                                                               '    if (value is! List) return const [];\n'
                                                               '    return value.map((item) => '
                                                               'item.toString()).toList();\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  static double? number(Object? value) {\n'
                                                               '    if (value is num) return value.toDouble();\n'
                                                               '    return '
                                                               "double.tryParse(value?.toString().replaceAll(',', '.') "
                                                               "?? '');\n"
                                                               '  }\n'
                                                               '\n'
                                                               '  static bool hasAmountDiscrepancy(\n'
                                                               '    Object? transactionAmount,\n'
                                                               '    Object? detectedAmount, {\n'
                                                               '    double tolerance = 0.01,\n'
                                                               '  }) {\n'
                                                               '    final expected = number(transactionAmount);\n'
                                                               '    final detected = number(detectedAmount);\n'
                                                               '    if (expected == null || detected == null) return '
                                                               'false;\n'
                                                               '    return (expected - detected).abs() > tolerance;\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  static String? suggestProductId(\n'
                                                               '    String description,\n'
                                                               '    List<Map<String, dynamic>> products,\n'
                                                               '  ) {\n'
                                                               '    final source = normalize(description);\n'
                                                               '    if (source.isEmpty) return null;\n'
                                                               '    String? bestId;\n'
                                                               '    double bestScore = 0;\n'
                                                               '    final sourceTokens = _tokens(source);\n'
                                                               '\n'
                                                               '    for (final product in products) {\n'
                                                               "      final id = product['id']?.toString();\n"
                                                               '      if (id == null || id.isEmpty) continue;\n'
                                                               '      final candidate = normalize(\n'
                                                               "        '${product['name'] ?? ''} ${product['sku'] ?? "
                                                               "''} ${product['supplier'] ?? ''}',\n"
                                                               '      );\n'
                                                               '      if (candidate.isEmpty) continue;\n'
                                                               '      var score = 0.0;\n'
                                                               '      final name = '
                                                               "normalize(product['name']?.toString() ?? '');\n"
                                                               '      if (name.isNotEmpty && (source.contains(name) || '
                                                               'name.contains(source))) {\n'
                                                               '        score += 4;\n'
                                                               '      }\n'
                                                               '      final candidateTokens = _tokens(candidate);\n'
                                                               '      if (sourceTokens.isNotEmpty) {\n'
                                                               '        final shared = '
                                                               'sourceTokens.where(candidateTokens.contains).length;\n'
                                                               '        score += shared / sourceTokens.length * 3;\n'
                                                               '      }\n'
                                                               '      if (score > bestScore) {\n'
                                                               '        bestScore = score;\n'
                                                               '        bestId = id;\n'
                                                               '      }\n'
                                                               '    }\n'
                                                               '    return bestScore >= 1.2 ? bestId : null;\n'
                                                               '  }\n'
                                                               '\n'
                                                               '  static String normalize(String value) {\n'
                                                               '    var result = value.toLowerCase();\n'
                                                               '    const replacements = {\n'
                                                               "      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': "
                                                               "'a',\n"
                                                               "      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',\n"
                                                               "      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',\n"
                                                               "      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': "
                                                               "'o',\n"
                                                               "      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': "
                                                               "'c',\n"
                                                               '    };\n'
                                                               '    replacements.forEach((from, to) => result = '
                                                               'result.replaceAll(from, to));\n'
                                                               '    return result\n'
                                                               "        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')\n"
                                                               '        .trim()\n'
                                                               "        .replaceAll(RegExp(r'\\s+'), ' ');\n"
                                                               '  }\n'
                                                               '\n'
                                                               '  static Set<String> _tokens(String value) => value\n'
                                                               "      .split(' ')\n"
                                                               '      .where((token) => token.length >= 3)\n'
                                                               '      .toSet();\n'
                                                               '\n'
                                                               '  static String safeFileName(String value) {\n'
                                                               '    final normalized = value\n'
                                                               '        .trim()\n'
                                                               "        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')\n"
                                                               "        .replaceAll(RegExp(r'_+'), '_');\n"
                                                               "    return normalized.isEmpty ? 'documento' : "
                                                               'normalized;\n'
                                                               '  }\n'
                                                               '}\n',
 'apps/mobile/lib/widgets/financial_ocr_panel.dart': "import 'package:flutter/material.dart';\n"
                                                     '\n'
                                                     "import '../repositories/financial_documents_repository.dart';\n"
                                                     "import '../repositories/financial_ocr_repository.dart';\n"
                                                     '\n'
                                                     'class FinancialOcrPanel extends StatefulWidget {\n'
                                                     '  const FinancialOcrPanel({\n'
                                                     '    super.key,\n'
                                                     '    required this.transactionId,\n'
                                                     '    required this.transactionAmount,\n'
                                                     '  });\n'
                                                     '\n'
                                                     '  final String transactionId;\n'
                                                     '  final Object? transactionAmount;\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  State<FinancialOcrPanel> createState() => '
                                                     '_FinancialOcrPanelState();\n'
                                                     '}\n'
                                                     '\n'
                                                     'class _FinancialOcrPanelState extends State<FinancialOcrPanel> '
                                                     '{\n'
                                                     '  final FinancialDocumentsRepository _documents = '
                                                     'FinancialDocumentsRepository();\n'
                                                     '  final FinancialOcrRepository _ocr = FinancialOcrRepository();\n'
                                                     '  late Future<_FinancialOcrData> _future;\n'
                                                     '  String? _busyId;\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  void initState() {\n'
                                                     '    super.initState();\n'
                                                     '    _reload();\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  void _reload() {\n'
                                                     '    _future = Future.wait<dynamic>([\n'
                                                     '      _documents.listForTransaction(widget.transactionId),\n'
                                                     '      _ocr.jobsForTransaction(widget.transactionId),\n'
                                                     '    ]).then(\n'
                                                     '      (values) => _FinancialOcrData(\n'
                                                     '        documents: List<Map<String, dynamic>>.from(values[0] as '
                                                     'List),\n'
                                                     '        jobs: List<Map<String, dynamic>>.from(values[1] as '
                                                     'List),\n'
                                                     '      ),\n'
                                                     '    );\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Future<void> _refresh() async {\n'
                                                     '    setState(_reload);\n'
                                                     '    await _future;\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Future<void> _run(Map<String, dynamic> document) async {\n'
                                                     "    final id = document['id']?.toString();\n"
                                                     '    if (id == null || id.isEmpty) return;\n'
                                                     '    setState(() => _busyId = id);\n'
                                                     '    try {\n'
                                                     '      final jobId = await _ocr.startForDocument(id);\n'
                                                     '      final result = await _ocr.runOcr(jobId);\n'
                                                     '      if (!mounted) return;\n'
                                                     '      setState(_reload);\n'
                                                     '      _showStatus(result);\n'
                                                     '    } catch (error) {\n'
                                                     '      if (!mounted) return;\n'
                                                     '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                     '        SnackBar(content: Text(error.toString())),\n'
                                                     '      );\n'
                                                     '    } finally {\n'
                                                     '      if (mounted) setState(() => _busyId = null);\n'
                                                     '    }\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Future<void> _retry(Map<String, dynamic> job) async {\n'
                                                     "    final id = job['id']?.toString();\n"
                                                     '    if (id == null || id.isEmpty) return;\n'
                                                     '    setState(() => _busyId = id);\n'
                                                     '    try {\n'
                                                     '      final result = await _ocr.retry(id);\n'
                                                     '      if (!mounted) return;\n'
                                                     '      setState(_reload);\n'
                                                     '      _showStatus(result);\n'
                                                     '    } catch (error) {\n'
                                                     '      if (!mounted) return;\n'
                                                     '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                     '        SnackBar(content: Text(error.toString())),\n'
                                                     '      );\n'
                                                     '    } finally {\n'
                                                     '      if (mounted) setState(() => _busyId = null);\n'
                                                     '    }\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  void _showStatus(Map<String, dynamic> job) {\n'
                                                     "    final status = job['status']?.toString();\n"
                                                     "    if (status == 'unconfigured') {\n"
                                                     '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                     '        const SnackBar(\n'
                                                     '          content: Text(\n'
                                                     "            'O serviço OCR está preparado, mas falta configurar "
                                                     "OPENAI_API_KEY no Supabase.',\n"
                                                     '          ),\n'
                                                     '        ),\n'
                                                     '      );\n'
                                                     "    } else if (status == 'failed') {\n"
                                                     '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                     '        SnackBar(\n'
                                                     '          content: Text(\n'
                                                     "            job['error_message']?.toString() ?? 'A leitura OCR "
                                                     "falhou.',\n"
                                                     '          ),\n'
                                                     '        ),\n'
                                                     '      );\n'
                                                     '    }\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Future<void> _review(Map<String, dynamic> job) async {\n'
                                                     '    final saved = await showDialog<bool>(\n'
                                                     '      context: context,\n'
                                                     '      builder: (context) => _FinancialOcrReviewDialog(\n'
                                                     '        repository: _ocr,\n'
                                                     '        job: job,\n'
                                                     '      ),\n'
                                                     '    );\n'
                                                     '    if (saved == true) await _refresh();\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  Widget build(BuildContext context) {\n'
                                                     '    if (!_ocr.canRunFinancialOcr) return const '
                                                     'SizedBox.shrink();\n'
                                                     '    return FutureBuilder<_FinancialOcrData>(\n'
                                                     '      future: _future,\n'
                                                     '      builder: (context, snapshot) {\n'
                                                     '        if (snapshot.hasError) {\n'
                                                     '          return Card(\n'
                                                     '            child: ListTile(\n'
                                                     '              leading: const '
                                                     'Icon(Icons.document_scanner_outlined),\n'
                                                     "              title: const Text('Leitura OCR'),\n"
                                                     "              subtitle: Text('Não foi possível carregar o OCR: "
                                                     "${snapshot.error}'),\n"
                                                     '              trailing: IconButton(\n'
                                                     '                onPressed: _refresh,\n'
                                                     '                icon: const Icon(Icons.refresh),\n'
                                                     '              ),\n'
                                                     '            ),\n'
                                                     '          );\n'
                                                     '        }\n'
                                                     '        if (!snapshot.hasData) {\n'
                                                     '          return const Card(\n'
                                                     '            child: Padding(\n'
                                                     '              padding: EdgeInsets.all(24),\n'
                                                     '              child: Center(child: '
                                                     'CircularProgressIndicator()),\n'
                                                     '            ),\n'
                                                     '          );\n'
                                                     '        }\n'
                                                     '        final data = snapshot.data!;\n'
                                                     '        final supported = data.documents\n'
                                                     '            .where((doc) => '
                                                     'FinancialOcrRepository.isSupportedMime(\n'
                                                     "                  doc['mime_type']?.toString(),\n"
                                                     '                ))\n'
                                                     '            .toList();\n'
                                                     '\n'
                                                     '        return Card(\n'
                                                     '          child: Padding(\n'
                                                     '            padding: const EdgeInsets.all(16),\n'
                                                     '            child: Column(\n'
                                                     '              crossAxisAlignment: CrossAxisAlignment.start,\n'
                                                     '              children: [\n'
                                                     '                Row(\n'
                                                     '                  children: [\n'
                                                     '                    const '
                                                     'Icon(Icons.document_scanner_outlined),\n'
                                                     '                    const SizedBox(width: 10),\n'
                                                     '                    Expanded(\n'
                                                     '                      child: Text(\n'
                                                     "                        'Leitura OCR',\n"
                                                     '                        style: Theme.of(context)\n'
                                                     '                            .textTheme\n'
                                                     '                            .titleMedium\n'
                                                     '                            ?.copyWith(fontWeight: '
                                                     'FontWeight.w800),\n'
                                                     '                      ),\n'
                                                     '                    ),\n'
                                                     '                    IconButton(\n'
                                                     "                      tooltip: 'Atualizar',\n"
                                                     '                      onPressed: _refresh,\n'
                                                     '                      icon: const Icon(Icons.refresh),\n'
                                                     '                    ),\n'
                                                     '                  ],\n'
                                                     '                ),\n'
                                                     '                const SizedBox(height: 4),\n'
                                                     '                const Text(\n'
                                                     "                  'Extrai fornecedor, NIF, data, totais e linhas "
                                                     "para revisão. '\n"
                                                     "                  'O OCR nunca altera o movimento financeiro "
                                                     "automaticamente.',\n"
                                                     '                ),\n'
                                                     '                const SizedBox(height: 12),\n'
                                                     '                if (supported.isEmpty)\n'
                                                     '                  const Text(\n'
                                                     "                    'Adiciona uma imagem JPG/PNG/WEBP ou um PDF "
                                                     "para poder executar OCR.',\n"
                                                     '                  )\n'
                                                     '                else\n'
                                                     '                  for (final document in supported) ...[\n'
                                                     '                    _documentTile(data, document),\n'
                                                     '                    const Divider(height: 20),\n'
                                                     '                  ],\n'
                                                     '              ],\n'
                                                     '            ),\n'
                                                     '          ),\n'
                                                     '        );\n'
                                                     '      },\n'
                                                     '    );\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Widget _documentTile(\n'
                                                     '    _FinancialOcrData data,\n'
                                                     '    Map<String, dynamic> document,\n'
                                                     '  ) {\n'
                                                     '    Map<String, dynamic>? job;\n'
                                                     '    for (final candidate in data.jobs) {\n'
                                                     "      if (candidate['document_id']?.toString() == "
                                                     "document['id']?.toString()) {\n"
                                                     '        job = candidate;\n'
                                                     '        break;\n'
                                                     '      }\n'
                                                     '    }\n'
                                                     "    final status = job?['status']?.toString();\n"
                                                     "    final busy = _busyId == document['id']?.toString() ||\n"
                                                     "        (job != null && _busyId == job['id']?.toString());\n"
                                                     '    final discrepancy = job != null &&\n'
                                                     '        FinancialOcrRepository.hasAmountDiscrepancy(\n'
                                                     '          widget.transactionAmount,\n'
                                                     "          job['total'],\n"
                                                     '        );\n'
                                                     '\n'
                                                     '    return Column(\n'
                                                     '      crossAxisAlignment: CrossAxisAlignment.start,\n'
                                                     '      children: [\n'
                                                     '        ListTile(\n'
                                                     '          contentPadding: EdgeInsets.zero,\n'
                                                     '          leading: Icon(\n'
                                                     '            FinancialDocumentsRepository.isPdf(document)\n'
                                                     '                ? Icons.picture_as_pdf_outlined\n'
                                                     '                : Icons.image_outlined,\n'
                                                     '          ),\n'
                                                     '          title: Text(\n'
                                                     "            document['original_file_name']?.toString() ?? "
                                                     "'Documento',\n"
                                                     '          ),\n'
                                                     '          subtitle: Text(\n'
                                                     '            job == null\n'
                                                     "                ? 'Ainda sem leitura OCR.'\n"
                                                     '                : FinancialOcrRepository.statusLabel(status),\n'
                                                     '          ),\n'
                                                     '          trailing: busy\n'
                                                     '              ? const SizedBox(\n'
                                                     '                  width: 22,\n'
                                                     '                  height: 22,\n'
                                                     '                  child: CircularProgressIndicator(strokeWidth: '
                                                     '2),\n'
                                                     '                )\n'
                                                     '              : job == null\n'
                                                     '                  ? FilledButton.tonalIcon(\n'
                                                     '                      onPressed: () => _run(document),\n'
                                                     '                      icon: const '
                                                     'Icon(Icons.document_scanner_outlined),\n'
                                                     "                      label: const Text('Ler'),\n"
                                                     '                    )\n'
                                                     '                  : null,\n'
                                                     '        ),\n'
                                                     '        if (job != null) ...[\n'
                                                     '          Wrap(\n'
                                                     '            spacing: 8,\n'
                                                     '            runSpacing: 8,\n'
                                                     '            children: [\n'
                                                     "              if ((job['supplier_name']?.toString() ?? "
                                                     "'').isNotEmpty)\n"
                                                     '                Chip(label: '
                                                     "Text(job['supplier_name'].toString())),\n"
                                                     "              if (job['document_date'] != null)\n"
                                                     '                Chip(label: '
                                                     "Text(job['document_date'].toString())),\n"
                                                     "              if (job['total'] != null)\n"
                                                     "                Chip(label: Text('Total "
                                                     "${_money(job['total'])}')),\n"
                                                     "              if (job['confidence'] != null)\n"
                                                     '                Chip(\n'
                                                     '                  label: Text(\n'
                                                     "                    'Confiança "
                                                     "${((FinancialOcrRepository.number(job['confidence']) ?? 0) * "
                                                     "100).round()}%',\n"
                                                     '                  ),\n'
                                                     '                ),\n'
                                                     '              if (discrepancy)\n'
                                                     '                const Chip(\n'
                                                     '                  avatar: Icon(Icons.warning_amber_outlined, '
                                                     'size: 18),\n'
                                                     "                  label: Text('Total difere do movimento'),\n"
                                                     '                ),\n'
                                                     '            ],\n'
                                                     '          ),\n'
                                                     "          if ((job['error_message']?.toString() ?? "
                                                     "'').isNotEmpty) ...[\n"
                                                     '            const SizedBox(height: 8),\n'
                                                     '            Text(\n'
                                                     "              job['error_message'].toString(),\n"
                                                     '              style: TextStyle(color: '
                                                     'Theme.of(context).colorScheme.error),\n'
                                                     '            ),\n'
                                                     '          ],\n'
                                                     '          const SizedBox(height: 8),\n'
                                                     '          Wrap(\n'
                                                     '            spacing: 8,\n'
                                                     '            children: [\n'
                                                     "              if (status == 'ready' || status == 'reviewed')\n"
                                                     '                OutlinedButton.icon(\n'
                                                     '                  onPressed: () => _review(job!),\n'
                                                     '                  icon: const Icon(Icons.fact_check_outlined),\n'
                                                     "                  label: Text(status == 'reviewed' ? 'Rever "
                                                     "novamente' : 'Rever OCR'),\n"
                                                     '                ),\n'
                                                     "              if (status == 'failed' || status == "
                                                     "'unconfigured')\n"
                                                     '                OutlinedButton.icon(\n'
                                                     '                  onPressed: busy ? null : () => _retry(job!),\n'
                                                     '                  icon: const Icon(Icons.refresh),\n'
                                                     "                  label: const Text('Tentar novamente'),\n"
                                                     '                ),\n'
                                                     '            ],\n'
                                                     '          ),\n'
                                                     '        ],\n'
                                                     '      ],\n'
                                                     '    );\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  static String _money(Object? value) {\n'
                                                     '    final amount = FinancialOcrRepository.number(value) ?? 0;\n'
                                                     "    return '${amount.toStringAsFixed(2).replaceAll('.', ',')} "
                                                     "€';\n"
                                                     '  }\n'
                                                     '}\n'
                                                     '\n'
                                                     'class _FinancialOcrReviewDialog extends StatefulWidget {\n'
                                                     '  const _FinancialOcrReviewDialog({\n'
                                                     '    required this.repository,\n'
                                                     '    required this.job,\n'
                                                     '  });\n'
                                                     '\n'
                                                     '  final FinancialOcrRepository repository;\n'
                                                     '  final Map<String, dynamic> job;\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  State<_FinancialOcrReviewDialog> createState() =>\n'
                                                     '      _FinancialOcrReviewDialogState();\n'
                                                     '}\n'
                                                     '\n'
                                                     'class _FinancialOcrReviewDialogState\n'
                                                     '    extends State<_FinancialOcrReviewDialog> {\n'
                                                     '  late final TextEditingController supplier;\n'
                                                     '  late final TextEditingController nif;\n'
                                                     '  late final TextEditingController number;\n'
                                                     '  late final TextEditingController date;\n'
                                                     '  late final TextEditingController currency;\n'
                                                     '  late final TextEditingController subtotal;\n'
                                                     '  late final TextEditingController tax;\n'
                                                     '  late final TextEditingController total;\n'
                                                     '  late final TextEditingController payment;\n'
                                                     '  bool saving = false;\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  void initState() {\n'
                                                     '    super.initState();\n'
                                                     '    supplier = TextEditingController(text: '
                                                     "widget.job['supplier_name']?.toString() ?? '');\n"
                                                     '    nif = TextEditingController(text: '
                                                     "widget.job['supplier_tax_id']?.toString() ?? '');\n"
                                                     '    number = TextEditingController(text: '
                                                     "widget.job['document_number']?.toString() ?? '');\n"
                                                     '    date = TextEditingController(text: '
                                                     "widget.job['document_date']?.toString() ?? '');\n"
                                                     '    currency = TextEditingController(text: '
                                                     "widget.job['currency']?.toString() ?? 'EUR');\n"
                                                     '    subtotal = TextEditingController(text: '
                                                     "_numText(widget.job['subtotal']));\n"
                                                     '    tax = TextEditingController(text: '
                                                     "_numText(widget.job['tax_total']));\n"
                                                     '    total = TextEditingController(text: '
                                                     "_numText(widget.job['total']));\n"
                                                     '    payment = TextEditingController(text: '
                                                     "widget.job['payment_method']?.toString() ?? '');\n"
                                                     '  }\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  void dispose() {\n'
                                                     '    for (final controller in [supplier, nif, number, date, '
                                                     'currency, subtotal, tax, total, payment]) {\n'
                                                     '      controller.dispose();\n'
                                                     '    }\n'
                                                     '    super.dispose();\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  Future<void> _save() async {\n'
                                                     '    setState(() => saving = true);\n'
                                                     '    try {\n'
                                                     '      final parsedDate = date.text.trim().isEmpty\n'
                                                     '          ? null\n'
                                                     '          : DateTime.tryParse(date.text.trim());\n'
                                                     '      if (date.text.trim().isNotEmpty && parsedDate == null) {\n'
                                                     "        throw ArgumentError('Usa a data no formato "
                                                     "AAAA-MM-DD.');\n"
                                                     '      }\n'
                                                     '      await widget.repository.saveReview(\n'
                                                     '        job: widget.job,\n'
                                                     '        supplierName: supplier.text,\n'
                                                     '        supplierTaxId: nif.text,\n'
                                                     '        documentNumber: number.text,\n'
                                                     '        documentDate: parsedDate,\n'
                                                     '        currency: currency.text,\n'
                                                     '        subtotal: _parseNullable(subtotal.text),\n'
                                                     '        taxTotal: _parseNullable(tax.text),\n'
                                                     '        total: _parseNullable(total.text),\n'
                                                     '        paymentMethod: payment.text,\n'
                                                     '        lineItems: '
                                                     'FinancialOcrRepository.lineItems(widget.job),\n'
                                                     '        warnings: FinancialOcrRepository.warnings(widget.job),\n'
                                                     '      );\n'
                                                     '      if (mounted) Navigator.pop(context, true);\n'
                                                     '    } catch (error) {\n'
                                                     '      if (!mounted) return;\n'
                                                     '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                     '        SnackBar(content: Text(error.toString())),\n'
                                                     '      );\n'
                                                     '    } finally {\n'
                                                     '      if (mounted) setState(() => saving = false);\n'
                                                     '    }\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  @override\n'
                                                     '  Widget build(BuildContext context) {\n'
                                                     '    final lines = FinancialOcrRepository.lineItems(widget.job);\n'
                                                     '    final warnings = '
                                                     'FinancialOcrRepository.warnings(widget.job);\n'
                                                     '    return AlertDialog(\n'
                                                     "      title: const Text('Rever leitura OCR'),\n"
                                                     '      content: SizedBox(\n'
                                                     '        width: 680,\n'
                                                     '        child: SingleChildScrollView(\n'
                                                     '          child: Column(\n'
                                                     '            mainAxisSize: MainAxisSize.min,\n'
                                                     '            children: [\n'
                                                     '              TextField(controller: supplier, decoration: const '
                                                     "InputDecoration(labelText: 'Fornecedor')),\n"
                                                     '              TextField(controller: nif, decoration: const '
                                                     "InputDecoration(labelText: 'NIF fornecedor')),\n"
                                                     '              TextField(controller: number, decoration: const '
                                                     "InputDecoration(labelText: 'N.º documento')),\n"
                                                     '              TextField(controller: date, decoration: const '
                                                     "InputDecoration(labelText: 'Data (AAAA-MM-DD)')),\n"
                                                     '              Row(\n'
                                                     '                children: [\n'
                                                     '                  Expanded(child: TextField(controller: '
                                                     'subtotal, keyboardType: const '
                                                     'TextInputType.numberWithOptions(decimal: true), decoration: '
                                                     "const InputDecoration(labelText: 'Subtotal'))),\n"
                                                     '                  const SizedBox(width: 10),\n'
                                                     '                  Expanded(child: TextField(controller: tax, '
                                                     'keyboardType: const TextInputType.numberWithOptions(decimal: '
                                                     "true), decoration: const InputDecoration(labelText: 'IVA'))),\n"
                                                     '                  const SizedBox(width: 10),\n'
                                                     '                  Expanded(child: TextField(controller: total, '
                                                     'keyboardType: const TextInputType.numberWithOptions(decimal: '
                                                     "true), decoration: const InputDecoration(labelText: 'Total'))),\n"
                                                     '                ],\n'
                                                     '              ),\n'
                                                     '              Row(\n'
                                                     '                children: [\n'
                                                     '                  Expanded(child: TextField(controller: '
                                                     'currency, decoration: const InputDecoration(labelText: '
                                                     "'Moeda'))),\n"
                                                     '                  const SizedBox(width: 10),\n'
                                                     '                  Expanded(child: TextField(controller: payment, '
                                                     "decoration: const InputDecoration(labelText: 'Pagamento "
                                                     "detetado'))),\n"
                                                     '                ],\n'
                                                     '              ),\n'
                                                     '              const SizedBox(height: 14),\n'
                                                     '              Align(\n'
                                                     '                alignment: Alignment.centerLeft,\n'
                                                     "                child: Text('${lines.length} linhas detetadas', "
                                                     'style: Theme.of(context).textTheme.titleSmall),\n'
                                                     '              ),\n'
                                                     '              for (final line in lines.take(12))\n'
                                                     '                ListTile(\n'
                                                     '                  dense: true,\n'
                                                     '                  contentPadding: EdgeInsets.zero,\n'
                                                     "                  title: Text(line['description']?.toString() ?? "
                                                     "'Linha'),\n"
                                                     "                  trailing: line['line_total'] == null ? null : "
                                                     "Text(_FinancialOcrPanelState._money(line['line_total'])),\n"
                                                     '                ),\n'
                                                     '              if (warnings.isNotEmpty) ...[\n'
                                                     '                const Divider(),\n'
                                                     '                for (final warning in warnings)\n'
                                                     '                  ListTile(\n'
                                                     '                    dense: true,\n'
                                                     '                    contentPadding: EdgeInsets.zero,\n'
                                                     '                    leading: const '
                                                     'Icon(Icons.warning_amber_outlined),\n'
                                                     '                    title: Text(warning),\n'
                                                     '                  ),\n'
                                                     '              ],\n'
                                                     '              const SizedBox(height: 8),\n'
                                                     '              const Text(\n'
                                                     "                'Guardar a revisão não altera a Tesouraria. O "
                                                     "movimento financeiro mantém os valores já registados.',\n"
                                                     '              ),\n'
                                                     '            ],\n'
                                                     '          ),\n'
                                                     '        ),\n'
                                                     '      ),\n'
                                                     '      actions: [\n'
                                                     '        TextButton(onPressed: saving ? null : () => '
                                                     "Navigator.pop(context, false), child: const Text('Cancelar')),\n"
                                                     '        FilledButton.icon(\n'
                                                     '          onPressed: saving ? null : _save,\n'
                                                     '          icon: saving\n'
                                                     '              ? const SizedBox(width: 18, height: 18, child: '
                                                     'CircularProgressIndicator(strokeWidth: 2))\n'
                                                     '              : const Icon(Icons.save_outlined),\n'
                                                     "          label: const Text('Guardar revisão'),\n"
                                                     '        ),\n'
                                                     '      ],\n'
                                                     '    );\n'
                                                     '  }\n'
                                                     '\n'
                                                     '  static String _numText(Object? value) {\n'
                                                     '    final number = FinancialOcrRepository.number(value);\n'
                                                     "    return number == null ? '' : "
                                                     "number.toStringAsFixed(2).replaceAll('.', ',');\n"
                                                     '  }\n'
                                                     '\n'
                                                     '  static double? _parseNullable(String value) {\n'
                                                     '    final clean = value.trim();\n'
                                                     '    if (clean.isEmpty) return null;\n'
                                                     "    final parsed = double.tryParse(clean.replaceAll(',', '.'));\n"
                                                     "    if (parsed == null) throw ArgumentError('Valor numérico "
                                                     "inválido: $value');\n"
                                                     '    return parsed;\n'
                                                     '  }\n'
                                                     '}\n'
                                                     '\n'
                                                     'class _FinancialOcrData {\n'
                                                     '  const _FinancialOcrData({required this.documents, required '
                                                     'this.jobs});\n'
                                                     '  final List<Map<String, dynamic>> documents;\n'
                                                     '  final List<Map<String, dynamic>> jobs;\n'
                                                     '}\n',
 'apps/mobile/lib/screens/bar_ocr_review_screen.dart': "import 'package:flutter/material.dart';\n"
                                                       '\n'
                                                       "import '../repositories/financial_ocr_repository.dart';\n"
                                                       '\n'
                                                       'class BarOcrReviewScreen extends StatefulWidget {\n'
                                                       '  const BarOcrReviewScreen({\n'
                                                       '    super.key,\n'
                                                       '    required this.job,\n'
                                                       '    required this.products,\n'
                                                       '    required this.events,\n'
                                                       '    required this.accounts,\n'
                                                       '    required this.canSelectAccount,\n'
                                                       '  });\n'
                                                       '\n'
                                                       '  final Map<String, dynamic> job;\n'
                                                       '  final List<Map<String, dynamic>> products;\n'
                                                       '  final List<Map<String, dynamic>> events;\n'
                                                       '  final List<Map<String, dynamic>> accounts;\n'
                                                       '  final bool canSelectAccount;\n'
                                                       '\n'
                                                       '  @override\n'
                                                       '  State<BarOcrReviewScreen> createState() => '
                                                       '_BarOcrReviewScreenState();\n'
                                                       '}\n'
                                                       '\n'
                                                       'class _BarOcrReviewScreenState extends '
                                                       'State<BarOcrReviewScreen> {\n'
                                                       '  final FinancialOcrRepository _repository = '
                                                       'FinancialOcrRepository();\n'
                                                       '  final TextEditingController _total = '
                                                       'TextEditingController();\n'
                                                       '  final TextEditingController _notes = '
                                                       'TextEditingController();\n'
                                                       '  final List<_OcrBarLine> _lines = [];\n'
                                                       '  String? _eventId;\n'
                                                       '  String? _accountId;\n'
                                                       "  String _paymentMethod = 'Dinheiro';\n"
                                                       '  bool _saving = false;\n'
                                                       '\n'
                                                       '  @override\n'
                                                       '  void initState() {\n'
                                                       '    super.initState();\n'
                                                       "    _total.text = _numberText(widget.job['total']);\n"
                                                       '    final ocrLines = '
                                                       'FinancialOcrRepository.lineItems(widget.job);\n'
                                                       '    for (final source in ocrLines) {\n'
                                                       "      final description = source['description']?.toString() ?? "
                                                       "'';\n"
                                                       '      final productId = '
                                                       'FinancialOcrRepository.suggestProductId(\n'
                                                       '        description,\n'
                                                       '        widget.products,\n'
                                                       '      );\n'
                                                       '      Map<String, dynamic>? product;\n'
                                                       '      if (productId != null) {\n'
                                                       '        for (final candidate in widget.products) {\n'
                                                       "          if (candidate['id']?.toString() == productId) {\n"
                                                       '            product = candidate;\n'
                                                       '            break;\n'
                                                       '          }\n'
                                                       '        }\n'
                                                       '      }\n'
                                                       '      final quantity = '
                                                       "FinancialOcrRepository.number(source['quantity']);\n"
                                                       '      final lineTotal = '
                                                       "FinancialOcrRepository.number(source['line_total']);\n"
                                                       '      var unitPrice = '
                                                       "FinancialOcrRepository.number(source['unit_price']);\n"
                                                       '      if ((unitPrice == null || unitPrice <= 0) &&\n'
                                                       '          quantity != null &&\n'
                                                       '          quantity > 0 &&\n'
                                                       '          lineTotal != null) {\n'
                                                       '        unitPrice = lineTotal / quantity;\n'
                                                       '      }\n'
                                                       '      if ((unitPrice == null || unitPrice <= 0) && product != '
                                                       'null) {\n'
                                                       '        unitPrice = '
                                                       "FinancialOcrRepository.number(product['purchase_cost']);\n"
                                                       '      }\n'
                                                       '      _lines.add(\n'
                                                       '        _OcrBarLine(\n'
                                                       '          source: source,\n'
                                                       '          productId: productId,\n'
                                                       '          included: productId != null,\n'
                                                       '          purchaseUnits: TextEditingController(\n'
                                                       '            text: quantity != null && quantity > 0 ? '
                                                       "_numberText(quantity) : '1',\n"
                                                       '          ),\n'
                                                       '          unitPrice: TextEditingController(\n'
                                                       '            text: unitPrice != null ? _numberText(unitPrice) : '
                                                       "'',\n"
                                                       '          ),\n'
                                                       '        ),\n'
                                                       '      );\n'
                                                       '    }\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  @override\n'
                                                       '  void dispose() {\n'
                                                       '    _total.dispose();\n'
                                                       '    _notes.dispose();\n'
                                                       '    for (final line in _lines) {\n'
                                                       '      line.purchaseUnits.dispose();\n'
                                                       '      line.unitPrice.dispose();\n'
                                                       '    }\n'
                                                       '    super.dispose();\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  Future<void> _confirm() async {\n'
                                                       '    final selected = <Map<String, dynamic>>[];\n'
                                                       '    for (final line in _lines.where((item) => item.included)) '
                                                       '{\n'
                                                       '      if (line.productId == null || line.productId!.isEmpty) '
                                                       '{\n'
                                                       "        throw ArgumentError('Associa um artigo do Bar a todas "
                                                       "as linhas selecionadas.');\n"
                                                       '      }\n'
                                                       '      final quantity = _parse(line.purchaseUnits.text);\n'
                                                       '      final unitPrice = _parse(line.unitPrice.text);\n'
                                                       '      if (quantity <= 0) {\n'
                                                       "        throw ArgumentError('A quantidade de compra deve ser "
                                                       "superior a zero.');\n"
                                                       '      }\n'
                                                       '      if (unitPrice < 0) {\n'
                                                       "        throw ArgumentError('O preço de compra não pode ser "
                                                       "negativo.');\n"
                                                       '      }\n'
                                                       '      selected.add({\n'
                                                       "        'product_id': line.productId,\n"
                                                       "        'purchase_units': quantity,\n"
                                                       "        'unit_price': unitPrice,\n"
                                                       "        'description': line.source['description']?.toString() "
                                                       "?? '',\n"
                                                       '      });\n'
                                                       '    }\n'
                                                       '    if (selected.isEmpty) {\n'
                                                       "      throw ArgumentError('Seleciona pelo menos uma linha do "
                                                       "talão.');\n"
                                                       '    }\n'
                                                       '    final total = _parse(_total.text);\n'
                                                       "    if (total <= 0) throw ArgumentError('Confirma o total do "
                                                       "documento.');\n"
                                                       '\n'
                                                       '    final lineTotal = selected.fold<double>(\n'
                                                       '      0,\n'
                                                       '      (sum, line) =>\n'
                                                       '          sum +\n'
                                                       "          (line['purchase_units'] as double) *\n"
                                                       "              (line['unit_price'] as double),\n"
                                                       '    );\n'
                                                       '    final confirmed = await showDialog<bool>(\n'
                                                       '      context: context,\n'
                                                       '      builder: (context) => AlertDialog(\n'
                                                       "        title: const Text('Confirmar compra do Bar'),\n"
                                                       '        content: Text(\n'
                                                       "          '${selected.length} linha(s) vão atualizar o "
                                                       "stock.\\n'\n"
                                                       "          'Será criada uma única despesa de ${_money(total)} "
                                                       "na Tesouraria.\\n\\n'\n"
                                                       "          'Total das linhas de stock: "
                                                       "${_money(lineTotal)}\\n'\n"
                                                       "          'Total do documento: ${_money(total)}\\n\\n'\n"
                                                       "          'Confirma estes dados depois de verificares o talão "
                                                       "original?',\n"
                                                       '        ),\n'
                                                       '        actions: [\n'
                                                       '          TextButton(\n'
                                                       '            onPressed: () => Navigator.pop(context, false),\n'
                                                       "            child: const Text('Voltar'),\n"
                                                       '          ),\n'
                                                       '          FilledButton(\n'
                                                       '            onPressed: () => Navigator.pop(context, true),\n'
                                                       "            child: const Text('Confirmar'),\n"
                                                       '          ),\n'
                                                       '        ],\n'
                                                       '      ),\n'
                                                       '    );\n'
                                                       '    if (confirmed != true) return;\n'
                                                       '\n'
                                                       '    setState(() => _saving = true);\n'
                                                       '    try {\n'
                                                       '      await _repository.saveReview(\n'
                                                       '        job: widget.job,\n'
                                                       "        supplierName: widget.job['supplier_name']?.toString() "
                                                       "?? '',\n"
                                                       '        supplierTaxId: '
                                                       "widget.job['supplier_tax_id']?.toString() ?? '',\n"
                                                       '        documentNumber: '
                                                       "widget.job['document_number']?.toString() ?? '',\n"
                                                       '        documentDate: '
                                                       "DateTime.tryParse(widget.job['document_date']?.toString() ?? "
                                                       "''),\n"
                                                       "        currency: widget.job['currency']?.toString() ?? "
                                                       "'EUR',\n"
                                                       '        subtotal: '
                                                       "FinancialOcrRepository.number(widget.job['subtotal']),\n"
                                                       '        taxTotal: '
                                                       "FinancialOcrRepository.number(widget.job['tax_total']),\n"
                                                       '        total: total,\n'
                                                       '        paymentMethod: _paymentMethod,\n'
                                                       '        lineItems: '
                                                       'FinancialOcrRepository.lineItems(widget.job),\n'
                                                       '        warnings: '
                                                       'FinancialOcrRepository.warnings(widget.job),\n'
                                                       '      );\n'
                                                       '      await _repository.confirmBarPurchase(\n'
                                                       "        jobId: widget.job['id'].toString(),\n"
                                                       '        lines: selected,\n'
                                                       '        eventId: _eventId,\n'
                                                       '        accountId: _accountId,\n'
                                                       '        paymentMethod: _paymentMethod,\n'
                                                       '        total: total,\n'
                                                       '        notes: _notes.text,\n'
                                                       '      );\n'
                                                       '      if (!mounted) return;\n'
                                                       '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                       '        const SnackBar(\n'
                                                       "          content: Text('Compra OCR confirmada: stock e "
                                                       "Tesouraria atualizados.'),\n"
                                                       '        ),\n'
                                                       '      );\n'
                                                       '      Navigator.pop(context, true);\n'
                                                       '    } catch (error) {\n'
                                                       '      if (!mounted) return;\n'
                                                       '      ScaffoldMessenger.of(context).showSnackBar(\n'
                                                       '        SnackBar(content: Text(error.toString())),\n'
                                                       '      );\n'
                                                       '    } finally {\n'
                                                       '      if (mounted) setState(() => _saving = false);\n'
                                                       '    }\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  @override\n'
                                                       '  Widget build(BuildContext context) {\n'
                                                       '    final warnings = '
                                                       'FinancialOcrRepository.warnings(widget.job);\n'
                                                       '    final confidence = '
                                                       "FinancialOcrRepository.number(widget.job['confidence']);\n"
                                                       '    final selectedTotal = _selectedLineTotal();\n'
                                                       '    final documentTotal = _parse(_total.text);\n'
                                                       '    final mismatch = (selectedTotal - documentTotal).abs() > '
                                                       '0.01;\n'
                                                       '\n'
                                                       '    return Scaffold(\n'
                                                       "      appBar: AppBar(title: const Text('Rever compra por "
                                                       "OCR')),\n"
                                                       '      body: ListView(\n'
                                                       '        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),\n'
                                                       '        children: [\n'
                                                       '          Card(\n'
                                                       '            child: Padding(\n'
                                                       '              padding: const EdgeInsets.all(16),\n'
                                                       '              child: Column(\n'
                                                       '                crossAxisAlignment: CrossAxisAlignment.start,\n'
                                                       '                children: [\n'
                                                       '                  Text(\n'
                                                       '                    '
                                                       "widget.job['supplier_name']?.toString().isNotEmpty == true\n"
                                                       '                        ? '
                                                       "widget.job['supplier_name'].toString()\n"
                                                       "                        : 'Documento sem fornecedor "
                                                       "identificado',\n"
                                                       '                    style: Theme.of(context)\n'
                                                       '                        .textTheme\n'
                                                       '                        .titleLarge\n'
                                                       '                        ?.copyWith(fontWeight: '
                                                       'FontWeight.w900),\n'
                                                       '                  ),\n'
                                                       '                  const SizedBox(height: 6),\n'
                                                       '                  Text(\n'
                                                       '                    [\n'
                                                       '                      if '
                                                       "((widget.job['supplier_tax_id']?.toString() ?? "
                                                       "'').isNotEmpty)\n"
                                                       "                        'NIF "
                                                       "${widget.job['supplier_tax_id']}',\n"
                                                       '                      '
                                                       "widget.job['document_number']?.toString(),\n"
                                                       '                      '
                                                       "widget.job['document_date']?.toString(),\n"
                                                       "                      if (confidence != null) 'Confiança "
                                                       "${(confidence * 100).round()}%',\n"
                                                       '                    ].whereType<String>().where((v) => '
                                                       "v.isNotEmpty).join(' • '),\n"
                                                       '                  ),\n'
                                                       '                  if (warnings.isNotEmpty) ...[\n'
                                                       '                    const SizedBox(height: 10),\n'
                                                       '                    for (final warning in warnings)\n'
                                                       '                      Padding(\n'
                                                       '                        padding: const EdgeInsets.only(bottom: '
                                                       '4),\n'
                                                       '                        child: Row(\n'
                                                       '                          crossAxisAlignment: '
                                                       'CrossAxisAlignment.start,\n'
                                                       '                          children: [\n'
                                                       '                            const '
                                                       'Icon(Icons.warning_amber_outlined, size: 18),\n'
                                                       '                            const SizedBox(width: 6),\n'
                                                       '                            Expanded(child: Text(warning)),\n'
                                                       '                          ],\n'
                                                       '                        ),\n'
                                                       '                      ),\n'
                                                       '                  ],\n'
                                                       '                ],\n'
                                                       '              ),\n'
                                                       '            ),\n'
                                                       '          ),\n'
                                                       '          const SizedBox(height: 12),\n'
                                                       '          if (_lines.isEmpty)\n'
                                                       '            const Card(\n'
                                                       '              child: ListTile(\n'
                                                       '                leading: Icon(Icons.warning_amber_outlined),\n'
                                                       "                title: Text('O OCR não encontrou linhas de "
                                                       "artigos.'),\n"
                                                       "                subtitle: Text('Não é possível atualizar stock "
                                                       "sem linhas confirmadas.'),\n"
                                                       '              ),\n'
                                                       '            )\n'
                                                       '          else\n'
                                                       '            for (var index = 0; index < _lines.length; '
                                                       'index++)\n'
                                                       '              _lineCard(index, _lines[index]),\n'
                                                       '          const SizedBox(height: 12),\n'
                                                       '          Card(\n'
                                                       '            child: Padding(\n'
                                                       '              padding: const EdgeInsets.all(16),\n'
                                                       '              child: Column(\n'
                                                       '                crossAxisAlignment: CrossAxisAlignment.start,\n'
                                                       '                children: [\n'
                                                       "                  Text('Lançamento financeiro', style: "
                                                       'Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: '
                                                       'FontWeight.w800)),\n'
                                                       '                  const SizedBox(height: 10),\n'
                                                       '                  TextField(\n'
                                                       '                    controller: _total,\n'
                                                       '                    onChanged: (_) => setState(() {}),\n'
                                                       '                    keyboardType: const '
                                                       'TextInputType.numberWithOptions(decimal: true),\n'
                                                       '                    decoration: const '
                                                       "InputDecoration(labelText: 'Total do documento (€)'),\n"
                                                       '                  ),\n'
                                                       '                  const SizedBox(height: 10),\n'
                                                       '                  DropdownButtonFormField<String>(\n'
                                                       "                    initialValue: _eventId ?? '',\n"
                                                       '                    decoration: const '
                                                       "InputDecoration(labelText: 'Evento (opcional)'),\n"
                                                       '                    items: [\n'
                                                       '                      const DropdownMenuItem<String>(value: '
                                                       "'', child: Text('Sem evento')),\n"
                                                       '                      ...widget.events.map((event) => '
                                                       "DropdownMenuItem<String>(value: event['id']?.toString() ?? '', "
                                                       "child: Text(event['name']?.toString() ?? 'Evento'))),\n"
                                                       '                    ],\n'
                                                       '                    onChanged: (value) => setState(() => '
                                                       '_eventId = value == null || value.isEmpty ? null : value),\n'
                                                       '                  ),\n'
                                                       '                  if (widget.canSelectAccount) ...[\n'
                                                       '                    const SizedBox(height: 10),\n'
                                                       '                    DropdownButtonFormField<String>(\n'
                                                       "                      initialValue: _accountId ?? '',\n"
                                                       '                      decoration: const '
                                                       "InputDecoration(labelText: 'Conta da Tesouraria'),\n"
                                                       '                      items: [\n'
                                                       '                        const DropdownMenuItem<String>(value: '
                                                       "'', child: Text('Automática (Caixa)')),\n"
                                                       '                        ...widget.accounts.map((account) => '
                                                       "DropdownMenuItem<String>(value: account['id']?.toString() ?? "
                                                       "'', child: Text(account['name']?.toString() ?? 'Conta'))),\n"
                                                       '                      ],\n'
                                                       '                      onChanged: (value) => setState(() => '
                                                       '_accountId = value == null || value.isEmpty ? null : value),\n'
                                                       '                    ),\n'
                                                       '                  ],\n'
                                                       '                  const SizedBox(height: 10),\n'
                                                       '                  DropdownButtonFormField<String>(\n'
                                                       '                    initialValue: _paymentMethod,\n'
                                                       '                    decoration: const '
                                                       "InputDecoration(labelText: 'Método de pagamento'),\n"
                                                       '                    items: const [\n'
                                                       "                      DropdownMenuItem(value: 'Dinheiro', "
                                                       "child: Text('Dinheiro')),\n"
                                                       "                      DropdownMenuItem(value: 'MB Way', child: "
                                                       "Text('MB Way')),\n"
                                                       "                      DropdownMenuItem(value: 'Transferência "
                                                       "bancária', child: Text('Transferência bancária')),\n"
                                                       "                      DropdownMenuItem(value: 'Cartão', child: "
                                                       "Text('Cartão')),\n"
                                                       "                      DropdownMenuItem(value: 'Outro', child: "
                                                       "Text('Outro')),\n"
                                                       '                    ],\n'
                                                       '                    onChanged: (value) => setState(() => '
                                                       "_paymentMethod = value ?? 'Dinheiro'),\n"
                                                       '                  ),\n'
                                                       '                  const SizedBox(height: 10),\n'
                                                       '                  TextField(controller: _notes, maxLines: 2, '
                                                       "decoration: const InputDecoration(labelText: 'Notas')), \n"
                                                       '                  const SizedBox(height: 12),\n'
                                                       '                  Wrap(\n'
                                                       '                    spacing: 8,\n'
                                                       '                    runSpacing: 8,\n'
                                                       '                    children: [\n'
                                                       "                      Chip(label: Text('Linhas selecionadas "
                                                       "${_lines.where((line) => line.included).length}')),\n"
                                                       "                      Chip(label: Text('Linhas "
                                                       "${_money(selectedTotal)}')),\n"
                                                       "                      Chip(label: Text('Documento "
                                                       "${_money(documentTotal)}')),\n"
                                                       '                      if (mismatch)\n'
                                                       '                        const Chip(\n'
                                                       '                          avatar: Icon(Icons.info_outline, '
                                                       'size: 18),\n'
                                                       "                          label: Text('Totais diferentes — "
                                                       "confirma descontos/depósitos/outros'),\n"
                                                       '                        ),\n'
                                                       '                    ],\n'
                                                       '                  ),\n'
                                                       '                  const SizedBox(height: 10),\n'
                                                       '                  const Text(\n'
                                                       "                    'Nenhum valor é lançado automaticamente. "
                                                       'Só ao confirmar abaixo são atualizados stock e Tesouraria numa '
                                                       "única operação.',\n"
                                                       '                  ),\n'
                                                       '                ],\n'
                                                       '              ),\n'
                                                       '            ),\n'
                                                       '          ),\n'
                                                       '        ],\n'
                                                       '      ),\n'
                                                       '      bottomNavigationBar: SafeArea(\n'
                                                       '        child: Padding(\n'
                                                       '          padding: const EdgeInsets.all(12),\n'
                                                       '          child: FilledButton.icon(\n'
                                                       '            onPressed: _saving ? null : () async {\n'
                                                       '              try {\n'
                                                       '                await _confirm();\n'
                                                       '              } catch (error) {\n'
                                                       '                if (!mounted) return;\n'
                                                       '                '
                                                       'ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: '
                                                       'Text(error.toString())));\n'
                                                       '              }\n'
                                                       '            },\n'
                                                       '            icon: _saving\n'
                                                       '                ? const SizedBox(width: 20, height: 20, child: '
                                                       'CircularProgressIndicator(strokeWidth: 2))\n'
                                                       '                : const Icon(Icons.fact_check_outlined),\n'
                                                       "            label: const Text('Confirmar entrada de stock + "
                                                       "despesa'),\n"
                                                       '          ),\n'
                                                       '        ),\n'
                                                       '      ),\n'
                                                       '    );\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  Widget _lineCard(int index, _OcrBarLine line) {\n'
                                                       "    final description = line.source['description']?.toString() "
                                                       "?? 'Linha ${index + 1}';\n"
                                                       '    return Card(\n'
                                                       '      child: Padding(\n'
                                                       '        padding: const EdgeInsets.all(12),\n'
                                                       '        child: Column(\n'
                                                       '          children: [\n'
                                                       '            CheckboxListTile(\n'
                                                       '              contentPadding: EdgeInsets.zero,\n'
                                                       '              value: line.included,\n'
                                                       '              title: Text(description),\n'
                                                       '              subtitle: Text(\n'
                                                       '                [\n'
                                                       "                  if (line.source['quantity'] != null) 'Qtd "
                                                       "OCR ${line.source['quantity']}',\n"
                                                       "                  if (line.source['unit_price'] != null) "
                                                       "'Preço OCR ${line.source['unit_price']}',\n"
                                                       "                  if (line.source['line_total'] != null) "
                                                       "'Total OCR ${line.source['line_total']}',\n"
                                                       "                ].join(' • '),\n"
                                                       '              ),\n'
                                                       '              onChanged: (value) => setState(() => '
                                                       'line.included = value ?? false),\n'
                                                       '            ),\n'
                                                       '            DropdownButtonFormField<String>(\n'
                                                       "              initialValue: line.productId ?? '',\n"
                                                       '              decoration: const InputDecoration(labelText: '
                                                       "'Artigo do Bar'),\n"
                                                       '              items: [\n'
                                                       "                const DropdownMenuItem<String>(value: '', "
                                                       "child: Text('Não associado')),\n"
                                                       '                ...widget.products.map((product) => '
                                                       "DropdownMenuItem<String>(value: product['id']?.toString() ?? "
                                                       "'', child: Text(product['name']?.toString() ?? 'Artigo'))),\n"
                                                       '              ],\n'
                                                       '              onChanged: (value) {\n'
                                                       '                setState(() {\n'
                                                       '                  final selected = value == null || '
                                                       'value.isEmpty ? null : value;\n'
                                                       '                  line.productId = selected;\n'
                                                       '                  if (selected != null) line.included = true;\n'
                                                       '                  if (selected != null && '
                                                       '_parse(line.unitPrice.text) <= 0) {\n'
                                                       '                    Map<String, dynamic>? product;\n'
                                                       '                    for (final candidate in widget.products) '
                                                       '{\n'
                                                       "                      if (candidate['id']?.toString() == "
                                                       'selected) {\n'
                                                       '                        product = candidate;\n'
                                                       '                        break;\n'
                                                       '                      }\n'
                                                       '                    }\n'
                                                       '                    final purchaseCost = '
                                                       "FinancialOcrRepository.number(product?['purchase_cost']);\n"
                                                       '                    if (purchaseCost != null) '
                                                       'line.unitPrice.text = _numberText(purchaseCost);\n'
                                                       '                  }\n'
                                                       '                });\n'
                                                       '              },\n'
                                                       '            ),\n'
                                                       '            const SizedBox(height: 10),\n'
                                                       '            Row(\n'
                                                       '              children: [\n'
                                                       '                Expanded(\n'
                                                       '                  child: TextField(\n'
                                                       '                    controller: line.purchaseUnits,\n'
                                                       '                    onChanged: (_) => setState(() {}),\n'
                                                       '                    keyboardType: const '
                                                       'TextInputType.numberWithOptions(decimal: true),\n'
                                                       '                    decoration: const '
                                                       "InputDecoration(labelText: 'Qtd. embalagens compra'),\n"
                                                       '                  ),\n'
                                                       '                ),\n'
                                                       '                const SizedBox(width: 10),\n'
                                                       '                Expanded(\n'
                                                       '                  child: TextField(\n'
                                                       '                    controller: line.unitPrice,\n'
                                                       '                    onChanged: (_) => setState(() {}),\n'
                                                       '                    keyboardType: const '
                                                       'TextInputType.numberWithOptions(decimal: true),\n'
                                                       '                    decoration: const '
                                                       "InputDecoration(labelText: 'Preço / embalagem (€)'),\n"
                                                       '                  ),\n'
                                                       '                ),\n'
                                                       '              ],\n'
                                                       '            ),\n'
                                                       '          ],\n'
                                                       '        ),\n'
                                                       '      ),\n'
                                                       '    );\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  double _selectedLineTotal() {\n'
                                                       '    var total = 0.0;\n'
                                                       '    for (final line in _lines.where((item) => item.included)) '
                                                       '{\n'
                                                       '      total += _parse(line.purchaseUnits.text) * '
                                                       '_parse(line.unitPrice.text);\n'
                                                       '    }\n'
                                                       '    return total;\n'
                                                       '  }\n'
                                                       '\n'
                                                       '  static double _parse(String value) => '
                                                       "double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;\n"
                                                       '\n'
                                                       '  static String _numberText(Object? value) {\n'
                                                       '    final number = FinancialOcrRepository.number(value);\n'
                                                       "    if (number == null) return '';\n"
                                                       '    return number == number.roundToDouble()\n'
                                                       '        ? number.toInt().toString()\n'
                                                       "        : number.toStringAsFixed(2).replaceAll('.', ',');\n"
                                                       '  }\n'
                                                       '\n'
                                                       '  static String _money(Object? value) {\n'
                                                       '    final number = value is num ? value.toDouble() : '
                                                       "_parse(value?.toString() ?? '');\n"
                                                       "    return '${number.toStringAsFixed(2).replaceAll('.', ',')} "
                                                       "€';\n"
                                                       '  }\n'
                                                       '}\n'
                                                       '\n'
                                                       'class _OcrBarLine {\n'
                                                       '  _OcrBarLine({\n'
                                                       '    required this.source,\n'
                                                       '    required this.productId,\n'
                                                       '    required this.included,\n'
                                                       '    required this.purchaseUnits,\n'
                                                       '    required this.unitPrice,\n'
                                                       '  });\n'
                                                       '\n'
                                                       '  final Map<String, dynamic> source;\n'
                                                       '  String? productId;\n'
                                                       '  bool included;\n'
                                                       '  final TextEditingController purchaseUnits;\n'
                                                       '  final TextEditingController unitPrice;\n'
                                                       '}\n',
 'apps/mobile/test/financial_ocr_module_test.dart': 'import '
                                                    "'package:bob_manager_mobile/repositories/financial_ocr_repository.dart';\n"
                                                    "import 'package:flutter_test/flutter_test.dart';\n"
                                                    '\n'
                                                    'void main() {\n'
                                                    "  group('Commit 11 OCR financeiro e Bar', () {\n"
                                                    "    test('aceita apenas MIME suportado', () {\n"
                                                    '      '
                                                    "expect(FinancialOcrRepository.isSupportedMime('image/jpeg'), "
                                                    'isTrue);\n'
                                                    '      '
                                                    "expect(FinancialOcrRepository.isSupportedMime('application/pdf'), "
                                                    'isTrue);\n'
                                                    '      '
                                                    "expect(FinancialOcrRepository.isSupportedMime('text/plain'), "
                                                    'isFalse);\n'
                                                    '    });\n'
                                                    '\n'
                                                    "    test('apresenta estados OCR em português', () {\n"
                                                    "      expect(FinancialOcrRepository.statusLabel('ready'), 'Pronto "
                                                    "para revisão');\n"
                                                    "      expect(FinancialOcrRepository.statusLabel('unconfigured'), "
                                                    "'OCR por configurar');\n"
                                                    "      expect(FinancialOcrRepository.statusLabel('confirmed'), "
                                                    "'Confirmado');\n"
                                                    '    });\n'
                                                    '\n'
                                                    "    test('extrai linhas estruturadas do job', () {\n"
                                                    '      final lines = FinancialOcrRepository.lineItems({\n'
                                                    "        'line_items': [\n"
                                                    "          {'description': 'Água 6x', 'quantity': 2},\n"
                                                    '        ],\n'
                                                    '      });\n'
                                                    '      expect(lines, hasLength(1));\n'
                                                    "      expect(lines.first['description'], 'Água 6x');\n"
                                                    '    });\n'
                                                    '\n'
                                                    "    test('deteta discrepância de total financeiro', () {\n"
                                                    '      expect(FinancialOcrRepository.hasAmountDiscrepancy(100, '
                                                    '100.005), isFalse);\n'
                                                    '      expect(FinancialOcrRepository.hasAmountDiscrepancy(100, '
                                                    '101), isTrue);\n'
                                                    '    });\n'
                                                    '\n'
                                                    "    test('sugere artigo por nome normalizado', () {\n"
                                                    '      final products = <Map<String, dynamic>>[\n'
                                                    "        {'id': 'beer', 'name': 'Cerveja Super Bock', 'sku': '', "
                                                    "'supplier': ''},\n"
                                                    "        {'id': 'water', 'name': 'Água 50 cl', 'sku': '', "
                                                    "'supplier': ''},\n"
                                                    '      ];\n'
                                                    '      expect(\n'
                                                    "        FinancialOcrRepository.suggestProductId('CERVEJA SUPER "
                                                    "BOCK 20L', products),\n"
                                                    "        'beer',\n"
                                                    '      );\n'
                                                    '      expect(\n'
                                                    "        FinancialOcrRepository.suggestProductId('Agua 50 CL "
                                                    "pack', products),\n"
                                                    "        'water',\n"
                                                    '      );\n'
                                                    '    });\n'
                                                    '\n'
                                                    "    test('não força associação de linha sem semelhança "
                                                    "suficiente', () {\n"
                                                    '      final products = <Map<String, dynamic>>[\n'
                                                    "        {'id': 'beer', 'name': 'Cerveja', 'sku': '', 'supplier': "
                                                    "''},\n"
                                                    '      ];\n'
                                                    '      expect(\n'
                                                    "        FinancialOcrRepository.suggestProductId('Guardanapos "
                                                    "papel', products),\n"
                                                    '        isNull,\n'
                                                    '      );\n'
                                                    '    });\n'
                                                    '  });\n'
                                                    '}\n',
 'supabase/migrations/20260811202432_rc1_financial_ocr_foundation.sql': '-- Commit 11 — OCR financeiro e Bar: fundação '
                                                                        'auditada.\n'
                                                                        '-- O OCR apenas propõe dados. Confirmações '
                                                                        'financeiras continuam explícitas.\n'
                                                                        '\n'
                                                                        'create table if not exists '
                                                                        'public.financial_ocr_jobs (\n'
                                                                        '  id uuid primary key default '
                                                                        'gen_random_uuid(),\n'
                                                                        '  club_id uuid not null references '
                                                                        'public.clubs(id) on delete cascade,\n'
                                                                        '  source_kind text not null check '
                                                                        '(source_kind in '
                                                                        "('transaction_document','bar_import')),\n"
                                                                        '  document_id uuid references '
                                                                        'public.financial_transaction_documents(id) on '
                                                                        'delete set null,\n'
                                                                        '  transaction_id uuid references '
                                                                        'public.treasury_transactions(id) on delete '
                                                                        'set null,\n'
                                                                        '  storage_path text,\n'
                                                                        '  original_file_name text,\n'
                                                                        '  mime_type text,\n'
                                                                        '  file_size bigint not null default 0 check '
                                                                        '(file_size >= 0 and file_size <= 20971520),\n'
                                                                        "  status text not null default 'draft'\n"
                                                                        '    check (status in '
                                                                        "('draft','pending','processing','ready','reviewed','unconfigured','failed','confirmed','cancelled')),\n"
                                                                        "  provider text not null default 'openai',\n"
                                                                        '  model text,\n'
                                                                        '  provider_response_id text,\n'
                                                                        '  supplier_name text,\n'
                                                                        '  supplier_tax_id text,\n'
                                                                        '  document_number text,\n'
                                                                        '  document_date date,\n'
                                                                        '  currency text,\n'
                                                                        '  subtotal numeric,\n'
                                                                        '  tax_total numeric,\n'
                                                                        '  total numeric,\n'
                                                                        '  payment_method text,\n'
                                                                        '  confidence numeric check (confidence is '
                                                                        'null or (confidence >= 0 and confidence <= '
                                                                        '1)),\n'
                                                                        '  raw_text text,\n'
                                                                        '  line_items jsonb not null default '
                                                                        "'[]'::jsonb check "
                                                                        "(jsonb_typeof(line_items)='array'),\n"
                                                                        "  warnings jsonb not null default '[]'::jsonb "
                                                                        "check (jsonb_typeof(warnings)='array'),\n"
                                                                        "  usage jsonb not null default '{}'::jsonb "
                                                                        "check (jsonb_typeof(usage)='object'),\n"
                                                                        '  error_message text,\n'
                                                                        '  started_at timestamptz,\n'
                                                                        '  completed_at timestamptz,\n'
                                                                        '  reviewed_at timestamptz,\n'
                                                                        '  reviewed_by uuid references '
                                                                        'public.profiles(id) on delete set null,\n'
                                                                        '  confirmed_at timestamptz,\n'
                                                                        '  confirmed_by uuid references '
                                                                        'public.profiles(id) on delete set null,\n'
                                                                        '  confirmed_transaction_id uuid references '
                                                                        'public.treasury_transactions(id) on delete '
                                                                        'set null,\n'
                                                                        '  confirmed_lines jsonb not null default '
                                                                        "'[]'::jsonb check "
                                                                        "(jsonb_typeof(confirmed_lines)='array'),\n"
                                                                        '  created_at timestamptz not null default '
                                                                        'now(),\n'
                                                                        '  created_by uuid references '
                                                                        'public.profiles(id) on delete set null '
                                                                        'default auth.uid(),\n'
                                                                        '  updated_at timestamptz not null default '
                                                                        'now(),\n'
                                                                        '  updated_by uuid references '
                                                                        'public.profiles(id) on delete set null '
                                                                        'default auth.uid()\n'
                                                                        ');\n'
                                                                        '\n'
                                                                        'create index if not exists '
                                                                        'idx_financial_ocr_jobs_club_created\n'
                                                                        '  on '
                                                                        'public.financial_ocr_jobs(club_id,created_at '
                                                                        'desc);\n'
                                                                        'create index if not exists '
                                                                        'idx_financial_ocr_jobs_document\n'
                                                                        '  on '
                                                                        'public.financial_ocr_jobs(document_id,created_at '
                                                                        'desc) where document_id is not null;\n'
                                                                        'create index if not exists '
                                                                        'idx_financial_ocr_jobs_status\n'
                                                                        '  on '
                                                                        'public.financial_ocr_jobs(club_id,status,updated_at '
                                                                        'desc);\n'
                                                                        '\n'
                                                                        'drop trigger if exists '
                                                                        'trg_financial_ocr_audit_stamp_v1 on '
                                                                        'public.financial_ocr_jobs;\n'
                                                                        'create trigger '
                                                                        'trg_financial_ocr_audit_stamp_v1\n'
                                                                        'before insert or update on '
                                                                        'public.financial_ocr_jobs\n'
                                                                        'for each row execute function '
                                                                        'public.audit_stamp_row_v1();\n'
                                                                        '\n'
                                                                        'drop trigger if exists '
                                                                        'trg_financial_ocr_audit_capture_v1 on '
                                                                        'public.financial_ocr_jobs;\n'
                                                                        'create trigger '
                                                                        'trg_financial_ocr_audit_capture_v1\n'
                                                                        'after insert or update or delete on '
                                                                        'public.financial_ocr_jobs\n'
                                                                        'for each row execute function '
                                                                        'public.audit_capture_row_v1();\n'
                                                                        '\n'
                                                                        'alter table public.financial_ocr_jobs enable '
                                                                        'row level security;\n'
                                                                        'drop policy if exists '
                                                                        'financial_ocr_jobs_select on '
                                                                        'public.financial_ocr_jobs;\n'
                                                                        'create policy financial_ocr_jobs_select on '
                                                                        'public.financial_ocr_jobs\n'
                                                                        'for select to authenticated using (\n'
                                                                        "  case when source_kind='bar_import' then\n"
                                                                        '    '
                                                                        "public.has_club_permission(club_id,'manageBar')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(club_id,'viewInventory')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(club_id,'viewTreasury')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(club_id,'approveExpenseRequests')\n"
                                                                        '  else\n'
                                                                        '    '
                                                                        "public.has_club_permission(club_id,'viewTreasury')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(club_id,'approveExpenseRequests')\n"
                                                                        '  end\n'
                                                                        ');\n'
                                                                        'grant select on table '
                                                                        'public.financial_ocr_jobs to authenticated;\n'
                                                                        'revoke insert,update,delete on table '
                                                                        'public.financial_ocr_jobs from '
                                                                        'anon,authenticated;\n'
                                                                        '\n'
                                                                        'create or replace function '
                                                                        'public.create_bar_ocr_job_v1(target_club '
                                                                        'uuid)\n'
                                                                        'returns uuid language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare v_id uuid;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null or not '
                                                                        "public.has_club_permission(target_club,'manageBar') "
                                                                        'then\n'
                                                                        "    raise exception 'Sem autorização para "
                                                                        "usar OCR no Bar.';\n"
                                                                        '  end if;\n'
                                                                        '  insert into '
                                                                        'public.financial_ocr_jobs(club_id,source_kind,status,provider)\n'
                                                                        '  '
                                                                        "values(target_club,'bar_import','draft','openai') "
                                                                        'returning id into v_id;\n'
                                                                        '  return v_id;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        'create or replace function '
                                                                        'public.attach_bar_ocr_source_v1(\n'
                                                                        '  target_club uuid,p_job uuid,p_storage_path '
                                                                        'text,p_original_file_name text,p_mime_type '
                                                                        'text,p_file_size bigint\n'
                                                                        ') returns void language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare j public.financial_ocr_jobs%rowtype;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null or not '
                                                                        "public.has_club_permission(target_club,'manageBar') "
                                                                        "then raise exception 'Sem autorização para "
                                                                        "usar OCR no Bar.'; end if;\n"
                                                                        '  select * into j from '
                                                                        'public.financial_ocr_jobs where id=p_job and '
                                                                        'club_id=target_club and '
                                                                        "source_kind='bar_import' for update;\n"
                                                                        "  if not found then raise exception 'Pedido "
                                                                        "OCR não encontrado.'; end if;\n"
                                                                        '  if j.status not in '
                                                                        "('draft','failed','unconfigured') then raise "
                                                                        "exception 'O pedido OCR já não aceita outro "
                                                                        "ficheiro.'; end if;\n"
                                                                        '  if p_file_size is null or p_file_size<=0 or '
                                                                        "p_file_size>20971520 then raise exception 'O "
                                                                        "ficheiro deve ter entre 1 byte e 20 MB.'; end "
                                                                        'if;\n'
                                                                        "  if lower(coalesce(p_mime_type,'')) not in "
                                                                        "('image/jpeg','image/png','image/webp','application/pdf') "
                                                                        "then raise exception 'Formato OCR não "
                                                                        "suportado. Usa JPG, PNG, WEBP ou PDF.'; end "
                                                                        'if;\n'
                                                                        '  if p_storage_path not like '
                                                                        "target_club::text||'/ocr/'||p_job::text||'/%' "
                                                                        "then raise exception 'Caminho OCR inválido.'; "
                                                                        'end if;\n'
                                                                        '  update public.financial_ocr_jobs\n'
                                                                        '  set '
                                                                        "storage_path=p_storage_path,original_file_name=coalesce(nullif(btrim(p_original_file_name),''),'documento'),\n"
                                                                        '      '
                                                                        "mime_type=lower(p_mime_type),file_size=p_file_size,status='pending',error_message=null,started_at=null,completed_at=null\n"
                                                                        '  where id=p_job;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        'create or replace function '
                                                                        'public.start_financial_document_ocr_v1(target_club '
                                                                        'uuid,p_document uuid)\n'
                                                                        'returns uuid language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare d '
                                                                        'public.financial_transaction_documents%rowtype; '
                                                                        'j public.financial_ocr_jobs%rowtype; v_id '
                                                                        'uuid;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null or not (\n'
                                                                        '    '
                                                                        "public.has_club_permission(target_club,'createTreasuryMovement')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(target_club,'approveExpenseRequests')\n"
                                                                        "  ) then raise exception 'Sem autorização "
                                                                        "para executar OCR financeiro.'; end if;\n"
                                                                        '  select * into d from '
                                                                        'public.financial_transaction_documents where '
                                                                        'id=p_document and club_id=target_club;\n'
                                                                        '  if not found then raise exception '
                                                                        "'Documento financeiro não encontrado.'; end "
                                                                        'if;\n'
                                                                        "  if lower(coalesce(d.mime_type,'')) not in "
                                                                        "('image/jpeg','image/png','image/webp','application/pdf') "
                                                                        "then raise exception 'Formato OCR não "
                                                                        "suportado. Usa JPG, PNG, WEBP ou PDF.'; end "
                                                                        'if;\n'
                                                                        '  select * into j from '
                                                                        'public.financial_ocr_jobs\n'
                                                                        '  where club_id=target_club and '
                                                                        'document_id=p_document and status in '
                                                                        "('pending','processing','ready','reviewed','unconfigured')\n"
                                                                        '  order by created_at desc limit 1;\n'
                                                                        '  if found then\n'
                                                                        "    if j.status='unconfigured' then\n"
                                                                        '      update public.financial_ocr_jobs set '
                                                                        "status='pending',error_message=null,started_at=null,completed_at=null "
                                                                        'where id=j.id;\n'
                                                                        '    end if;\n'
                                                                        '    return j.id;\n'
                                                                        '  end if;\n'
                                                                        '  insert into public.financial_ocr_jobs(\n'
                                                                        '    '
                                                                        'club_id,source_kind,document_id,transaction_id,storage_path,original_file_name,mime_type,file_size,status,provider\n'
                                                                        '  ) values (\n'
                                                                        '    '
                                                                        "target_club,'transaction_document',d.id,d.transaction_id,d.storage_path,d.original_file_name,d.mime_type,d.file_size,'pending','openai'\n"
                                                                        '  ) returning id into v_id;\n'
                                                                        '  return v_id;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        'create or replace function '
                                                                        'public.retry_financial_ocr_job_v1(target_club '
                                                                        'uuid,p_job uuid)\n'
                                                                        'returns void language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare j public.financial_ocr_jobs%rowtype; '
                                                                        'v_allowed boolean;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null then raise exception '
                                                                        "'Sessão inválida.'; end if;\n"
                                                                        '  select * into j from '
                                                                        'public.financial_ocr_jobs where id=p_job and '
                                                                        'club_id=target_club for update;\n'
                                                                        "  if not found then raise exception 'Pedido "
                                                                        "OCR não encontrado.'; end if;\n"
                                                                        '  v_allowed:=case when '
                                                                        "j.source_kind='bar_import'\n"
                                                                        '    then '
                                                                        "public.has_club_permission(target_club,'manageBar')\n"
                                                                        '    else '
                                                                        "public.has_club_permission(target_club,'createTreasuryMovement') "
                                                                        'or '
                                                                        "public.has_club_permission(target_club,'approveExpenseRequests') "
                                                                        'end;\n'
                                                                        "  if not v_allowed then raise exception 'Sem "
                                                                        "autorização para repetir este OCR.'; end if;\n"
                                                                        '  if j.storage_path is null then raise '
                                                                        "exception 'Pedido OCR sem ficheiro.'; end "
                                                                        'if;\n'
                                                                        '  if j.status in '
                                                                        "('processing','confirmed','cancelled') then "
                                                                        "raise exception 'O pedido OCR não pode ser "
                                                                        "repetido neste estado.'; end if;\n"
                                                                        '  update public.financial_ocr_jobs set '
                                                                        "status='pending',error_message=null,started_at=null,completed_at=null "
                                                                        'where id=p_job;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        'create or replace function '
                                                                        'public.save_financial_ocr_review_v1(\n'
                                                                        '  target_club uuid,p_job uuid,p_supplier_name '
                                                                        'text,p_supplier_tax_id text,p_document_number '
                                                                        'text,p_document_date date,\n'
                                                                        '  p_currency text,p_subtotal '
                                                                        'numeric,p_tax_total numeric,p_total '
                                                                        'numeric,p_payment_method text,p_confidence '
                                                                        'numeric,\n'
                                                                        '  p_line_items jsonb,p_warnings jsonb\n'
                                                                        ') returns void language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare j public.financial_ocr_jobs%rowtype; '
                                                                        'v_allowed boolean;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null then raise exception '
                                                                        "'Sessão inválida.'; end if;\n"
                                                                        '  select * into j from '
                                                                        'public.financial_ocr_jobs where id=p_job and '
                                                                        'club_id=target_club for update;\n'
                                                                        "  if not found then raise exception 'Pedido "
                                                                        "OCR não encontrado.'; end if;\n"
                                                                        '  v_allowed:=case when '
                                                                        "j.source_kind='bar_import'\n"
                                                                        '    then '
                                                                        "public.has_club_permission(target_club,'manageBar')\n"
                                                                        '    else '
                                                                        "public.has_club_permission(target_club,'createTreasuryMovement') "
                                                                        'or '
                                                                        "public.has_club_permission(target_club,'approveExpenseRequests') "
                                                                        'end;\n'
                                                                        "  if not v_allowed then raise exception 'Sem "
                                                                        "autorização para rever este OCR.'; end if;\n"
                                                                        "  if j.status not in ('ready','reviewed') "
                                                                        "then raise exception 'O OCR ainda não está "
                                                                        "pronto para revisão.'; end if;\n"
                                                                        '  if p_line_items is null or '
                                                                        "jsonb_typeof(p_line_items)<>'array' then "
                                                                        "raise exception 'Linhas OCR inválidas.'; end "
                                                                        'if;\n'
                                                                        '  if p_warnings is null or '
                                                                        "jsonb_typeof(p_warnings)<>'array' then raise "
                                                                        "exception 'Avisos OCR inválidos.'; end if;\n"
                                                                        '  update public.financial_ocr_jobs set\n'
                                                                        '    '
                                                                        "supplier_name=nullif(btrim(coalesce(p_supplier_name,'')),''),supplier_tax_id=nullif(btrim(coalesce(p_supplier_tax_id,'')),''),\n"
                                                                        '    '
                                                                        "document_number=nullif(btrim(coalesce(p_document_number,'')),''),document_date=p_document_date,\n"
                                                                        '    '
                                                                        "currency=upper(nullif(btrim(coalesce(p_currency,'')),'')),subtotal=p_subtotal,tax_total=p_tax_total,total=p_total,\n"
                                                                        '    '
                                                                        "payment_method=nullif(btrim(coalesce(p_payment_method,'')),''),\n"
                                                                        '    confidence=case when p_confidence is null '
                                                                        'then confidence else '
                                                                        'greatest(0,least(1,p_confidence)) end,\n'
                                                                        '    '
                                                                        "line_items=p_line_items,warnings=p_warnings,status='reviewed',reviewed_at=now(),reviewed_by=auth.uid()\n"
                                                                        '  where id=p_job;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        '-- Evidência originada por OCR fica protegida '
                                                                        'tal como os comprovativos herdados.\n'
                                                                        'create or replace function '
                                                                        'public.delete_financial_transaction_document_v1(target_club '
                                                                        'uuid,p_transaction uuid,p_document uuid)\n'
                                                                        'returns text language plpgsql security '
                                                                        'definer set search_path=public as $$\n'
                                                                        'declare d '
                                                                        'public.financial_transaction_documents%rowtype; '
                                                                        'v_path text;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null or not (\n'
                                                                        '    '
                                                                        "public.has_club_permission(target_club,'createTreasuryMovement')\n"
                                                                        '    or '
                                                                        "public.has_club_permission(target_club,'approveExpenseRequests')\n"
                                                                        "  ) then raise exception 'Sem autorização "
                                                                        "para gerir documentos financeiros.'; end if;\n"
                                                                        '  select * into d from '
                                                                        'public.financial_transaction_documents\n'
                                                                        '  where id=p_document and '
                                                                        'transaction_id=p_transaction and '
                                                                        'club_id=target_club for update;\n'
                                                                        '  if not found then raise exception '
                                                                        "'Documento não encontrado.'; end if;\n"
                                                                        '  if d.source_attachment_id is not null or '
                                                                        "d.origin in ('request','bar_ocr') then\n"
                                                                        "    raise exception 'Este documento pertence "
                                                                        'ao processo financeiro original e não pode '
                                                                        "ser eliminado aqui.';\n"
                                                                        '  end if;\n'
                                                                        '  v_path:=d.storage_path;\n'
                                                                        '  delete from '
                                                                        'public.financial_transaction_documents where '
                                                                        'id=d.id;\n'
                                                                        '  perform '
                                                                        'public.refresh_financial_transaction_primary_v1(p_transaction);\n'
                                                                        '  return v_path;\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        '-- O bucket financial-documents passa a '
                                                                        'aceitar caminhos privados /ocr/<job>/...\n'
                                                                        'create or replace function '
                                                                        'public.financial_storage_access_v2(p_name '
                                                                        'text,p_manage boolean default false)\n'
                                                                        'returns boolean language plpgsql stable '
                                                                        'security definer set '
                                                                        'search_path=public,storage as $$\n'
                                                                        'declare folders text[]; v_request uuid; '
                                                                        'v_transaction uuid; v_job uuid; v_club uuid;\n'
                                                                        'begin\n'
                                                                        '  if auth.uid() is null then return false; '
                                                                        'end if;\n'
                                                                        '  folders:=storage.foldername(p_name);\n'
                                                                        '  if coalesce(array_length(folders,1),0)<2 '
                                                                        'then return false; end if;\n'
                                                                        "  if folders[2]='transactions' then\n"
                                                                        '    if coalesce(array_length(folders,1),0)<3 '
                                                                        'then return false; end if;\n'
                                                                        '    begin v_transaction:=folders[3]::uuid; '
                                                                        'exception when invalid_text_representation '
                                                                        'then return false; end;\n'
                                                                        '    select t.club_id into v_club from '
                                                                        'public.treasury_transactions t where '
                                                                        't.id=v_transaction;\n'
                                                                        '    if not found or folders[1] is distinct '
                                                                        'from v_club::text then return false; end if;\n'
                                                                        '    if p_manage then return '
                                                                        "public.has_club_permission(v_club,'createTreasuryMovement') "
                                                                        'or '
                                                                        "public.has_club_permission(v_club,'approveExpenseRequests'); "
                                                                        'end if;\n'
                                                                        '    return '
                                                                        "public.has_club_permission(v_club,'viewTreasury') "
                                                                        'or '
                                                                        "public.has_club_permission(v_club,'approveExpenseRequests');\n"
                                                                        '  end if;\n'
                                                                        "  if folders[2]='ocr' then\n"
                                                                        '    if coalesce(array_length(folders,1),0)<3 '
                                                                        'then return false; end if;\n'
                                                                        '    begin v_job:=folders[3]::uuid; exception '
                                                                        'when invalid_text_representation then return '
                                                                        'false; end;\n'
                                                                        '    select j.club_id into v_club from '
                                                                        'public.financial_ocr_jobs j where '
                                                                        'j.id=v_job;\n'
                                                                        '    if not found or folders[1] is distinct '
                                                                        'from v_club::text then return false; end if;\n'
                                                                        '    if p_manage then\n'
                                                                        '      return '
                                                                        "public.has_club_permission(v_club,'manageBar')\n"
                                                                        '        or '
                                                                        "public.has_club_permission(v_club,'createTreasuryMovement')\n"
                                                                        '        or '
                                                                        "public.has_club_permission(v_club,'approveExpenseRequests');\n"
                                                                        '    end if;\n'
                                                                        '    return '
                                                                        "public.has_club_permission(v_club,'manageBar')\n"
                                                                        '      or '
                                                                        "public.has_club_permission(v_club,'viewInventory')\n"
                                                                        '      or '
                                                                        "public.has_club_permission(v_club,'viewTreasury')\n"
                                                                        '      or '
                                                                        "public.has_club_permission(v_club,'approveExpenseRequests');\n"
                                                                        '  end if;\n'
                                                                        '  begin v_request:=folders[2]::uuid; '
                                                                        'exception when invalid_text_representation '
                                                                        'then return false; end;\n'
                                                                        '  select r.club_id into v_club from '
                                                                        'public.financial_requests r where '
                                                                        'r.id=v_request;\n'
                                                                        '  if not found or folders[1] is distinct from '
                                                                        'v_club::text then return false; end if;\n'
                                                                        '  return '
                                                                        'public.financial_request_access_v1(v_request);\n'
                                                                        'end; $$;\n'
                                                                        '\n'
                                                                        'revoke all on function '
                                                                        'public.create_bar_ocr_job_v1(uuid) from '
                                                                        'public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.create_bar_ocr_job_v1(uuid) to '
                                                                        'authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.attach_bar_ocr_source_v1(uuid,uuid,text,text,text,bigint) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.attach_bar_ocr_source_v1(uuid,uuid,text,text,text,bigint) '
                                                                        'to authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.start_financial_document_ocr_v1(uuid,uuid) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.start_financial_document_ocr_v1(uuid,uuid) '
                                                                        'to authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.retry_financial_ocr_job_v1(uuid,uuid) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.retry_financial_ocr_job_v1(uuid,uuid) '
                                                                        'to authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.save_financial_ocr_review_v1(uuid,uuid,text,text,text,date,text,numeric,numeric,numeric,text,numeric,jsonb,jsonb) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.save_financial_ocr_review_v1(uuid,uuid,text,text,text,date,text,numeric,numeric,numeric,text,numeric,jsonb,jsonb) '
                                                                        'to authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.delete_financial_transaction_document_v1(uuid,uuid,uuid) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.delete_financial_transaction_document_v1(uuid,uuid,uuid) '
                                                                        'to authenticated;\n'
                                                                        'revoke all on function '
                                                                        'public.financial_storage_access_v2(text,boolean) '
                                                                        'from public,anon;\n'
                                                                        'grant execute on function '
                                                                        'public.financial_storage_access_v2(text,boolean) '
                                                                        'to authenticated;\n',
 'supabase/migrations/20260811202501_rc1_bar_ocr_confirmation.sql': '-- Commit 11 — confirmação atómica de uma compra '
                                                                    'OCR do Bar.\n'
                                                                    '-- Várias linhas de stock -> uma única despesa '
                                                                    'financeira.\n'
                                                                    '\n'
                                                                    'create or replace function '
                                                                    'public.confirm_bar_ocr_purchase_v1(\n'
                                                                    '  target_club uuid,\n'
                                                                    '  p_job uuid,\n'
                                                                    '  p_lines jsonb,\n'
                                                                    '  p_event uuid default null,\n'
                                                                    '  p_account uuid default null,\n'
                                                                    "  p_payment_method text default 'Dinheiro',\n"
                                                                    '  p_total numeric default null,\n'
                                                                    '  p_notes text default null\n'
                                                                    ')\n'
                                                                    'returns jsonb\n'
                                                                    'language plpgsql\n'
                                                                    'security definer\n'
                                                                    'set search_path=public\n'
                                                                    'as $$\n'
                                                                    'declare\n'
                                                                    '  j public.financial_ocr_jobs%rowtype;\n'
                                                                    '  r jsonb;\n'
                                                                    '  v_product public.products%rowtype;\n'
                                                                    '  v_product_id uuid;\n'
                                                                    '  v_purchase_units numeric;\n'
                                                                    '  v_unit_price numeric;\n'
                                                                    '  v_quantity numeric;\n'
                                                                    '  v_new_stock numeric;\n'
                                                                    '  v_purchase_unit_cost numeric;\n'
                                                                    '  v_new_average_cost numeric;\n'
                                                                    '  v_line_total numeric;\n'
                                                                    '  v_lines_total numeric:=0;\n'
                                                                    '  v_account uuid;\n'
                                                                    '  v_cost_center uuid;\n'
                                                                    '  v_tx uuid;\n'
                                                                    '  v_desc text;\n'
                                                                    '  v_note text;\n'
                                                                    '  v_line_count integer:=0;\n'
                                                                    'begin\n'
                                                                    '  if auth.uid() is null or not '
                                                                    "public.has_club_permission(target_club,'manageBar') "
                                                                    'then\n'
                                                                    "    raise exception 'Sem autorização para "
                                                                    "confirmar compras OCR no Bar.';\n"
                                                                    '  end if;\n'
                                                                    '  if p_lines is null or '
                                                                    "jsonb_typeof(p_lines)<>'array' or "
                                                                    'jsonb_array_length(p_lines)=0 then\n'
                                                                    "    raise exception 'Seleciona pelo menos uma "
                                                                    "linha do documento para entrada em stock.';\n"
                                                                    '  end if;\n'
                                                                    '\n'
                                                                    '  select * into j from public.financial_ocr_jobs\n'
                                                                    '  where id=p_job and club_id=target_club and '
                                                                    "source_kind='bar_import' for update;\n"
                                                                    "  if not found then raise exception 'Pedido OCR "
                                                                    "do Bar não encontrado.'; end if;\n"
                                                                    "  if j.status not in ('ready','reviewed') then "
                                                                    "raise exception 'O OCR tem de estar "
                                                                    "pronto/revisto antes da confirmação.'; end if;\n"
                                                                    '  if j.storage_path is null or j.file_size<=0 '
                                                                    "then raise exception 'Pedido OCR sem documento "
                                                                    "original.'; end if;\n"
                                                                    '\n'
                                                                    '  if p_event is not null and not exists(select 1 '
                                                                    'from public.events where id=p_event and '
                                                                    "club_id=target_club) then raise exception 'Evento "
                                                                    "inválido.'; end if;\n"
                                                                    '\n'
                                                                    '  if p_account is not null then\n'
                                                                    '    if not '
                                                                    "public.has_club_permission(target_club,'selectBarFinancialAccount') "
                                                                    "then raise exception 'Sem autorização para "
                                                                    "escolher a conta financeira do Bar.'; end if;\n"
                                                                    '    select id into v_account from '
                                                                    'public.treasury_accounts where id=p_account and '
                                                                    'club_id=target_club and active=true;\n'
                                                                    '    if v_account is null then raise exception '
                                                                    "'Conta financeira inválida ou inativa.'; end if;\n"
                                                                    '  else\n'
                                                                    '    select id into v_account from '
                                                                    'public.treasury_accounts where '
                                                                    'club_id=target_club and active=true and '
                                                                    "lower(name)=lower('Caixa') limit 1;\n"
                                                                    '    if v_account is null then select id into '
                                                                    'v_account from public.treasury_accounts where '
                                                                    'club_id=target_club and active=true order by '
                                                                    'created_at limit 1; end if;\n'
                                                                    '    if v_account is null then raise exception '
                                                                    "'Não existe nenhuma conta financeira ativa.'; end "
                                                                    'if;\n'
                                                                    '  end if;\n'
                                                                    '\n'
                                                                    '  select id into v_cost_center from '
                                                                    'public.cost_centers\n'
                                                                    '  where club_id=target_club and active=true and '
                                                                    "lower(name)=lower('Club House') limit 1;\n"
                                                                    '\n'
                                                                    '  -- Primeiro valida todas as linhas, antes de '
                                                                    'qualquer movimento contabilístico.\n'
                                                                    '  for r in select value from '
                                                                    'jsonb_array_elements(p_lines) loop\n'
                                                                    '    begin\n'
                                                                    "      v_product_id:=(r->>'product_id')::uuid;\n"
                                                                    '      '
                                                                    "v_purchase_units:=(r->>'purchase_units')::numeric;\n"
                                                                    "      v_unit_price:=(r->>'unit_price')::numeric;\n"
                                                                    '    exception when others then raise exception '
                                                                    "'Linha OCR com produto, quantidade ou preço "
                                                                    "inválido.'; end;\n"
                                                                    '    if v_purchase_units<=0 or v_unit_price<0 then '
                                                                    "raise exception 'Quantidade e preço das linhas "
                                                                    "OCR têm de ser válidos.'; end if;\n"
                                                                    '    select * into v_product from public.products\n'
                                                                    '    where id=v_product_id and club_id=target_club '
                                                                    "and inventory_area='bar' and active=true;\n"
                                                                    "    if not found then raise exception 'Artigo de "
                                                                    "Bar inválido numa linha OCR.'; end if;\n"
                                                                    '    if '
                                                                    'coalesce(v_product.units_per_purchase,0)<=0 then '
                                                                    "raise exception 'Conversão inválida no artigo "
                                                                    "%.',v_product.name; end if;\n"
                                                                    '    '
                                                                    'v_lines_total:=v_lines_total+(v_purchase_units*v_unit_price);\n'
                                                                    '    v_line_count:=v_line_count+1;\n'
                                                                    '  end loop;\n'
                                                                    '\n'
                                                                    '  if p_total is null or p_total<=0 then '
                                                                    'p_total:=v_lines_total; end if;\n'
                                                                    "  if p_total<=0 then raise exception 'Total "
                                                                    "financeiro inválido.'; end if;\n"
                                                                    '\n'
                                                                    "  v_desc:='Compra Bar OCR';\n"
                                                                    '  if '
                                                                    "coalesce(nullif(btrim(j.supplier_name),''),'')<>'' "
                                                                    "then v_desc:=v_desc||' - '||j.supplier_name; end "
                                                                    'if;\n'
                                                                    '  '
                                                                    "v_note:=nullif(btrim(coalesce(p_notes,'')),'');\n"
                                                                    '  if abs(p_total-v_lines_total)>0.01 then\n'
                                                                    "    v_note:=concat_ws(' | ',v_note,\n"
                                                                    "      'OCR: total do documento "
                                                                    "'||to_char(p_total,'FM999999990.00')||' €; linhas "
                                                                    'de stock '
                                                                    "'||to_char(v_lines_total,'FM999999990.00')||' "
                                                                    "€');\n"
                                                                    '  end if;\n'
                                                                    '\n'
                                                                    '  insert into public.treasury_transactions(\n'
                                                                    '    '
                                                                    'club_id,kind,account_id,cost_center_id,event_id,transaction_date,description,amount,\n'
                                                                    '    '
                                                                    'payment_method,notes,source_type,source_id,created_by\n'
                                                                    '  ) values (\n'
                                                                    '    '
                                                                    "target_club,'expense'::public.transaction_kind,v_account,v_cost_center,p_event,\n"
                                                                    '    '
                                                                    "coalesce(j.document_date,current_date),v_desc,p_total,p_payment_method,v_note,'bar_ocr',j.id,auth.uid()\n"
                                                                    '  ) returning id into v_tx;\n'
                                                                    '\n'
                                                                    '  for r in select value from '
                                                                    'jsonb_array_elements(p_lines) loop\n'
                                                                    "    v_product_id:=(r->>'product_id')::uuid;\n"
                                                                    '    '
                                                                    "v_purchase_units:=(r->>'purchase_units')::numeric;\n"
                                                                    "    v_unit_price:=(r->>'unit_price')::numeric;\n"
                                                                    '    select * into v_product from public.products\n'
                                                                    '    where id=v_product_id and club_id=target_club '
                                                                    "and inventory_area='bar' and active=true for "
                                                                    'update;\n'
                                                                    '\n'
                                                                    '    '
                                                                    'v_quantity:=v_purchase_units*v_product.units_per_purchase;\n'
                                                                    '    '
                                                                    'v_new_stock:=coalesce(v_product.current_stock,0)+v_quantity;\n'
                                                                    '    '
                                                                    'v_purchase_unit_cost:=v_unit_price/v_product.units_per_purchase;\n'
                                                                    '    v_new_average_cost:=case when v_new_stock>0 '
                                                                    'then\n'
                                                                    '      '
                                                                    '((coalesce(v_product.current_stock,0)*coalesce(v_product.cost,0))+(v_quantity*v_purchase_unit_cost))/v_new_stock\n'
                                                                    '      else v_purchase_unit_cost end;\n'
                                                                    '    v_line_total:=v_purchase_units*v_unit_price;\n'
                                                                    '\n'
                                                                    '    update public.products set '
                                                                    'current_stock=v_new_stock,purchase_cost=v_unit_price,cost=v_new_average_cost '
                                                                    'where id=v_product.id;\n'
                                                                    '    insert into '
                                                                    'public.stock_movements(club_id,product_id,event_id,kind,quantity,unit_cost,notes,created_by)\n'
                                                                    '    '
                                                                    "values(target_club,v_product.id,p_event,'purchase',v_quantity,v_purchase_unit_cost,\n"
                                                                    "      concat_ws(' | ','Entrada via "
                                                                    "OCR',nullif(r->>'description','')),auth.uid());\n"
                                                                    '    insert into public.bar_operations(\n'
                                                                    '      '
                                                                    'club_id,product_id,event_id,operation_type,purchase_units,consumption_quantity,unit_price,total_amount,\n'
                                                                    '      '
                                                                    'payment_method,notes,treasury_transaction_id,created_by\n'
                                                                    '    ) values (\n'
                                                                    '      '
                                                                    "target_club,v_product.id,p_event,'purchase',v_purchase_units,v_quantity,v_unit_price,v_line_total,\n"
                                                                    "      p_payment_method,concat_ws(' | "
                                                                    "','OCR',nullif(r->>'description','')),v_tx,auth.uid()\n"
                                                                    '    );\n'
                                                                    '  end loop;\n'
                                                                    '\n'
                                                                    '  insert into '
                                                                    'public.financial_transaction_documents(\n'
                                                                    '    '
                                                                    'club_id,transaction_id,document_type,origin,storage_path,original_file_name,mime_type,file_size,is_primary\n'
                                                                    '  ) values (\n'
                                                                    '    '
                                                                    "target_club,v_tx,'receipt','bar_ocr',j.storage_path,coalesce(j.original_file_name,'documento'),j.mime_type,j.file_size,true\n"
                                                                    '  ) on conflict(transaction_id,storage_path) do '
                                                                    'nothing;\n'
                                                                    '  perform '
                                                                    'public.refresh_financial_transaction_primary_v1(v_tx);\n'
                                                                    '\n'
                                                                    '  update public.financial_ocr_jobs\n'
                                                                    '  set '
                                                                    "status='confirmed',confirmed_at=now(),confirmed_by=auth.uid(),confirmed_transaction_id=v_tx,\n"
                                                                    '      '
                                                                    'confirmed_lines=p_lines,transaction_id=v_tx\n'
                                                                    '  where id=j.id;\n'
                                                                    '\n'
                                                                    '  perform public.emit_domain_event(\n'
                                                                    '    '
                                                                    "target_club,'BarOcrPurchaseConfirmed','inventory',v_product_id,\n"
                                                                    '    jsonb_build_object(\n'
                                                                    '      '
                                                                    "'title',v_desc,'description',v_line_count::text||' "
                                                                    "linhas · '||to_char(p_total,'FM999999990.00')||' "
                                                                    "€',\n"
                                                                    '      '
                                                                    "'module_code','inventory','route','inventory','priority','normal','ocr_job_id',j.id,'transaction_id',v_tx\n"
                                                                    '    )\n'
                                                                    '  );\n'
                                                                    '\n'
                                                                    '  return jsonb_build_object(\n'
                                                                    '    '
                                                                    "'job_id',j.id,'transaction_id',v_tx,'account_id',v_account,'line_count',v_line_count,\n"
                                                                    '    '
                                                                    "'lines_total',v_lines_total,'financial_total',p_total\n"
                                                                    '  );\n'
                                                                    'end;\n'
                                                                    '$$;\n'
                                                                    '\n'
                                                                    'revoke all on function '
                                                                    'public.confirm_bar_ocr_purchase_v1(uuid,uuid,jsonb,uuid,uuid,text,numeric,text) '
                                                                    'from public,anon;\n'
                                                                    'grant execute on function '
                                                                    'public.confirm_bar_ocr_purchase_v1(uuid,uuid,jsonb,uuid,uuid,text,numeric,text) '
                                                                    'to authenticated;\n',
 'supabase/functions/financial-ocr/index.ts': "import { createClient } from 'npm:@supabase/supabase-js@2';\n"
                                              '\n'
                                              "const jsonHeaders = { 'Content-Type': 'application/json' };\n"
                                              '\n'
                                              'const schema = {\n'
                                              "  type: 'object',\n"
                                              '  additionalProperties: false,\n'
                                              '  required: [\n'
                                              '    '
                                              "'supplier_name','supplier_tax_id','document_number','document_date','currency',\n"
                                              '    '
                                              "'subtotal','tax_total','total','payment_method','confidence','raw_text','line_items','warnings',\n"
                                              '  ],\n'
                                              '  properties: {\n'
                                              "    supplier_name: { type: ['string','null'] },\n"
                                              "    supplier_tax_id: { type: ['string','null'] },\n"
                                              "    document_number: { type: ['string','null'] },\n"
                                              "    document_date: { type: ['string','null'], description: 'YYYY-MM-DD "
                                              "quando legível.' },\n"
                                              "    currency: { type: ['string','null'], description: 'Código ISO, "
                                              "normalmente EUR.' },\n"
                                              "    subtotal: { type: ['number','null'] },\n"
                                              "    tax_total: { type: ['number','null'] },\n"
                                              "    total: { type: ['number','null'] },\n"
                                              "    payment_method: { type: ['string','null'] },\n"
                                              "    confidence: { type: 'number', minimum: 0, maximum: 1 },\n"
                                              "    raw_text: { type: 'string' },\n"
                                              '    line_items: {\n'
                                              "      type: 'array',\n"
                                              '      items: {\n'
                                              "        type: 'object', additionalProperties: false,\n"
                                              '        required: '
                                              "['description','quantity','unit_price','line_total','tax_rate','sku'],\n"
                                              '        properties: {\n'
                                              "          description: { type: 'string' }, quantity: { type: "
                                              "['number','null'] },\n"
                                              "          unit_price: { type: ['number','null'] }, line_total: { type: "
                                              "['number','null'] },\n"
                                              "          tax_rate: { type: ['number','null'] }, sku: { type: "
                                              "['string','null'] },\n"
                                              '        },\n'
                                              '      },\n'
                                              '    },\n'
                                              "    warnings: { type: 'array', items: { type: 'string' } },\n"
                                              '  },\n'
                                              '};\n'
                                              '\n'
                                              'const prompt = `Extrai dados deste documento comercial para revisão '
                                              'humana num sistema financeiro português.\n'
                                              'Regras obrigatórias:\n'
                                              '- Não inventes valores. Se um campo não for legível, devolve null.\n'
                                              '- Mantém os valores monetários como números decimais, sem símbolo de '
                                              'moeda.\n'
                                              '- document_date deve ser YYYY-MM-DD.\n'
                                              '- supplier_tax_id deve conter apenas o identificador fiscal quando '
                                              'estiver visível.\n'
                                              '- Em line_items, preserva a descrição comercial e extrai quantidade, '
                                              'preço unitário e total da linha quando existirem.\n'
                                              '- Não calcules valores que não estejam explícitos, exceto quando '
                                              'quantity e unit_price forem ambos claros e o total de linha também for '
                                              'inequívoco.\n'
                                              '- confidence representa confiança global entre 0 e 1.\n'
                                              '- warnings deve assinalar baixa legibilidade, totais inconsistentes, '
                                              'páginas cortadas ou outros riscos.\n'
                                              '- raw_text deve conter o texto essencial lido do documento, sem '
                                              'acrescentar explicações.\n'
                                              'Este resultado é apenas uma proposta: um utilizador irá rever antes de '
                                              'qualquer lançamento contabilístico.`;\n'
                                              '\n'
                                              'function outputText(response: Record<string, unknown>): string | null '
                                              '{\n'
                                              '  const output = Array.isArray(response.output) ? response.output : '
                                              '[];\n'
                                              '  for (const item of output) {\n'
                                              "    if (!item || typeof item !== 'object') continue;\n"
                                              '    const content = Array.isArray((item as Record<string, '
                                              'unknown>).content)\n'
                                              '      ? (item as Record<string, unknown>).content as unknown[] : [];\n'
                                              '    for (const part of content) {\n'
                                              "      if (!part || typeof part !== 'object') continue;\n"
                                              '      const p = part as Record<string, unknown>;\n'
                                              "      if (p.type === 'output_text' && typeof p.text === 'string') "
                                              'return p.text;\n'
                                              '    }\n'
                                              '  }\n'
                                              '  return null;\n'
                                              '}\n'
                                              '\n'
                                              'function validDate(value: unknown): string | null {\n'
                                              "  return typeof value === 'string' && "
                                              '/^\\d{4}-\\d{2}-\\d{2}$/.test(value) ? value : null;\n'
                                              '}\n'
                                              'function textOrNull(value: unknown): string | null {\n'
                                              "  if (typeof value !== 'string') return null;\n"
                                              '  const v = value.trim();\n'
                                              '  return v.length ? v : null;\n'
                                              '}\n'
                                              'function numberOrNull(value: unknown): number | null {\n'
                                              "  return typeof value === 'number' && Number.isFinite(value) ? value : "
                                              'null;\n'
                                              '}\n'
                                              '\n'
                                              'Deno.serve(async (req: Request) => {\n'
                                              "  if (req.method !== 'POST') {\n"
                                              "    return new Response(JSON.stringify({ error: 'method_not_allowed' "
                                              '}), { status: 405, headers: jsonHeaders });\n'
                                              '  }\n'
                                              '\n'
                                              "  const authorization = req.headers.get('Authorization') ?? '';\n"
                                              "  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';\n"
                                              "  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';\n"
                                              "  const secretKeysRaw = Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}';\n"
                                              "  let serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';\n"
                                              '  try {\n'
                                              '    const keys = JSON.parse(secretKeysRaw) as Record<string, string>;\n'
                                              '    serviceKey = keys.default ?? serviceKey;\n'
                                              '  } catch (_) {}\n'
                                              '  if (!authorization || !supabaseUrl || !anonKey || !serviceKey) {\n'
                                              '    return new Response(JSON.stringify({ error: '
                                              "'supabase_server_config_missing' }), { status: 500, headers: "
                                              'jsonHeaders });\n'
                                              '  }\n'
                                              '\n'
                                              '  const userClient = createClient(supabaseUrl, anonKey, {\n'
                                              '    auth: { persistSession: false, autoRefreshToken: false },\n'
                                              '    global: { headers: { Authorization: authorization } },\n'
                                              '  });\n'
                                              '  const admin = createClient(supabaseUrl, serviceKey, {\n'
                                              '    auth: { persistSession: false, autoRefreshToken: false },\n'
                                              '  });\n'
                                              '\n'
                                              "  let jobId = '';\n"
                                              '  try {\n'
                                              '    const body = await req.json();\n'
                                              "    jobId = String(body?.job_id ?? '');\n"
                                              '    if (!jobId) return new Response(JSON.stringify({ error: '
                                              "'job_id_required' }), { status: 400, headers: jsonHeaders });\n"
                                              '\n'
                                              '    const { data: visibleJob, error: visibleError } = await userClient\n'
                                              "      .from('financial_ocr_jobs')\n"
                                              '      '
                                              ".select('id,club_id,status,storage_path,original_file_name,mime_type,file_size')\n"
                                              "      .eq('id', jobId)\n"
                                              '      .single();\n'
                                              '    if (visibleError || !visibleJob) {\n'
                                              '      return new Response(JSON.stringify({ error: '
                                              "'ocr_job_not_accessible' }), { status: 403, headers: jsonHeaders });\n"
                                              '    }\n'
                                              '\n'
                                              "    const currentStatus = String(visibleJob.status ?? '');\n"
                                              "    if (['ready','reviewed','confirmed'].includes(currentStatus)) {\n"
                                              '      return new Response(JSON.stringify({ status: currentStatus, '
                                              'job_id: jobId }), { status: 200, headers: jsonHeaders });\n'
                                              '    }\n'
                                              "    if (currentStatus === 'processing') {\n"
                                              "      return new Response(JSON.stringify({ status: 'processing', "
                                              'job_id: jobId }), { status: 202, headers: jsonHeaders });\n'
                                              '    }\n'
                                              "    if (currentStatus !== 'pending') {\n"
                                              '      return new Response(JSON.stringify({ error: '
                                              "'ocr_job_not_pending', status: currentStatus }), { status: 409, "
                                              'headers: jsonHeaders });\n'
                                              '    }\n'
                                              '\n'
                                              '    const { data: claimed, error: claimError } = await admin\n'
                                              "      .from('financial_ocr_jobs')\n"
                                              "      .update({ status: 'processing', started_at: new "
                                              'Date().toISOString(), completed_at: null, error_message: null })\n'
                                              "      .eq('id', jobId)\n"
                                              "      .eq('status', 'pending')\n"
                                              '      '
                                              ".select('id,storage_path,original_file_name,mime_type,file_size')\n"
                                              '      .maybeSingle();\n'
                                              '    if (claimError) throw claimError;\n'
                                              '    if (!claimed) return new Response(JSON.stringify({ status: '
                                              "'already_claimed', job_id: jobId }), { status: 202, headers: "
                                              'jsonHeaders });\n'
                                              '\n'
                                              "    const storagePath = String(claimed.storage_path ?? '');\n"
                                              "    const mimeType = String(claimed.mime_type ?? '').toLowerCase();\n"
                                              '    const fileName = String(claimed.original_file_name ?? '
                                              "'documento');\n"
                                              "    if (!storagePath) throw new Error('Pedido OCR sem ficheiro.');\n"
                                              '    if '
                                              "(!['image/jpeg','image/png','image/webp','application/pdf'].includes(mimeType)) "
                                              "throw new Error('Formato OCR não suportado.');\n"
                                              '\n'
                                              "    const openAiKey = Deno.env.get('OPENAI_API_KEY') ?? '';\n"
                                              "    const model = Deno.env.get('OPENAI_OCR_MODEL') ?? 'gpt-5-mini';\n"
                                              '    if (!openAiKey) {\n'
                                              "      await admin.from('financial_ocr_jobs').update({\n"
                                              "        status: 'unconfigured',\n"
                                              '        model,\n'
                                              "        error_message: 'OPENAI_API_KEY ainda não configurado no "
                                              "Supabase.',\n"
                                              '        completed_at: new Date().toISOString(),\n'
                                              "      }).eq('id', jobId);\n"
                                              "      return new Response(JSON.stringify({ status: 'unconfigured', "
                                              "reason: 'openai_api_key_missing', job_id: jobId }), { status: 503, "
                                              'headers: jsonHeaders });\n'
                                              '    }\n'
                                              '\n'
                                              '    const { data: signed, error: signedError } = await admin.storage\n'
                                              "      .from('financial-documents')\n"
                                              '      .createSignedUrl(storagePath, 300);\n'
                                              '    if (signedError || !signed?.signedUrl) {\n'
                                              '      throw new Error(`Não foi possível obter o documento: '
                                              "${signedError?.message ?? 'URL indisponível'}`);\n"
                                              '    }\n'
                                              '\n'
                                              "    const content: Record<string, unknown>[] = [{ type: 'input_text', "
                                              'text: prompt }];\n'
                                              "    if (mimeType === 'application/pdf') {\n"
                                              "      content.push({ type: 'input_file', file_url: signed.signedUrl, "
                                              'filename: fileName });\n'
                                              '    } else {\n'
                                              "      content.push({ type: 'input_image', image_url: signed.signedUrl, "
                                              "detail: 'high' });\n"
                                              '    }\n'
                                              '\n'
                                              '    const aiResponse = await '
                                              "fetch('https://api.openai.com/v1/responses', {\n"
                                              "      method: 'POST',\n"
                                              "      headers: { 'Content-Type': 'application/json', Authorization: "
                                              '`Bearer ${openAiKey}` },\n'
                                              '      body: JSON.stringify({\n'
                                              '        model,\n'
                                              "        input: [{ role: 'user', content }],\n"
                                              "        text: { format: { type: 'json_schema', name: "
                                              "'financial_document_ocr', strict: true, schema } },\n"
                                              '        max_output_tokens: 6000,\n'
                                              '      }),\n'
                                              '    });\n'
                                              '    const raw = await aiResponse.text();\n'
                                              '    let parsedResponse: Record<string, unknown> = {};\n'
                                              '    try { parsedResponse = raw ? JSON.parse(raw) as Record<string, '
                                              'unknown> : {}; }\n'
                                              '    catch (_) { parsedResponse = { raw }; }\n'
                                              '    if (!aiResponse.ok) throw new Error(`OpenAI ${aiResponse.status}: '
                                              '${raw.slice(0, 1200)}`);\n'
                                              '\n'
                                              '    const text = outputText(parsedResponse);\n'
                                              "    if (!text) throw new Error('O serviço OCR não devolveu dados "
                                              "estruturados.');\n"
                                              '    const result = JSON.parse(text) as Record<string, unknown>;\n'
                                              "    const rawText = typeof result.raw_text === 'string' ? "
                                              "result.raw_text.slice(0, 20000) : '';\n"
                                              '    const lineItems = Array.isArray(result.line_items) ? '
                                              'result.line_items : [];\n'
                                              '    const warnings = Array.isArray(result.warnings)\n'
                                              "      ? result.warnings.filter((v) => typeof v === 'string').slice(0, "
                                              '30) : [];\n'
                                              "    const confidence = typeof result.confidence === 'number' && "
                                              'Number.isFinite(result.confidence)\n'
                                              '      ? Math.max(0, Math.min(1, result.confidence)) : 0;\n'
                                              '\n'
                                              '    const { error: updateError } = await '
                                              "admin.from('financial_ocr_jobs').update({\n"
                                              "      status: 'ready', provider: 'openai', model,\n"
                                              "      provider_response_id: typeof parsedResponse.id === 'string' ? "
                                              'parsedResponse.id : null,\n'
                                              '      supplier_name: textOrNull(result.supplier_name), supplier_tax_id: '
                                              'textOrNull(result.supplier_tax_id),\n'
                                              '      document_number: textOrNull(result.document_number), '
                                              'document_date: validDate(result.document_date),\n'
                                              '      currency: textOrNull(result.currency)?.toUpperCase() ?? null,\n'
                                              '      subtotal: numberOrNull(result.subtotal), tax_total: '
                                              'numberOrNull(result.tax_total), total: numberOrNull(result.total),\n'
                                              '      payment_method: textOrNull(result.payment_method), confidence, '
                                              'raw_text: rawText,\n'
                                              '      line_items: lineItems, warnings,\n'
                                              '      usage: parsedResponse.usage && typeof parsedResponse.usage === '
                                              "'object' ? parsedResponse.usage : {},\n"
                                              '      error_message: null, completed_at: new Date().toISOString(),\n'
                                              "    }).eq('id', jobId);\n"
                                              '    if (updateError) throw updateError;\n'
                                              '\n'
                                              "    return new Response(JSON.stringify({ status: 'ready', job_id: "
                                              'jobId, model, confidence, line_count: lineItems.length }), { status: '
                                              '200, headers: jsonHeaders });\n'
                                              '  } catch (error) {\n'
                                              '    const message = error instanceof Error ? error.message : '
                                              'String(error);\n'
                                              '    if (jobId) {\n'
                                              '      try {\n'
                                              "        await admin.from('financial_ocr_jobs').update({\n"
                                              "          status: 'failed', error_message: message.slice(0, 4000), "
                                              'completed_at: new Date().toISOString(),\n'
                                              "        }).eq('id', jobId).neq('status', 'confirmed');\n"
                                              '      } catch (_) {}\n'
                                              '    }\n'
                                              '    return new Response(JSON.stringify({ error: message, job_id: jobId '
                                              '|| null }), { status: 500, headers: jsonHeaders });\n'
                                              '  }\n'
                                              '});\n',
 'supabase/functions/financial-ocr/deno.json': '{\n  "compilerOptions": {\n    "strict": true\n  }\n}\n',
 'docs/COMMIT11_FINANCIAL_BAR_OCR.md': '# Commit 11 — OCR integrado no Financeiro / Bar\n'
                                       '\n'
                                       '## Objetivo\n'
                                       '\n'
                                       'Adicionar leitura assistida de talões, faturas, imagens e PDF sem permitir que '
                                       'um resultado OCR altere contabilidade ou stock sem revisão humana.\n'
                                       '\n'
                                       '## Fluxo Financeiro\n'
                                       '\n'
                                       '1. O utilizador abre os documentos de um movimento da Tesouraria.\n'
                                       '2. Em JPG, PNG, WEBP ou PDF pode iniciar **Ler com OCR**.\n'
                                       '3. A Edge Function privada `financial-ocr` envia o documento ao serviço OCR e '
                                       'guarda a proposta em `financial_ocr_jobs`.\n'
                                       '4. Fornecedor, NIF, número, data, subtotal, IVA, total, método de pagamento, '
                                       'texto e linhas ficam visíveis para revisão.\n'
                                       '5. O utilizador pode corrigir e guardar a revisão.\n'
                                       '6. **Nenhum campo do movimento da Tesouraria é alterado automaticamente.**\n'
                                       '\n'
                                       '## Fluxo Bar\n'
                                       '\n'
                                       '1. Em Bar > Stock, `Ler OCR` permite carregar um talão/fatura.\n'
                                       '2. O original é guardado no bucket privado `financial-documents` em '
                                       '`<club>/ocr/<job>/...`.\n'
                                       '3. O OCR propõe cabeçalho e linhas.\n'
                                       '4. Cada linha é associada manualmente a um artigo já existente do Bar. Existe '
                                       'apenas uma sugestão local por semelhança de texto; nunca é criada mercadoria '
                                       'automaticamente.\n'
                                       '5. O utilizador confirma quantidade em embalagens e preço por embalagem, '
                                       'evento, conta, método de pagamento e total.\n'
                                       '6. A confirmação é atómica no servidor: várias entradas de stock e operações '
                                       'de Bar partilham **uma única despesa da Tesouraria**.\n'
                                       '7. O documento original passa a integrar a galeria financeira com '
                                       '`origin=bar_ocr` e não pode ser eliminado por essa galeria.\n'
                                       '\n'
                                       '## Segurança e auditoria\n'
                                       '\n'
                                       '- Tabela `financial_ocr_jobs` com RLS e auditoria global.\n'
                                       '- Escrita direta pelo cliente é bloqueada; alterações passam por RPCs com '
                                       'permissões internas.\n'
                                       '- `manageBar` é obrigatório para o fluxo de compra do Bar.\n'
                                       '- OCR de documentos financeiros requer `createTreasuryMovement` ou '
                                       '`approveExpenseRequests`.\n'
                                       '- Jobs OCR não são visíveis a perfis apenas de leitura, evitando consumo '
                                       'indevido do serviço.\n'
                                       '- A Edge Function exige JWT válido.\n'
                                       '- A chave `OPENAI_API_KEY` é secret server-side do Supabase e nunca pertence '
                                       'ao Flutter/Git.\n'
                                       '- Limite por documento: 20 MB; formatos JPG/JPEG, PNG, WEBP e PDF.\n'
                                       '\n'
                                       '## Serviço OCR\n'
                                       '\n'
                                       'Edge Function: `supabase/functions/financial-ocr`.\n'
                                       '\n'
                                       'Secrets esperados:\n'
                                       '\n'
                                       '- `OPENAI_API_KEY` — obrigatório para executar OCR real.\n'
                                       '- `OPENAI_OCR_MODEL` — opcional; por omissão `gpt-5-mini`.\n'
                                       '\n'
                                       'Sem a chave, o job fica em `unconfigured`: o documento permanece guardado e '
                                       'pode ser repetido depois de configurar o secret.\n'
                                       '\n'
                                       '## Migrations\n'
                                       '\n'
                                       '- `20260811202432_rc1_financial_ocr_foundation.sql`\n'
                                       '- `20260811202501_rc1_bar_ocr_confirmation.sql`\n'
                                       '- `20260811204001_rc1_financial_ocr_hardening.sql`\n'
                                       '\n'
                                       'As migrations já foram aplicadas no projeto remoto durante a construção do '
                                       'Commit 11; os ficheiros locais preservam o histórico para instalações '
                                       'futuras.\n'
                                       '\n'
                                       '## Validação backend realizada\n'
                                       '\n'
                                       'Foi executado um teste transacional com dois artigos fictícios do Bar e um '
                                       'documento OCR fictício. A confirmação produziu, dentro da mesma transação:\n'
                                       '\n'
                                       '- 1 movimento de Tesouraria;\n'
                                       '- 2 operações de Bar;\n'
                                       '- 2 movimentos de stock;\n'
                                       '- 1 documento financeiro originado por OCR;\n'
                                       '- atualização correta dos stocks.\n'
                                       '\n'
                                       'O teste terminou com `ROLLBACK` e foi confirmada a inexistência de dados de '
                                       'teste residuais.\n',
 'supabase/migrations/20260811204001_rc1_financial_ocr_hardening.sql': '-- Commit 11 — restringe jobs OCR a perfis que '
                                                                       'podem efetivamente executar/rever o fluxo.\n'
                                                                       '\n'
                                                                       'drop policy if exists '
                                                                       'financial_ocr_jobs_select on '
                                                                       'public.financial_ocr_jobs;\n'
                                                                       'create policy financial_ocr_jobs_select on '
                                                                       'public.financial_ocr_jobs\n'
                                                                       'for select to authenticated using (\n'
                                                                       '  case\n'
                                                                       "    when source_kind='bar_import' then\n"
                                                                       '      '
                                                                       "public.has_club_permission(club_id,'manageBar')\n"
                                                                       '    else\n'
                                                                       '      '
                                                                       "public.has_club_permission(club_id,'createTreasuryMovement')\n"
                                                                       '      or '
                                                                       "public.has_club_permission(club_id,'approveExpenseRequests')\n"
                                                                       '  end\n'
                                                                       ');\n'
                                                                       '\n'
                                                                       '-- Perfis apenas de leitura continuam a '
                                                                       'consultar o documento financeiro original,\n'
                                                                       '-- mas não conseguem iniciar/consultar jobs '
                                                                       'que possam consumir o serviço OCR.\n'}

for path, content in FILES.items():
    write_file(path, content)

# Proteger evidência OCR na Galeria Financeira.
replace_once(
    "apps/mobile/lib/repositories/financial_documents_repository.dart",
    """  static bool isDeletable(Map<String, dynamic> document) =>
      document['source_attachment_id'] == null &&
      document['origin']?.toString() != 'request';""",
    """  static bool isDeletable(Map<String, dynamic> document) {
    final origin = document['origin']?.toString();
    return document['source_attachment_id'] == null &&
        origin != 'request' &&
        origin != 'bar_ocr';
  }""",
)

# Painel OCR nos documentos de Tesouraria.
replace_once(
    "apps/mobile/lib/screens/financial_transaction_documents_screen.dart",
    "import '../widgets/financial_document_gallery.dart';",
    "import '../widgets/financial_document_gallery.dart';\nimport '../widgets/financial_ocr_panel.dart';",
)
replace_once(
    "apps/mobile/lib/screens/financial_transaction_documents_screen.dart",
    """            FinancialDocumentGallery(
              repository: repository,
              transactionId: transactionId,
              canManage: repository.canManage,
              onChanged: onChanged,
            ),
          const SizedBox(height: 16),""",
    """            FinancialDocumentGallery(
              repository: repository,
              transactionId: transactionId,
              canManage: repository.canManage,
              onChanged: onChanged,
            ),
          if (transactionId.isNotEmpty && repository.canManage) ...[
            const SizedBox(height: 16),
            FinancialOcrPanel(
              transactionId: transactionId,
              transactionAmount: transaction['amount'],
            ),
          ],
          const SizedBox(height: 16),""",
)

# Entrada OCR no Bar sem dependências Flutter novas.
replace_once(
    "apps/mobile/lib/screens/bar_screen_v3.dart",
    "import 'package:flutter/material.dart';",
    "import 'package:file_picker/file_picker.dart';\nimport 'package:flutter/material.dart';",
)
replace_once(
    "apps/mobile/lib/screens/bar_screen_v3.dart",
    "import '../repositories/bar_repository.dart';",
    "import '../repositories/bar_repository.dart';\nimport '../repositories/financial_ocr_repository.dart';\nimport 'bar_ocr_review_screen.dart';",
)
replace_once(
    "apps/mobile/lib/screens/bar_screen_v3.dart",
    "  final BarRepository _repository = BarRepository();",
    "  final BarRepository _repository = BarRepository();\n  final FinancialOcrRepository _ocrRepository = FinancialOcrRepository();",
)
replace_once(
    "apps/mobile/lib/screens/bar_screen_v3.dart",
    "  Future<void> _operation(\n",
    """  Future<void> _barOcr(_BarData data) async {
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
              'Falta configurar OPENAI_API_KEY nos secrets do Supabase. '
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
""",
)
replace_once(
    "apps/mobile/lib/screens/bar_screen_v3.dart",
    """                      const SizedBox(height: 10),
                      if (data.products.isEmpty)""",
    """                      const SizedBox(height: 10),
                      if (_canManage) ...[
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
                      if (data.products.isEmpty)""",
)

# A galeria identifica também os originais vindos do OCR e deixa claro que são evidência protegida.
replace_once(
    "apps/mobile/lib/widgets/financial_document_gallery.dart",
    "Os documentos herdados de pedidos/reembolsos ficam protegidos contra eliminação nesta galeria.",
    "Os documentos herdados de pedidos/reembolsos e os originais de OCR ficam protegidos contra eliminação nesta galeria.",
)
replace_once(
    "apps/mobile/lib/widgets/financial_document_gallery.dart",
    """            if (document['origin'] == 'request')
              const Positioned(
                left: 4,
                top: 4,
                child: Tooltip(
                  message: 'Herdado do pedido financeiro',
                  child: Icon(Icons.link, size: 20),
                ),
              ),""",
    """            if (document['origin'] == 'request' || document['origin'] == 'bar_ocr')
              Positioned(
                left: 4,
                top: 4,
                child: Tooltip(
                  message: document['origin'] == 'bar_ocr'
                      ? 'Documento original da leitura OCR'
                      : 'Herdado do pedido financeiro',
                  child: Icon(
                    document['origin'] == 'bar_ocr'
                        ? Icons.document_scanner_outlined
                        : Icons.link,
                    size: 20,
                  ),
                ),
              ),""",
)

print("Commit 11 — OCR Financeiro/Bar aplicado localmente com sucesso.")
print()
print("Criado/alterado:")
for path in FILES:
    print(f" - {path}")
print(" - apps/mobile/lib/repositories/financial_documents_repository.dart")
print(" - apps/mobile/lib/screens/financial_transaction_documents_screen.dart")
print(" - apps/mobile/lib/screens/bar_screen_v3.dart")
print(" - apps/mobile/lib/widgets/financial_document_gallery.dart")
print()
print("As migrations e a Edge Function já foram aplicadas/deployadas no Supabase remoto.")
print("Não voltes a aplicar as migrations remotas.")
print()
print("Agora executa:")
print(r"  cd C:\project\BOB_Manager_v1_0_DEV\apps\mobile")
print("  flutter analyze")
print("  flutter test")
