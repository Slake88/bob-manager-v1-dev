import 'package:flutter/material.dart';

import '../core/fees_economics.dart';
import '../repositories/fees_operational_repository.dart';

class FeesReceivePaymentScreen extends StatefulWidget {
  const FeesReceivePaymentScreen({super.key});

  @override
  State<FeesReceivePaymentScreen> createState() => _FeesReceivePaymentScreenState();
}

class _FeesReceivePaymentScreenState extends State<FeesReceivePaymentScreen> {
  final FeesOperationalRepository _repository = FeesOperationalRepository();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _method = TextEditingController(text: 'Transferência');
  final TextEditingController _notes = TextEditingController();
  final Map<String, TextEditingController> _allocationControllers = {};
  late Future<List<Map<String, dynamic>>> _membersFuture;
  String? _memberId;
  DateTime _date = DateTime.now();
  FeeAllocationPreview? _preview;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _membersFuture = _repository.listMembers();
  }

  @override
  void dispose() {
    _amount.dispose();
    _method.dispose();
    _notes.dispose();
    for (final controller in _allocationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double get _paymentAmount => feeNumber(_amount.text);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _previewPayment() async {
    final member = _memberId;
    if (member == null || _paymentAmount <= 0) {
      _message('Seleciona o membro e indica um valor superior a zero.');
      return;
    }
    setState(() => _busy = true);
    try {
      final preview = await _repository.previewPayment(
        memberId: member,
        amount: _paymentAmount,
      );
      for (final controller in _allocationControllers.values) {
        controller.dispose();
      }
      _allocationControllers.clear();
      for (final allocation in preview.allocations) {
        final id = allocation['obligation_id']?.toString();
        if (id != null) {
          _allocationControllers[id] = TextEditingController(
            text: feeNumber(allocation['amount']).toStringAsFixed(2),
          );
        }
      }
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _customAllocations() {
    final preview = _preview;
    if (preview == null) return const [];
    final rows = <Map<String, dynamic>>[];
    var total = 0.0;
    for (final allocation in preview.allocations) {
      final id = allocation['obligation_id']?.toString();
      if (id == null) continue;
      final value = feeNumber(_allocationControllers[id]?.text);
      final outstanding = feeNumber(allocation['outstanding_before']);
      if (value < 0 || value > outstanding + 0.0001) {
        throw StateError('Uma distribuição excede o saldo da mensalidade.');
      }
      if (value > 0) {
        rows.add({'obligation_id': id, 'amount': value});
        total += value;
      }
    }
    if (total > _paymentAmount + 0.0001) {
      throw StateError('A distribuição excede o valor recebido.');
    }
    return rows;
  }

  Future<void> _confirm() async {
    final member = _memberId;
    if (member == null || _preview == null) return;
    if (_repository.isDemo) {
      _message('O modo Demo é apenas de leitura.');
      return;
    }
    if (_method.text.trim().isEmpty) {
      _message('Indica o método de pagamento.');
      return;
    }
    setState(() => _busy = true);
    try {
      final allocations = _customAllocations();
      await _repository.registerPayment(
        memberId: member,
        amount: _paymentAmount,
        paymentMethod: _method.text,
        paymentDate: _date,
        notes: _notes.text,
        allocations: allocations,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pagamento registado com sucesso.')),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receber pagamento de quotas')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final members = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('Pré-visualização Demo'),
                    subtitle: Text('Podes testar a distribuição, mas não confirmar.'),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: _memberId,
                decoration: const InputDecoration(labelText: 'Membro'),
                items: members.map((member) {
                  return DropdownMenuItem<String>(
                    value: member['id']?.toString(),
                    child: Text(member['full_name']?.toString() ?? 'Membro'),
                  );
                }).toList(),
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                          _memberId = value;
                          _preview = null;
                        }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor recebido (€)'),
                onChanged: (_) => setState(() => _preview = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _method,
                decoration: const InputDecoration(labelText: 'Método de pagamento'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Data: ${_date.day.toString().padLeft(2, '0')}/'
                    '${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notas (opcional)'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _previewPayment,
                icon: const Icon(Icons.calculate_outlined),
                label: const Text('Pré-visualizar distribuição'),
              ),
              if (_preview case final preview?) ...[
                const SizedBox(height: 20),
                Text('Distribuição', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (preview.allocations.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('Sem quotas em dívida'),
                      subtitle: Text('O valor recebido ficará integralmente em crédito.'),
                    ),
                  ),
                ...preview.allocations.map((allocation) {
                  final id = allocation['obligation_id']?.toString() ?? '';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_period(allocation),
                                    style: Theme.of(context).textTheme.titleMedium),
                                Text('Saldo antes: ${_money(feeNumber(allocation['outstanding_before']))}'),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _allocationControllers[id],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Aplicar €'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: const Text('Excesso previsto como crédito'),
                    trailing: Text(_money(preview.excessCredit)),
                    subtitle: preview.existingCredit > 0
                        ? Text('Crédito já existente: ${_money(preview.existingCredit)}')
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy || _repository.isDemo ? null : _confirm,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirmar recebimento'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }
}

String _period(Map<String, dynamic> row) {
  if (row['obligation_type'] == 'registration') return 'Inscrição';
  final month = int.tryParse(row['reference_month']?.toString() ?? '');
  final year = row['reference_year']?.toString() ?? '';
  const names = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
  if (month == null || month < 1 || month > 12) return year;
  return '${names[month - 1]} $year';
}

String _money(double value) => '${value.toStringAsFixed(2)} €';
String _friendly(Object error) => error.toString().replaceFirst('StateError: ', '').replaceFirst('Invalid argument(s): ', '');
