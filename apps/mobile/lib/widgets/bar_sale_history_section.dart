import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../repositories/bar_sales_repository.dart';

class BarSaleHistorySection extends StatefulWidget {
  const BarSaleHistorySection(
      {super.key,
      required this.sales,
      required this.repository,
      required this.onChanged});
  final List<Map<String, dynamic>> sales;
  final BarSalesRepository repository;
  final Future<void> Function() onChanged;
  @override
  State<BarSaleHistorySection> createState() => _BarSaleHistorySectionState();
}

class _BarSaleHistorySectionState extends State<BarSaleHistorySection> {
  bool _busy = false;
  Future<void> _reverse(Map<String, dynamic> sale) async {
    final reason = await showDialog<String>(
        context: context, builder: (_) => const _ReversalDialog());
    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.repository.reverseSale(sale['id'].toString(), reason);
      await widget.onChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Venda anulada. Tesouraria revertida e stock devolvido quando aplicável.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    return date == null
        ? 'Data indisponível'
        : DateFormat('dd/MM/yyyy HH:mm', 'pt_PT').format(date.toLocal());
  }

  String _actor(dynamic name, dynamic id) =>
      name?.toString().trim().isNotEmpty == true
          ? name.toString()
          : id?.toString() ?? 'Utilizador não registado';
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vendas', style: Theme.of(context).textTheme.titleLarge),
        if (widget.sales.isEmpty)
          const ListTile(title: Text('Ainda não existem vendas concluídas.')),
        for (final sale in widget.sales)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${_date(sale['completed_at'])} · ${NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(sale['total_amount'] ?? 0)}'),
                        Text(
                            sale['status'] == 'reversed'
                                ? 'Anulada'
                                : 'Concluída',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                            'Registada por: ${_actor(sale['completed_actor_name'], sale['completed_by'])}'),
                        for (final item
                            in (sale['bar_sale_items'] as List? ?? [])
                                .whereType<Map>())
                          Text(
                              '${item['description']} · ${item['quantity']} × ${NumberFormat.currency(locale: 'pt_PT', symbol: '€').format(item['unit_price'] ?? 0)}'),
                        if (sale['status'] == 'reversed') ...[
                          Text(
                              'Motivo: ${sale['reversal_reason'] ?? 'Não registado'}'),
                          Text(
                              'Anulada em ${_date(sale['reversed_at'])} por ${_actor(sale['reversed_actor_name'], sale['reversed_by'])}'),
                        ],
                        if (sale['status'] == 'completed' &&
                            widget.repository.canReverse)
                          TextButton.icon(
                              onPressed: _busy ? null : () => _reverse(sale),
                              icon: const Icon(Icons.undo),
                              label: const Text('Anular venda')),
                      ]))),
      ]);
}

class _ReversalDialog extends StatefulWidget {
  const _ReversalDialog();
  @override
  State<_ReversalDialog> createState() => _ReversalDialogState();
}

class _ReversalDialogState extends State<_ReversalDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Anular venda'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Esta operação preserva o histórico, reverte a Tesouraria e devolve o stock consumido, quando aplicável.'),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _reason,
                      decoration: const InputDecoration(
                          labelText: 'Motivo obrigatório'),
                      maxLines: 3,
                      validator: (value) => (value?.trim().length ?? 0) < 3
                          ? 'Indica o motivo (mínimo 3 caracteres).'
                          : null),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _reason.text.trim());
                }
              },
              child: const Text('Confirmar anulação'))
        ],
      );
}
