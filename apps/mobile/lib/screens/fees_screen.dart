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
  late Future<_FeesViewData> _future;
  int _year = DateTime.now().year;

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
    _future = _load();
  }

  Future<_FeesViewData> _load() async {
    await _repository.ensureYear(_year);
    final results = await Future.wait([
      _repository.listObligations(year: _year),
      _repository.listMembers(),
      _repository.settings(),
    ]);
    return _FeesViewData(
      obligations: List<Map<String, dynamic>>.from(results[0] as List),
      members: List<Map<String, dynamic>>.from(results[1] as List),
      settings: Map<String, dynamic>.from(results[2] as Map),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  void _changeYear(int delta) {
    setState(() {
      _year += delta;
      _reload();
    });
  }

  Future<void> _newObligation(_FeesViewData data) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FeeObligationDialog(
        members: data.members,
        repository: _repository,
        initialYear: _year,
        defaultAmount: _asDouble(data.settings['monthly_amount']),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _registerPayment(Map<String, dynamic> obligation) async {
    if (_asDouble(obligation['balance']) <= 0) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FeePaymentDialog(
        obligation: obligation,
        repository: _repository,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _deleteObligation(Map<String, dynamic> obligation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar quota?'),
        content: Text(
          'Apagar definitivamente ${obligation['period_label']} de '
          '${obligation['member_name']}? Esta operação só é permitida ao Super Admin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteObligation(obligation);
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    }
  }

  Future<void> _openSettings(_FeesViewData data) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _FeeSettingsDialog(
        repository: _repository,
        settings: data.settings,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_FeesViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${_friendlyError(snapshot.error!)}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final monthly = data.obligations
              .where((row) => row['obligation_type']?.toString() != 'registration')
              .toList();
          final registrations = data.obligations
              .where((row) => row['obligation_type']?.toString() == 'registration')
              .toList();
          final paidCount = monthly.where((row) => _asDouble(row['balance']) == 0).length;
          final pendingCount = monthly.where((row) => _asDouble(row['balance']) > 0).length;
          final received = data.obligations.fold<double>(
            0,
            (total, row) => total + _asDouble(row['paid_amount']),
          );
          final outstanding = data.obligations.fold<double>(
            0,
            (total, row) => total + _asDouble(row['balance']),
          );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Ano anterior',
                      onPressed: () => _changeYear(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      'Quotas $_year',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    IconButton(
                      tooltip: 'Ano seguinte',
                      onPressed: () => _changeYear(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const Spacer(),
                    if (_repository.canConfigureFees)
                      OutlinedButton.icon(
                        onPressed: () => _openSettings(data),
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Configurar'),
                      ),
                    if (_canManage) ...[
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _newObligation(data),
                        icon: const Icon(Icons.add),
                        label: const Text('Quota manual'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      label: 'Mensalidades pagas',
                      value: '$paidCount',
                      icon: Icons.check_circle_outline,
                    ),
                    _MetricCard(
                      label: 'Mensalidades em falta',
                      value: '$pendingCount',
                      icon: Icons.cancel_outlined,
                    ),
                    _MetricCard(
                      label: 'Recebido',
                      value: '${received.toStringAsFixed(2)} €',
                      icon: Icons.payments_outlined,
                    ),
                    _MetricCard(
                      label: 'Por receber',
                      value: '${outstanding.toStringAsFixed(2)} €',
                      icon: Icons.schedule_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mapa anual',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text('✓ pago  •  ✕ por pagar  •  — sem obrigação'),
                        const SizedBox(height: 12),
                        _AnnualFeesGrid(
                          members: data.members,
                          obligations: monthly,
                          onTap: _canManage ? _registerPayment : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Inscrições', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (registrations.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Sem inscrições registadas neste ano.'),
                      subtitle: _repository.canConfigureFees &&
                              _asDouble(data.settings['registration_amount']) == 0
                          ? const Text(
                              'O valor de inscrição está a 0 €. Define-o em Configurar para gerar inscrições automaticamente.',
                            )
                          : null,
                    ),
                  )
                else
                  ...registrations.map((row) => _ObligationTile(
                        row: row,
                        canManage: _canManage,
                        canDelete: _repository.canDeleteObligations,
                        onPayment: () => _registerPayment(row),
                        onDelete: () => _deleteObligation(row),
                      )),
                const SizedBox(height: 16),
                Text(
                  'Detalhe das mensalidades',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...monthly.map((row) => _ObligationTile(
                      row: row,
                      canManage: _canManage,
                      canDelete: _repository.canDeleteObligations,
                      onPayment: () => _registerPayment(row),
                      onDelete: () => _deleteObligation(row),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FeesViewData {
  const _FeesViewData({
    required this.obligations,
    required this.members,
    required this.settings,
  });

  final List<Map<String, dynamic>> obligations;
  final List<Map<String, dynamic>> members;
  final Map<String, dynamic> settings;
}

class _AnnualFeesGrid extends StatelessWidget {
  const _AnnualFeesGrid({
    required this.members,
    required this.obligations,
    this.onTap,
  });

  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> obligations;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final row in obligations) {
      final memberId = row['member_id']?.toString();
      final month = int.tryParse(row['reference_month']?.toString() ?? '');
      if (memberId != null && month != null) {
        byKey['$memberId-$month'] = row;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(58),
        columnWidths: const {0: FixedColumnWidth(190)},
        border: TableBorder.all(color: Theme.of(context).dividerColor),
        children: [
          TableRow(
            children: [
              const _GridCell(text: 'Membro', bold: true),
              ..._monthShort.map((month) => _GridCell(text: month, bold: true)),
            ],
          ),
          ...members.map((member) {
            final memberId = member['id']?.toString() ?? '';
            return TableRow(
              children: [
                _GridCell(
                  text: member['full_name']?.toString() ?? 'Membro',
                  alignLeft: true,
                ),
                for (var month = 1; month <= 12; month++)
                  _StatusCell(
                    obligation: byKey['$memberId-$month'],
                    onTap: onTap,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.text,
    this.bold = false,
    this.alignLeft = false,
  });

  final String text;
  final bool bold;
  final bool alignLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  const _StatusCell({required this.obligation, this.onTap});

  final Map<String, dynamic>? obligation;
  final void Function(Map<String, dynamic>)? onTap;

  @override
  Widget build(BuildContext context) {
    if (obligation == null) {
      return const SizedBox(height: 46, child: Center(child: Text('—')));
    }
    final paid = _asDouble(obligation!['balance']) == 0;
    return InkWell(
      onTap: !paid && onTap != null ? () => onTap!(obligation!) : null,
      child: SizedBox(
        height: 46,
        child: Center(
          child: Icon(
            paid ? Icons.check_circle : Icons.cancel,
            color: paid ? Colors.green : Colors.red,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ObligationTile extends StatelessWidget {
  const _ObligationTile({
    required this.row,
    required this.canManage,
    required this.canDelete,
    required this.onPayment,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final bool canManage;
  final bool canDelete;
  final VoidCallback onPayment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final balance = _asDouble(row['balance']);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            (row['member_name']?.toString().isNotEmpty ?? false)
                ? row['member_name'].toString()[0].toUpperCase()
                : '?',
          ),
        ),
        title: Text(row['member_name']?.toString() ?? 'Membro'),
        subtitle: Text(
          '${row['period_label'] ?? ''} • ${row['status'] ?? ''}\n'
          'Devido: ${_asDouble(row['amount']).toStringAsFixed(2)} € • '
          'Pago: ${_asDouble(row['paid_amount']).toStringAsFixed(2)} €',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${balance.toStringAsFixed(2)} €',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (canDelete)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Apagar')),
                ],
              ),
          ],
        ),
        onTap: canManage && balance > 0 ? onPayment : null,
      ),
    );
  }
}

class _FeeObligationDialog extends StatefulWidget {
  const _FeeObligationDialog({
    required this.members,
    required this.repository,
    required this.initialYear,
    required this.defaultAmount,
  });

  final List<Map<String, dynamic>> members;
  final FeesRepository repository;
  final int initialYear;
  final double defaultAmount;

  @override
  State<_FeeObligationDialog> createState() => _FeeObligationDialogState();
}

class _FeeObligationDialogState extends State<_FeeObligationDialog> {
  String? _memberId;
  late int _month;
  late final TextEditingController _year;
  late final TextEditingController _amount;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _month = DateTime.now().month;
    _year = TextEditingController(text: widget.initialYear.toString());
    _amount = TextEditingController(text: widget.defaultAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _year.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final member = widget.members.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['id']?.toString() == _memberId,
          orElse: () => null,
        );
    final year = int.tryParse(_year.text.trim());
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (member == null || year == null || amount == null || amount <= 0) return;

    setState(() => _saving = true);
    try {
      await widget.repository.saveObligation({
        'member_id': member['id'],
        'member_name': member['full_name'],
        'period_label': '${_monthNames[_month - 1]} $year',
        'amount': amount,
        'paid_amount': 0.0,
        'credit_amount': 0.0,
        'status': 'pending',
        'obligation_type': 'monthly',
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quota manual'),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Mês'),
              items: [
                for (var i = 1; i <= 12; i++)
                  DropdownMenuItem(value: i, child: Text(_monthNames[i - 1])),
              ],
              onChanged: (value) => setState(() => _month = value ?? _month),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ano'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
            const SizedBox(height: 8),
            const Text(
              'O vencimento é calculado automaticamente com o dia definido nas configurações.',
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

class _FeeSettingsDialog extends StatefulWidget {
  const _FeeSettingsDialog({required this.repository, required this.settings});

  final FeesRepository repository;
  final Map<String, dynamic> settings;

  @override
  State<_FeeSettingsDialog> createState() => _FeeSettingsDialogState();
}

class _FeeSettingsDialogState extends State<_FeeSettingsDialog> {
  late final TextEditingController _dueDay;
  late final TextEditingController _monthly;
  late final TextEditingController _registration;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dueDay = TextEditingController(text: widget.settings['due_day']?.toString() ?? '8');
    _monthly = TextEditingController(
      text: _asDouble(widget.settings['monthly_amount']).toStringAsFixed(2),
    );
    _registration = TextEditingController(
      text: _asDouble(widget.settings['registration_amount']).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _dueDay.dispose();
    _monthly.dispose();
    _registration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final day = int.tryParse(_dueDay.text);
    final monthly = double.tryParse(_monthly.text.replaceAll(',', '.'));
    final registration = double.tryParse(_registration.text.replaceAll(',', '.'));
    if (day == null || monthly == null || registration == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateSettings(
        dueDay: day,
        monthlyAmount: monthly,
        registrationAmount: registration,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuração de quotas'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _dueDay,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Dia de vencimento mensal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monthly,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor da quota mensal'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _registration,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor da inscrição'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ao definir um valor de inscrição, as inscrições em falta são geradas automaticamente para Prospects e Full Colors.',
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
  void initState() {
    super.initState();
    _amount.text = _asDouble(widget.obligation['balance']).toStringAsFixed(2);
  }

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
        SnackBar(content: Text(_friendlyError(error))),
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
          Text(widget.obligation['period_label']?.toString() ?? ''),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor recebido'),
          ),
          const SizedBox(height: 12),
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
  const _MetricCard({required this.label, required this.value, required this.icon});

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

const List<String> _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

const List<String> _monthShort = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.startsWith('Bad state: ')) return text.substring(11);
  if (text.startsWith('Invalid argument(s): ')) return text.substring(21);
  return text;
}
