import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/lottery_repository.dart';

class LotteryScreen extends StatefulWidget {
  const LotteryScreen({super.key});

  @override
  State<LotteryScreen> createState() => _LotteryScreenState();
}

class _LotteryScreenState extends State<LotteryScreen> {
  final LotteryRepository _repository = LotteryRepository();
  late Future<List<Map<String, dynamic>>> _future;

  bool get _canManage => PermissionPolicy.allows(
        AppRole.fromValue(AppSession.instance.role),
        AppPermission.manageLottery,
      );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.listParticipants();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _newParticipant() async {
    final members = await _repository.listMembers();
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _LotteryParticipantDialog(
        members: members,
        repository: _repository,
      ),
    );
    if (changed == true) setState(_reload);
  }

  Future<void> _registerPayment(Map<String, dynamic> participant) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _LotteryPaymentDialog(
        participant: participant,
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
          final active = rows.where((row) => row['active'] != false).length;
          final pending = rows.fold<double>(
            0,
            (total, row) => total + _asDouble(row['balance']),
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
                      label: 'Participantes ativos',
                      value: '$active',
                      icon: Icons.groups_outlined,
                    ),
                    _MetricCard(
                      label: 'Saldo pendente',
                      value: '${pending.toStringAsFixed(2)} €',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ...rows.map((row) {
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.casino_outlined),
                      ),
                      title: Text(row['member_name']?.toString() ?? 'Membro'),
                      subtitle: Text(
                        '${row['billing_frequency'] ?? ''} • '
                        '${_asDouble(row['participant_amount']).toStringAsFixed(2)} €\n'
                        'Números: ${row['numbers'] ?? ''} • Estrelas: ${row['stars'] ?? ''}',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        '${_asDouble(row['balance']).toStringAsFixed(2)} €',
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
              onPressed: _newParticipant,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Novo participante'),
            )
          : null,
    );
  }
}

class _LotteryParticipantDialog extends StatefulWidget {
  const _LotteryParticipantDialog({
    required this.members,
    required this.repository,
  });

  final List<Map<String, dynamic>> members;
  final LotteryRepository repository;

  @override
  State<_LotteryParticipantDialog> createState() =>
      _LotteryParticipantDialogState();
}

class _LotteryParticipantDialogState
    extends State<_LotteryParticipantDialog> {
  String? _memberId;
  String _frequency = 'weekly';
  final TextEditingController _amount = TextEditingController(text: '5');
  final TextEditingController _numbers = TextEditingController();
  final TextEditingController _stars = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _numbers.dispose();
    _stars.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final member = widget.members.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == _memberId,
          orElse: () => null,
        );
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (member == null || amount == null) return;

    setState(() => _saving = true);
    try {
      await widget.repository.saveParticipant({
        'member_id': member['id'],
        'member_name': member['full_name'],
        'billing_frequency': _frequency,
        'participant_amount': amount,
        'numbers': _numbers.text.trim(),
        'stars': _stars.text.trim(),
        'paid_amount': 0.0,
        'balance': amount,
        'active': true,
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
      title: const Text('Novo participante'),
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
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Cobrança'),
              items: const [
                DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
                DropdownMenuItem(value: 'monthly', child: Text('Mensal')),
              ],
              onChanged: (value) =>
                  setState(() => _frequency = value ?? _frequency),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            TextField(
              controller: _numbers,
              decoration: const InputDecoration(
                labelText: '5 números',
                hintText: '4, 12, 23, 37, 48',
              ),
            ),
            TextField(
              controller: _stars,
              decoration: const InputDecoration(
                labelText: '2 estrelas',
                hintText: '3, 9',
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

class _LotteryPaymentDialog extends StatefulWidget {
  const _LotteryPaymentDialog({
    required this.participant,
    required this.repository,
  });

  final Map<String, dynamic> participant;
  final LotteryRepository repository;

  @override
  State<_LotteryPaymentDialog> createState() => _LotteryPaymentDialogState();
}

class _LotteryPaymentDialogState extends State<_LotteryPaymentDialog> {
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
        participant: widget.participant,
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
      title: Text('Pagamento — ${widget.participant['member_name'] ?? ''}'),
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
      width: 230,
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
