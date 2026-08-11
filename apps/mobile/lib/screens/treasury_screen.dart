import 'package:flutter/material.dart';

import '../repositories/treasury_repository.dart';
import 'financial_transaction_documents_screen.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  final TreasuryRepository _repository = TreasuryRepository();
  late Future<_TreasuryViewData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_TreasuryViewData> _load() async {
    final results = await Future.wait([
      _repository.summary(),
      _repository.listMovements(),
      _repository.listCostCenters(),
    ]);
    return _TreasuryViewData(
      summary: Map<String, dynamic>.from(results[0] as Map),
      movements: List<Map<String, dynamic>>.from(results[1] as List),
      costCenters: List<Map<String, dynamic>>.from(results[2] as List),
    );
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openMovementDocuments(Map<String, dynamic> movement) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinancialTransactionDocumentsScreen(
          transaction: movement,
          onChanged: _refresh,
        ),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _openMovement(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> costCenters,
    String kind,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _MovementDialog(
        repository: _repository,
        accounts: accounts,
        costCenters: costCenters,
        kind: kind,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _openTransfer(List<Map<String, dynamic>> accounts) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _TransferDialog(
        repository: _repository,
        accounts: accounts,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _openAccount([Map<String, dynamic>? account]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AccountDialog(
        repository: _repository,
        account: account,
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _deactivateAccount(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desativar conta'),
        content: Text(
          'Desativar a conta ${account['name']}? A conta deixa de aparecer nas operações, mas o histórico é mantido.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repository.deactivateAccount(account);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível desativar: $error')),
      );
    }
  }

  String _money(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return '${amount.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_TreasuryViewData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final accounts = List<Map<String, dynamic>>.from(
            data.summary['accounts'] as List<dynamic>? ?? const [],
          );
          final total = data.summary['total_balance'];

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo global',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _money(total),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => _openMovement(
                                accounts,
                                data.costCenters,
                                'income',
                              ),
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Receita'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: () => _openMovement(
                                accounts,
                                data.costCenters,
                                'expense',
                              ),
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Despesa'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openTransfer(accounts),
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text('Transferência'),
                            ),
                            if (_repository.canManageAccounts)
                              OutlinedButton.icon(
                                onPressed: _openAccount,
                                icon: const Icon(Icons.account_balance_wallet_outlined),
                                label: const Text('Nova conta'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Contas',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_repository.canManageAccounts)
                      TextButton.icon(
                        onPressed: _openAccount,
                        icon: const Icon(Icons.add),
                        label: const Text('Adicionar'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                ...accounts.map(
                  (account) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(account['icon']?.toString() ?? '€'),
                      ),
                      title: Text(account['name']?.toString() ?? 'Conta'),
                      subtitle: Text(
                        [
                          account['account_type']?.toString(),
                          account['allows_negative'] == true
                              ? 'Pode ficar com saldo negativo'
                              : 'Saldo negativo bloqueado',
                        ].where((value) => value != null).join(' • '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _money(account['balance']),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_repository.canManageAccounts)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _openAccount(account);
                                if (value == 'deactivate') {
                                  _deactivateAccount(account);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit_outlined),
                                    title: Text('Editar'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'deactivate',
                                  child: ListTile(
                                    leading: Icon(Icons.block_outlined),
                                    title: Text('Desativar'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Movimentos recentes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (data.movements.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Sem movimentos registados.'),
                    ),
                  )
                else
                  ...data.movements.take(30).map((movement) {
                    final kind = movement['kind']?.toString();
                    final isIncome = kind == 'income';
                    final isTransfer = kind == 'transfer';
                    final accountName = movement['account_name']?.toString();
                    final destination =
                        movement['destination_account_name']?.toString();
                    return Card(
                      child: ListTile(
                        onTap: () => _openMovementDocuments(movement),
                        leading: Icon(
                          isTransfer
                              ? Icons.swap_horiz
                              : isIncome
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                        ),
                        title: Text(
                          movement['description']?.toString() ?? 'Movimento',
                        ),
                        subtitle: Text(
                          [
                            movement['transaction_date'],
                            if (isTransfer)
                              '$accountName → $destination'
                            else
                              accountName,
                            movement['cost_center_name'],
                            if ((movement['document_path']?.toString() ?? '')
                                .isNotEmpty)
                              'Com documentos',
                          ]
                              .where((value) =>
                                  value != null && value.toString().isNotEmpty)
                              .join(' • '),
                        ),
                        trailing: Text(
                          '${isIncome ? '+' : isTransfer ? '' : '-'}${_money(movement['amount'])}',
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TreasuryViewData {
  const _TreasuryViewData({
    required this.summary,
    required this.movements,
    required this.costCenters,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> movements;
  final List<Map<String, dynamic>> costCenters;
}

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({
    required this.repository,
    this.account,
  });

  final TreasuryRepository repository;
  final Map<String, dynamic>? account;

  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _iban;
  late final TextEditingController _icon;
  late final TextEditingController _openingBalance;
  String _type = 'fund';
  bool _saving = false;

  bool get _editing => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    _name = TextEditingController(text: account?['name']?.toString() ?? '');
    _iban = TextEditingController(text: account?['iban']?.toString() ?? '');
    _icon = TextEditingController(text: account?['icon']?.toString() ?? '💰');
    _openingBalance = TextEditingController(
      text: account?['opening_balance']?.toString() ?? '0',
    );
    _type = account?['account_type']?.toString() ??
        account?['type']?.toString() ??
        'fund';
  }

  @override
  void dispose() {
    _name.dispose();
    _iban.dispose();
    _icon.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_editing) {
        await widget.repository.updateAccount(
          widget.account!['id'].toString(),
          name: _name.text,
          accountType: _type,
          iban: _iban.text,
          icon: _icon.text,
        );
      } else {
        await widget.repository.createAccount(
          name: _name.text,
          accountType: _type,
          iban: _iban.text,
          icon: _icon.text,
          openingBalance:
              double.tryParse(_openingBalance.text.replaceAll(',', '.')) ?? 0,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_editing ? 'Editar conta' : 'Nova conta'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nome da conta'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo obrigatório.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Tipo de conta'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Caixa / Dinheiro')),
                    DropdownMenuItem(value: 'bank', child: Text('Conta bancária')),
                    DropdownMenuItem(value: 'fund', child: Text('Conta interna')),
                    DropdownMenuItem(value: 'reserve', child: Text('Reserva')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? 'fund'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _icon,
                  decoration: const InputDecoration(
                    labelText: 'Ícone',
                    hintText: 'Ex.: 💰',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _iban,
                  decoration: const InputDecoration(
                    labelText: 'IBAN (opcional)',
                  ),
                ),
                if (!_editing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _openingBalance,
                    decoration: const InputDecoration(
                      labelText: 'Saldo inicial',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) =>
                        double.tryParse((value ?? '').replaceAll(',', '.')) == null
                            ? 'Introduz um valor válido.'
                            : null,
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Apenas uma conta com o nome Caixa pode ficar com saldo negativo.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.repository,
    required this.accounts,
    required this.costCenters,
    required this.kind,
  });

  final TreasuryRepository repository;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> costCenters;
  final String kind;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  String? _accountId;
  String? _costCenterId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) {
      _accountId = widget.accounts.first['id']?.toString();
    }
    if (widget.kind == 'expense' && widget.costCenters.isNotEmpty) {
      _costCenterId = widget.costCenters.first['id']?.toString();
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final account = widget.accounts.firstWhere(
      (row) => row['id']?.toString() == _accountId,
    );
    final costCenter = _costCenterId == null
        ? null
        : widget.costCenters.firstWhere(
            (row) => row['id']?.toString() == _costCenterId,
          );

    setState(() => _saving = true);
    try {
      await widget.repository.createMovement({
        'transaction_date': DateTime.now().toIso8601String().split('T').first,
        'kind': widget.kind,
        'description': _description.text.trim(),
        'amount': double.parse(_amount.text.replaceAll(',', '.')),
        'account_id': _accountId,
        'account_name': account['name'],
        if (costCenter != null) 'cost_center_id': costCenter['id'],
        if (costCenter != null) 'cost_center_name': costCenter['name'],
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.kind == 'income' ? 'Nova receita' : 'Nova despesa'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  decoration: InputDecoration(
                    labelText: widget.kind == 'income'
                        ? 'Conta que recebe o dinheiro'
                        : 'Conta de onde sai o dinheiro',
                  ),
                  items: widget.accounts
                      .map(
                        (account) => DropdownMenuItem<String>(
                          value: account['id'].toString(),
                          child: Text(account['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _accountId = value),
                  validator: (value) =>
                      value == null ? 'Seleciona uma conta.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(labelText: 'Valor'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final amount = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return amount == null || amount <= 0
                        ? 'Introduz um valor válido.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'Descrição'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Campo obrigatório.'
                      : null,
                ),
                if (widget.kind == 'expense') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _costCenterId,
                    decoration:
                        const InputDecoration(labelText: 'Centro de custo'),
                    items: widget.costCenters
                        .map(
                          (center) => DropdownMenuItem<String>(
                            value: center['id'].toString(),
                            child: Text(center['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _costCenterId = value),
                    validator: (value) => value == null
                        ? 'Seleciona o centro de custo.'
                        : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({
    required this.repository,
    required this.accounts,
  });

  final TreasuryRepository repository;
  final List<Map<String, dynamic>> accounts;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _sourceId;
  String? _destinationId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.accounts.isNotEmpty) {
      _sourceId = widget.accounts.first['id']?.toString();
    }
    if (widget.accounts.length > 1) {
      _destinationId = widget.accounts[1]['id']?.toString();
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.repository.transfer(
        sourceAccountId: _sourceId!,
        destinationAccountId: _destinationId!,
        amount: double.parse(_amount.text.replaceAll(',', '.')),
        description: _description.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível transferir: $error')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transferência entre contas'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _sourceId,
                decoration: const InputDecoration(
                  labelText: 'O dinheiro sai da conta',
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account['id'].toString(),
                        child: Text(account['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _sourceId = value),
                validator: (value) =>
                    value == null ? 'Seleciona a conta de origem.' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _destinationId,
                decoration: const InputDecoration(
                  labelText: 'O dinheiro entra na conta',
                ),
                items: widget.accounts
                    .map(
                      (account) => DropdownMenuItem<String>(
                        value: account['id'].toString(),
                        child: Text(account['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _destinationId = value),
                validator: (value) {
                  if (value == null) return 'Seleciona a conta de destino.';
                  if (value == _sourceId) {
                    return 'A origem e o destino têm de ser diferentes.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: const InputDecoration(labelText: 'Valor a transferir'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final amount =
                      double.tryParse((value ?? '').replaceAll(',', '.'));
                  return amount == null || amount <= 0
                      ? 'Introduz um valor válido.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Descrição (opcional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Transferir'),
        ),
      ],
    );
  }
}
