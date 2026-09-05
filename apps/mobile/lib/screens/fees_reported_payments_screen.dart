import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/fees_economics.dart';
import '../repositories/fees_operational_repository.dart';

class FeesReportedPaymentsScreen extends StatefulWidget {
  const FeesReportedPaymentsScreen({super.key});

  @override
  State<FeesReportedPaymentsScreen> createState() => _FeesReportedPaymentsScreenState();
}

class _FeesReportedPaymentsScreenState extends State<FeesReportedPaymentsScreen> {
  final FeesOperationalRepository _repository = FeesOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.listReportedPayments();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _repository.listReportedPayments();
    });
    await _future;
  }

  Future<void> _submit() async {
    if (_repository.isDemo) {
      _message('O modo Demo é apenas de leitura.');
      return;
    }
    final amount = TextEditingController();
    final method = TextEditingController(text: 'Transferência');
    final notes = TextEditingController();
    var paidOn = DateTime.now();
    PlatformFile? proof;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Comunicar pagamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor (€)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: method,
                  decoration: const InputDecoration(labelText: 'Método de pagamento'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await showDatePicker(
                      context: dialogContext,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 31)),
                      initialDate: paidOn,
                    );
                    if (selected != null) setDialogState(() => paidOn = selected);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Data: ${_date(paidOn)}'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Notas (opcional)'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
                      withData: true,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      setDialogState(() => proof = result.files.single);
                    }
                  },
                  icon: const Icon(Icons.attach_file),
                  label: Text(proof?.name ?? 'Anexar comprovativo'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar para validação'),
            ),
          ],
        ),
      ),
    );

    try {
      if (accepted == true) {
        final file = proof;
        if (feeNumber(amount.text) <= 0 || method.text.trim().isEmpty || file == null) {
          throw StateError('Indica valor, método e comprovativo.');
        }
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('Não foi possível ler o comprovativo.');
        }
        await _repository.submitReportedPayment(
          amount: feeNumber(amount.text),
          paidOn: paidOn,
          paymentMethod: method.text,
          fileName: file.name,
          bytes: bytes,
          mimeType: _mime(file.extension),
          notes: notes.text,
        );
        if (mounted) {
          _message('Pagamento comunicado. Aguarda validação.');
          await _reload();
        }
      }
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      amount.dispose();
      method.dispose();
      notes.dispose();
    }
  }

  Future<void> _openProof(Map<String, dynamic> row) async {
    try {
      final path = row['proof_path']?.toString();
      if (path == null || path.isEmpty) throw StateError('Sem comprovativo.');
      final url = await _repository.proofSignedUrl(path);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) _message('Não foi possível abrir o comprovativo.');
    } catch (error) {
      if (mounted) _message(_friendly(error));
    }
  }

  Future<void> _review(Map<String, dynamic> row, bool approve) async {
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Aprovar pagamento?' : 'Rejeitar pagamento?'),
        content: TextField(
          controller: notes,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: approve ? 'Nota (opcional)' : 'Motivo da rejeição',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Aprovar' : 'Rejeitar'),
          ),
        ],
      ),
    );
    try {
      if (accepted == true) {
        if (!approve && notes.text.trim().length < 3) {
          throw StateError('Indica o motivo da rejeição.');
        }
        await _repository.reviewReportedPayment(
          reportId: row['id'].toString(),
          approve: approve,
          notes: notes.text,
        );
        await _reload();
      }
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      notes.dispose();
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    try {
      await _repository.cancelReportedPayment(row['id'].toString());
      await _reload();
    } catch (error) {
      if (mounted) _message(_friendly(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamentos comunicados'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _repository.isDemo
          ? null
          : FloatingActionButton.extended(
              onPressed: _submit,
              icon: const Icon(Icons.add),
              label: const Text('Comunicar'),
            ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('Sem pagamentos comunicados'),
                    subtitle: Text('Usa “Comunicar” para enviar um comprovativo.'),
                  ),
                ),
              ],
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              final status = row['status']?.toString() ?? 'pending';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(_statusIcon(status)),
                        title: Text('${row['member_name'] ?? 'Membro'} · ${_money(feeNumber(row['amount']))}'),
                        subtitle: Text('${row['paid_on'] ?? ''} · ${row['payment_method'] ?? ''}\nEstado: ${_statusLabel(status)}'),
                        isThreeLine: true,
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _repository.isDemo ? null : () => _openProof(row),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Comprovativo'),
                          ),
                          if (_repository.canManage && status == 'pending') ...[
                            FilledButton.icon(
                              onPressed: () => _review(row, true),
                              icon: const Icon(Icons.check),
                              label: const Text('Aprovar'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _review(row, false),
                              icon: const Icon(Icons.close),
                              label: const Text('Rejeitar'),
                            ),
                          ] else if (!_repository.canManage && status == 'pending')
                            TextButton(
                              onPressed: () => _cancel(row),
                              child: const Text('Cancelar comunicação'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}

IconData _statusIcon(String status) => switch (status) {
  'approved' => Icons.check_circle_outline,
  'rejected' => Icons.cancel_outlined,
  'cancelled' => Icons.block_outlined,
  'reversed' => Icons.undo_outlined,
  _ => Icons.schedule_outlined,
};

String _statusLabel(String status) => switch (status) {
  'approved' => 'Aprovado',
  'rejected' => 'Rejeitado',
  'cancelled' => 'Cancelado',
  'reversed' => 'Revertido',
  _ => 'Pendente',
};

String? _mime(String? extension) => switch (extension?.toLowerCase()) {
  'pdf' => 'application/pdf',
  'png' => 'image/png',
  'webp' => 'image/webp',
  'jpg' || 'jpeg' => 'image/jpeg',
  _ => null,
};

String _money(double value) => '${value.toStringAsFixed(2)} €';
String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _friendly(Object error) => error.toString().replaceFirst('StateError: ', '').replaceFirst('Invalid argument(s): ', '');
