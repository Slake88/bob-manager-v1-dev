import 'package:flutter/material.dart';

import '../repositories/financial_documents_repository.dart';
import '../widgets/financial_document_gallery.dart';

class FinancialTransactionDocumentsScreen extends StatelessWidget {
  const FinancialTransactionDocumentsScreen({
    super.key,
    required this.transaction,
    this.onChanged,
  });

  final Map<String, dynamic> transaction;
  final Future<void> Function()? onChanged;

  @override
  Widget build(BuildContext context) {
    final repository = FinancialDocumentsRepository();
    final transactionId = transaction['id']?.toString() ?? '';
    final kind = transaction['kind']?.toString();
    final isIncome = kind == 'income';
    final isTransfer = kind == 'transfer';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documentos do movimento'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Icon(
                          isTransfer
                              ? Icons.swap_horiz
                              : isIncome
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              transaction['description']?.toString() ??
                                  'Movimento',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                transaction['transaction_date']?.toString(),
                                transaction['account_name']?.toString(),
                                transaction['cost_center_name']?.toString(),
                              ]
                                  .where((value) =>
                                      value != null && value.trim().isNotEmpty)
                                  .join(' • '),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${isIncome ? '+' : isTransfer ? '' : '-'}${_money(transaction['amount'])}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  if ((transaction['payment_method']?.toString() ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Pagamento: ${_paymentMethod(transaction['payment_method']?.toString())}',
                    ),
                  ],
                  if ((transaction['notes']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(transaction['notes'].toString()),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (transactionId.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.error_outline),
                title: Text('Movimento sem identificador.'),
              ),
            )
          else
            FinancialDocumentGallery(
              repository: repository,
              transactionId: transactionId,
              canManage: repository.canManage,
              onChanged: onChanged,
            ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Arquivo financeiro auditado'),
              subtitle: const Text(
                'Cada ficheiro fica associado individualmente ao movimento. '
                'Talões e comprovativos herdados de pedidos financeiros são '
                'mantidos como evidência e não são duplicados no Storage.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String _paymentMethod(String? value) {
    if (value == null || value.isEmpty) return '—';
    return switch (value) {
      'cash' => 'Numerário',
      'mbway' => 'MB Way',
      'bank_transfer' => 'Transferência bancária',
      'other' => 'Outro',
      _ => value,
    };
  }
}
