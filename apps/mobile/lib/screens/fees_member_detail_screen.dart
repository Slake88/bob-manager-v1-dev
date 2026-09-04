import 'package:flutter/material.dart';

import '../core/fees_economics.dart';
import '../repositories/fees_operational_repository.dart';

class FeesMemberDetailScreen extends StatefulWidget {
  const FeesMemberDetailScreen({super.key});

  @override
  State<FeesMemberDetailScreen> createState() => _FeesMemberDetailScreenState();
}

class _FeesMemberDetailScreenState extends State<FeesMemberDetailScreen> {
  final FeesOperationalRepository _repository = FeesOperationalRepository();
  late Future<List<Map<String, dynamic>>> _membersFuture;
  String? _memberId;
  Future<_MemberFeesData>? _dataFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = _repository.listMembers();
  }

  Future<_MemberFeesData> _load(String memberId) async {
    final results = await Future.wait<dynamic>([
      _repository.listObligations(memberId: memberId),
      _repository.listPayments(memberId: memberId),
      _repository.listCredits(memberId),
      _repository.listExemptions(memberId),
      _repository.listAdjustments(memberId),
      _repository.creditBalance(memberId),
    ]);
    return _MemberFeesData(
      obligations: results[0] as List<Map<String, dynamic>>,
      payments: results[1] as List<Map<String, dynamic>>,
      credits: results[2] as List<Map<String, dynamic>>,
      exemptions: results[3] as List<Map<String, dynamic>>,
      adjustments: results[4] as List<Map<String, dynamic>>,
      creditBalance: results[5] as double,
    );
  }

  void _selectMember(String? value) {
    setState(() {
      _memberId = value;
      _dataFuture = value == null ? null : _load(value);
    });
  }

  Future<void> _reload() async {
    final member = _memberId;
    if (member == null) return;
    setState(() => _dataFuture = _load(member));
    await _dataFuture;
  }

  Future<void> _obligationAction(
    Map<String, dynamic> obligation,
    String action,
  ) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (action) {
          'credit' => 'Aplicar crédito',
          'exemption' => 'Registar isenção',
          _ => 'Registar ajuste',
        }),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: InputDecoration(
                  labelText: action == 'adjustment'
                      ? 'Valor (€; pode ser negativo)'
                      : 'Valor (€)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Motivo'),
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      amount.dispose();
      reason.dispose();
      return;
    }
    try {
      final value = feeNumber(amount.text);
      final text = reason.text.trim();
      if (value == 0 || text.length < 3) {
        throw StateError('Indica um valor válido e um motivo.');
      }
      if (action == 'credit') {
        await _repository.applyCredit(
          memberId: _memberId!,
          obligationId: obligation['id'].toString(),
          amount: value,
          reason: text,
        );
      } else if (action == 'exemption') {
        if (value < 0) throw StateError('A isenção deve ser positiva.');
        await _repository.applyExemption(
          obligationId: obligation['id'].toString(),
          amount: value,
          reason: text,
        );
      } else {
        await _repository.applyAdjustment(
          obligationId: obligation['id'].toString(),
          amount: value,
          reason: text,
        );
      }
      await _reload();
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      amount.dispose();
      reason.dispose();
    }
  }

  Future<void> _creditAdjustment() async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajustar crédito'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Valor (€; + ou -)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    try {
      if (accepted == true) {
        await _repository.addCreditAdjustment(
          memberId: _memberId!,
          amount: feeNumber(amount.text),
          reason: reason.text,
        );
        await _reload();
      }
    } catch (error) {
      if (mounted) _message(_friendly(error));
    } finally {
      amount.dispose();
      reason.dispose();
    }
  }

  Future<void> _reversePayment(Map<String, dynamic> payment) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reverter pagamento?'),
        content: TextField(
          controller: reason,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Motivo da reversão'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reverter'),
          ),
        ],
      ),
    );
    if (accepted != true) {
      reason.dispose();
      return;
    }

    try {
      await _repository.reversePayment(
        paymentId: payment['id'].toString(),
        reason: reason.text,
      );
    } catch (error) {
      if (mounted) _message(_friendly(error));
      reason.dispose();
      return;
    }

    if (!mounted) {
      reason.dispose();
      return;
    }

    try {
      final member = _memberId;
      if (member != null) {
        final refreshed = _load(member);
        await refreshed;
        if (mounted) setState(() => _dataFuture = refreshed);
      }
      if (mounted) _message('Pagamento revertido com sucesso.');
    } catch (_) {
      if (mounted) {
        _message(
          'Pagamento revertido com sucesso, mas não foi possível atualizar o ecrã. Volta a abrir o membro.',
        );
      }
    } finally {
      reason.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quotas por membro')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final members = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _memberId,
                decoration: const InputDecoration(labelText: 'Membro'),
                items: members
                    .map(
                      (member) => DropdownMenuItem<String>(
                        value: member['id']?.toString(),
                        child: Text(
                          member['full_name']?.toString() ?? 'Membro',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _selectMember,
              ),
              if (_dataFuture != null) ...[
                const SizedBox(height: 16),
                FutureBuilder<_MemberFeesData>(
                  future: _dataFuture,
                  builder: (context, dataSnapshot) {
                    if (dataSnapshot.hasError) {
                      return Text('Erro: ${dataSnapshot.error}');
                    }
                    if (!dataSnapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    return _buildData(context, dataSnapshot.data!);
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildData(BuildContext context, _MemberFeesData data) {
    final debt = data.obligations.fold<double>(
      0,
      (sum, row) => sum + feeObligationOutstanding(row),
    );
    final overdue = data.obligations
        .where(feeObligationOverdue)
        .fold<double>(
          0,
          (sum, row) => sum + feeObligationOutstanding(row),
        );
    final paid = data.payments
        .where((row) => row['status'] != 'reversed')
        .fold<double>(0, (sum, row) => sum + feeNumber(row['amount']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Metric('Em dívida', debt),
            _Metric('Vencido', overdue),
            _Metric('Pago', paid),
            _Metric('Crédito', data.creditBalance),
          ],
        ),
        if (_repository.canManage && !_repository.isDemo) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _creditAdjustment,
              icon: const Icon(Icons.savings_outlined),
              label: const Text('Ajustar crédito'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Quotas', style: Theme.of(context).textTheme.titleLarge),
        ...data.obligations.map(
          (row) => Card(
            child: ListTile(
              title: Text(row['period_label']?.toString() ?? 'Quota'),
              subtitle: Text(
                'Devido ${_money(feeObligationTotal(row))} · Pago ${_money(feeNumber(row['paid_amount']))}\n'
                'Isento ${_money(feeNumber(row['exempt_amount']))} · Ajuste ${_money(feeNumber(row['adjustment_amount']))}',
              ),
              trailing:
                  _repository.canManage &&
                      feeObligationOutstanding(row) > 0 &&
                      !_repository.isDemo
                  ? PopupMenuButton<String>(
                      onSelected: (action) => _obligationAction(row, action),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'credit',
                          child: Text('Aplicar crédito'),
                        ),
                        PopupMenuItem(
                          value: 'exemption',
                          child: Text('Isenção'),
                        ),
                        PopupMenuItem(
                          value: 'adjustment',
                          child: Text('Ajuste'),
                        ),
                      ],
                    )
                  : Text(_money(feeObligationOutstanding(row))),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Pagamentos', style: Theme.of(context).textTheme.titleLarge),
        if (data.payments.isEmpty)
          const ListTile(title: Text('Sem pagamentos registados.')),
        ...data.payments.map(
          (row) => Card(
            child: ListTile(
              title: Text(_money(feeNumber(row['amount']))),
              subtitle: Text(
                '${row['payment_date'] ?? ''} · ${row['payment_method'] ?? ''} · ${row['status'] ?? ''}',
              ),
              trailing:
                  _repository.canManage &&
                      row['status'] != 'reversed' &&
                      !_repository.isDemo
                  ? IconButton(
                      tooltip: 'Reverter pagamento',
                      icon: const Icon(Icons.undo_outlined),
                      onPressed: () => _reversePayment(row),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: Text(
            'Histórico económico (${data.credits.length + data.exemptions.length + data.adjustments.length})',
          ),
          children: [
            ...data.credits.map(
              (row) => ListTile(
                leading: const Icon(Icons.savings_outlined),
                title: Text(
                  '${_money(feeNumber(row['amount']))} · ${row['entry_type'] ?? ''}',
                ),
                subtitle: Text(row['reason']?.toString() ?? ''),
              ),
            ),
            ...data.exemptions.map(
              (row) => ListTile(
                leading: const Icon(Icons.remove_circle_outline),
                title: Text(
                  'Isenção ${_money(feeNumber(row['amount']))} · ${row['status'] ?? ''}',
                ),
                subtitle: Text(row['reason']?.toString() ?? ''),
              ),
            ),
            ...data.adjustments.map(
              (row) => ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: Text(
                  'Ajuste ${_money(feeNumber(row['amount']))} · ${row['status'] ?? ''}',
                ),
                subtitle: Text(row['reason']?.toString() ?? ''),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
}

class _MemberFeesData {
  const _MemberFeesData({
    required this.obligations,
    required this.payments,
    required this.credits,
    required this.exemptions,
    required this.adjustments,
    required this.creditBalance,
  });

  final List<Map<String, dynamic>> obligations;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> credits;
  final List<Map<String, dynamic>> exemptions;
  final List<Map<String, dynamic>> adjustments;
  final double creditBalance;
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(_money(value), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

String _money(double value) => '${value.toStringAsFixed(2)} €';
String _friendly(Object error) => error
    .toString()
    .replaceFirst('StateError: ', '')
    .replaceFirst('Invalid argument(s): ', '');
