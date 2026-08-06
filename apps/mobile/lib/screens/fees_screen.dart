import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/fees_repository.dart';

class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key});

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  final FeesRepository _repository = FeesRepository();
  late Future<List<Map<String, dynamic>>> _future;

  bool get _canManage => PermissionPolicy.allows(
        AppRole.fromValue(AppSession.instance.role),
        AppPermission.manageFees,
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.listObligations();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _newObligation() async {
    final members = await _repository.listMembers();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FeeObligationDialog(
        members: members,
        repository: _repository,
      ),
    );
    if (changed == true) setState(_reload);
  }

  Future<void> _registerPayment(Map<String, dynamic> obligation) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FeePaymentDialog(
        obligation: obligation,
        repository: _repository,
      ),
    );
    if (changed == true) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = snapshot.data!;
          final outstanding = rows.fold<double>(
            0,
            (total, row) => total + _asDouble(row['balance']),
          );
          final paid = rows.fold<double>(
            0,
            (total, row) => total + _asDouble(row['paid_amount']),
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: 'Recebido',
                      value: '${paid.toStringAsFixed(2)} €',
                      icon: Icons.check_circle_outline,
                    ),
                    _MetricCard(
                      label: 'Pendente',
                      value: '${outstanding.toStringAsFixed(2)} €',
                      icon: Icons.schedule_outlined,
                    ),
                    _MetricCard(
                      label: 'Registos',
                      value: '${rows.length}',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...rows.map((row) {
                  final balance = _asDouble(row['balance']);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (row['member_name']?.toString() ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(row['member_name']?.toString() ?? 'Membro'),
                      subtitle: Text(
                        '${row['period_label'] ?? ''} • ${row['status'] ?? ''}\n'
                        'Devido: ${_asDouble(row['amount']).toStringAsFixed(2)} € • '
                        'Pago: ${_asDouble(row['paid_amount']).toStringAsFixed(2)} €',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        '${balance.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      onTap: _canManage ? () => _registerPayment(row) : null,
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _newObligation,
              icon: const Icon(Icons.add),
              label: const Text('Nova quota'),
            )
          : null,
    );
  }
}

class _FeeObligationDialog extends StatefulWidget {
  const _FeeObligationDialog({
    required this.members,
    required this.repository,
  });

  final List<Map<String, dynamic>> members;
  final FeesRepository repository;

  @override
  State<_FeeObligationDialog> createState() => _FeeObligationDialogState();
}

class _FeeObligationDialogState extends State<_FeeObligationDialog> {
  String? _memberId;
  final TextEditingController _period = TextEditingController();
  final TextEditingController _amount = TextEditingController(text: '25');
  final TextEditingController _dueDate = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _period.dispose();
    _amount.dispose();
    _dueDate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final member = widget.members.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == _memberId,
          orElse: () => null,
        );
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (member == null || _period.text.trim().isEmpty || amount == null) return;

    setState(() => _saving = true);
    try {
      await widget.repository.saveObligation({
        'member_id': member['id'],
        'member_name': member['full_name'],
        'period_label': _period.text.trim(),
        'due_date': _dueDate.text.trim().isEmpty ? null : _dueDate.text.trim(),
        'amount': amount,
        'paid_amount': 0.0,
        'credit_amount': 0.0,
        'status': 'pending',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova quota'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              decoration: const InputDecoration(labelText: 'Membro'),
              items: widget.members
                  .map(
                    (member) => DropdownMenuItem(
                      value: member['id'].toString(),
                      child: Text(member['full_name']?.toString() ?? ''),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _memberId = value),
            ),
            TextField(
              controller: _period,
              decoration: const InputDecoration(labelText: 'Período'),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            TextField(
              controller: _dueDate,
              decoration: const InputDecoration(
                labelText: 'Vencimento',
                hintText: 'AAAA-MM-DD',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _FeePaymentDialog extends StatefulWidget {
  const _FeePaymentDialog({
    required this.obligation,
    required this.repository,
  });

  final Map<String, dynamic> obligation;
  final FeesRepository repository;

  @override
  State<_FeePaymentDialog> createState() => _FeePaymentDialogState();
}

class _FeePaymentDialogState extends State<_FeePaymentDialog> {
  final TextEditingController _amount = TextEditingController();
  String _method = 'Transferência bancária';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (amount == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.registerPayment(
        obligation: widget.obligation,
        amount: amount,
        paymentMethod: _method,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Pagamento — ${widget.obligation['member_name'] ?? ''}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor recebido'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Método'),
            items: const [
              'Transferência bancária',
              'MB Way',
              'Dinheiro',
            ]
                .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                .toList(),
            onChanged: (value) => setState(() => _method = value ?? _method),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Registar'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(value),
          subtitle: Text(label),
        ),
      ),
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
