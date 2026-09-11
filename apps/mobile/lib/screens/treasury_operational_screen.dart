import 'package:flutter/material.dart';

import '../core/treasury_economics.dart';
import '../repositories/treasury_operational_repository.dart';

class TreasuryOperationalScreen extends StatefulWidget {
  const TreasuryOperationalScreen({super.key});

  @override
  State<TreasuryOperationalScreen> createState() =>
      _TreasuryOperationalScreenState();
}

class _TreasuryOperationalScreenState extends State<TreasuryOperationalScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.overview();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repository.overview());
    await _future;
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth - 32;
            final columns = constraints.maxWidth >= 900
                ? 3
                : constraints.maxWidth >= 620
                    ? 2
                    : 1;
            final gap = 12.0 * (columns - 1);
            final cardWidth = (available - gap) / columns;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    'Tesouraria operacional',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Planeamento, obrigações, reconciliação e controlo de caixa num fluxo preparado para telemóvel.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_repository.isDemo) ...[
                    const SizedBox(height: 12),
                    const _DemoBanner(),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.payments_outlined,
                          title: 'Contas a pagar',
                          metric:
                              '${data['payables_open']} • ${_money(data['payables_amount'])}',
                          subtitle: 'Vencimentos, pagamentos parciais e liquidação.',
                          onTap: () => _open(
                            const _ObligationsScreen(type: 'payable'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.request_quote_outlined,
                          title: 'Contas a receber',
                          metric:
                              '${data['receivables_open']} • ${_money(data['receivables_amount'])}',
                          subtitle: 'Valores previstos e recebimentos ligados à Tesouraria.',
                          onTap: () => _open(
                            const _ObligationsScreen(type: 'receivable'),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.account_balance_outlined,
                          title: 'Orçamentos',
                          metric: '${data['budgets_active']} ativos',
                          subtitle: 'Planeado × realizado × desvio por linha.',
                          onTap: () => _open(const _BudgetsScreen()),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.fact_check_outlined,
                          title: 'Reconciliação',
                          metric:
                              '${data['reconciliations_draft']} em preparação',
                          subtitle: 'Extrato bancário, movimentos conciliados e diferença.',
                          onTap: () => _open(const _ReconciliationsScreen()),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.point_of_sale_outlined,
                          title: 'Sessões de caixa',
                          metric: '${data['cash_active']} ativas',
                          subtitle:
                              '${data['cash_pending_approval']} diferenças aguardam aprovação.',
                          onTap: () => _open(const _CashSessionsScreen()),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.account_tree_outlined,
                          title: 'Centros de custo',
                          metric: '${data['cost_centers']} ativos',
                          subtitle: 'Estrutura de análise para despesas e receitas.',
                          onTap: () => _open(const _CostCentersScreen()),
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _OperationCard(
                          icon: Icons.undo_outlined,
                          title: 'Reversões',
                          metric: 'Histórico preservado',
                          subtitle: 'Corrige movimentos sem apagar o lançamento original.',
                          onTap: () => _open(const _ReversalScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({
    required this.icon,
    required this.title,
    required this.metric,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String metric;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(metric, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(subtitle),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.science_outlined),
        title: const Text('Pré-visualização em modo demonstração'),
        subtitle: const Text(
          'A navegação e os dados de exemplo estão disponíveis. Operações de escrita ficam desativadas sem simular alterações no backend.',
        ),
      ),
    );
  }
}

class _ObligationsScreen extends StatefulWidget {
  const _ObligationsScreen({required this.type});

  final String type;

  @override
  State<_ObligationsScreen> createState() => _ObligationsScreenState();
}

class _ObligationsScreenState extends State<_ObligationsScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  bool get _payable => widget.type == 'payable';
  String get _title => _payable ? 'Contas a pagar' : 'Contas a receber';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.listObligations(widget.type);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _create() async {
    final result = await _obligationDialog(context, title: 'Nova obrigação');
    if (result == null) return;
    try {
      await _repository.saveObligation(widget.type, result);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _settle(Map<String, dynamic> row) async {
    final accounts = await _repository.listAccounts();
    if (!mounted) return;
    final result = await _settlementDialog(
      context,
      accounts: accounts,
      outstanding: treasuryOutstanding(row),
      payable: _payable,
    );
    if (result == null) return;
    try {
      await _repository.settleObligation(
        type: widget.type,
        obligationId: row['id'].toString(),
        accountId: result['account_id'].toString(),
        amount: treasuryNumber(result['amount']),
        paymentMethod: result['payment_method']?.toString() ?? '',
        notes: result['notes']?.toString() ?? '',
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _cancel(Map<String, dynamic> row) async {
    final reason = await _reasonDialog(context, 'Motivo do cancelamento');
    if (reason == null) return;
    try {
      await _repository.cancelObligation(
        type: widget.type,
        obligationId: row['id'].toString(),
        reason: reason,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: _repository.canPlan && !_repository.isDemo
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            )
          : null,
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
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (_repository.isDemo) ...[
                  const _DemoBanner(),
                  const SizedBox(height: 12),
                ],
                if (rows.isEmpty)
                  const _EmptyCard('Sem obrigações financeiras registadas.')
                else
                  ...rows.map((row) {
                    final status = row['status']?.toString() ?? 'open';
                    final outstanding = treasuryOutstanding(row);
                    final overdue = treasuryObligationOverdue(row);
                    final open = status != 'paid' && status != 'cancelled';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row['counterparty']?.toString() ?? 'Entidade',
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      Text(row['description']?.toString() ?? ''),
                                    ],
                                  ),
                                ),
                                _StatusChip(status: status, overdue: overdue),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 14,
                              runSpacing: 6,
                              children: [
                                Text('Total: ${_money(row['amount'])}'),
                                Text('Liquidado: ${_money(row['settled_amount'])}'),
                                Text('Saldo: ${_money(outstanding)}'),
                                Text('Vence: ${_date(row['due_date'])}'),
                              ],
                            ),
                            if (row['cost_center_name'] != null) ...[
                              const SizedBox(height: 6),
                              Text('Centro: ${row['cost_center_name']}'),
                            ],
                            if (open &&
                                _repository.canPlan &&
                                !_repository.isDemo) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _settle(row),
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: Text(_payable ? 'Pagar' : 'Receber'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: treasuryNumber(row['settled_amount']) == 0
                                        ? () => _cancel(row)
                                        : null,
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text('Cancelar'),
                                  ),
                                ],
                              ),
                            ],
                          ],
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

class _BudgetsScreen extends StatefulWidget {
  const _BudgetsScreen();

  @override
  State<_BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<_BudgetsScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listBudgets();

  Future<void> _create() async {
    final result = await _budgetDialog(context);
    if (result == null) return;
    try {
      await _repository.saveBudget(result);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Orçamentos')),
      floatingActionButton: _repository.canPlan && !_repository.isDemo
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Novo'),
            )
          : null,
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo) ...[
                const _DemoBanner(),
                const SizedBox(height: 12),
              ],
              if (rows.isEmpty)
                const _EmptyCard('Sem orçamentos registados.')
              else
                ...rows.map(
                  (row) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(row['name']?.toString() ?? 'Orçamento'),
                      subtitle: Text(
                        '${_date(row['period_start'])} — ${_date(row['period_end'])}',
                      ),
                      trailing: Text(_statusLabel(row['status']?.toString())),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _BudgetDetailScreen(budget: row),
                          ),
                        );
                        if (mounted) setState(_reload);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetDetailScreen extends StatefulWidget {
  const _BudgetDetailScreen({required this.budget});

  final Map<String, dynamic> budget;

  @override
  State<_BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends State<_BudgetDetailScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.budget['status']?.toString() ?? 'draft';
    _reload();
  }

  void _reload() {
    _future = _repository.budgetPerformance(widget.budget['id'].toString());
  }

  Future<void> _addLine() async {
    final centers = await _repository.listCostCenters();
    if (!mounted) return;
    final result = await _budgetLineDialog(context, centers: centers);
    if (result == null) return;
    try {
      await _repository.saveBudgetLine(widget.budget['id'].toString(), result);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _changeStatus(String next) async {
    try {
      await _repository.setBudgetStatus(widget.budget['id'].toString(), next);
      if (!mounted) return;
      setState(() {
        _status = next;
        _reload();
      });
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.budget['name']?.toString() ?? 'Orçamento')),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_date(widget.budget['period_start'])} — ${_date(widget.budget['period_end'])}',
                      ),
                      const SizedBox(height: 8),
                      Text('Estado: ${_statusLabel(_status)}'),
                      if (_repository.canPlan && !_repository.isDemo) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_status == 'draft')
                              FilledButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add),
                                label: const Text('Adicionar linha'),
                              ),
                            if (_status == 'draft')
                              OutlinedButton(
                                onPressed: () => _changeStatus('approved'),
                                child: const Text('Aprovar orçamento'),
                              ),
                            if (_status == 'approved')
                              OutlinedButton(
                                onPressed: () => _changeStatus('closed'),
                                child: const Text('Fechar orçamento'),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Planeado × realizado', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const _EmptyCard('Ainda não existem linhas neste orçamento.')
              else
                ...rows.map(
                  (row) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['label']?.toString() ?? 'Linha',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 16,
                            runSpacing: 6,
                            children: [
                              Text('Planeado: ${_money(row['planned_amount'])}'),
                              Text('Realizado: ${_money(row['actual_amount'])}'),
                              Text('Desvio: ${_money(row['variance_amount'])}'),
                            ],
                          ),
                          if (row['cost_center_name'] != null)
                            Text('Centro: ${row['cost_center_name']}'),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReconciliationsScreen extends StatefulWidget {
  const _ReconciliationsScreen();

  @override
  State<_ReconciliationsScreen> createState() => _ReconciliationsScreenState();
}

class _ReconciliationsScreenState extends State<_ReconciliationsScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listReconciliations();

  Future<void> _create() async {
    final accounts = await _repository.listAccounts();
    if (!mounted) return;
    final result = await _reconciliationDialog(context, accounts: accounts);
    if (result == null) return;
    try {
      await _repository.saveReconciliation(result);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reconciliação bancária')),
      floatingActionButton: _repository.canPlan && !_repository.isDemo
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Nova'),
            )
          : null,
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo) ...[
                const _DemoBanner(),
                const SizedBox(height: 12),
              ],
              if (rows.isEmpty)
                const _EmptyCard('Sem reconciliações registadas.')
              else
                ...rows.map((row) {
                  final closed = row['status'] == 'closed';
                  return Card(
                    child: ListTile(
                      leading: Icon(closed ? Icons.verified_outlined : Icons.pending_actions),
                      title: Text(row['account_name']?.toString() ?? 'Conta bancária'),
                      subtitle: Text(
                        '${_date(row['period_start'])} — ${_date(row['period_end'])}\n'
                        'Extrato: ${_money(row['statement_closing_balance'])}'
                        '${closed ? ' • Diferença: ${_money(row['difference_amount'])}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: Text(_statusLabel(row['status']?.toString())),
                      onTap: closed || _repository.isDemo
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _ReconciliationDetailScreen(reconciliation: row),
                                ),
                              );
                              if (mounted) setState(_reload);
                            },
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _ReconciliationDetailScreen extends StatefulWidget {
  const _ReconciliationDetailScreen({required this.reconciliation});

  final Map<String, dynamic> reconciliation;

  @override
  State<_ReconciliationDetailScreen> createState() =>
      _ReconciliationDetailScreenState();
}

class _ReconciliationDetailScreenState
    extends State<_ReconciliationDetailScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<_ReconciliationData> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_ReconciliationData> _load() async {
    final values = await Future.wait<dynamic>([
      _repository.listReconciliationTransactions(widget.reconciliation),
      _repository.reconciliationTransactionIds(
        widget.reconciliation['id'].toString(),
      ),
    ]);
    return _ReconciliationData(
      List<Map<String, dynamic>>.from(values[0] as List),
      Set<String>.from(values[1] as Set),
    );
  }

  Future<void> _toggle(String id, bool included) async {
    try {
      await _repository.setReconciliationTransaction(
        reconciliationId: widget.reconciliation['id'].toString(),
        transactionId: id,
        included: included,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _close() async {
    try {
      final difference = await _repository.closeReconciliation(
        widget.reconciliation['id'].toString(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reconciliação fechada'),
          content: Text('Diferença entre extrato e registo: ${_money(difference)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Movimentos a conciliar')),
      body: FutureBuilder<_ReconciliationData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                '${widget.reconciliation['account_name'] ?? 'Conta'} • '
                '${_date(widget.reconciliation['period_start'])} — '
                '${_date(widget.reconciliation['period_end'])}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (data.transactions.isEmpty)
                const _EmptyCard('Sem movimentos neste período.')
              else
                ...data.transactions.map((row) {
                  final id = row['id'].toString();
                  return Card(
                    child: CheckboxListTile(
                      value: data.included.contains(id),
                      onChanged: _repository.canPlan
                          ? (value) => _toggle(id, value == true)
                          : null,
                      title: Text(row['description']?.toString() ?? 'Movimento'),
                      subtitle: Text(
                        '${_date(row['transaction_date'])} • ${_statusLabel(row['kind']?.toString())}',
                      ),
                      secondary: Text(_money(row['amount'])),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              if (_repository.canPlan)
                FilledButton.icon(
                  onPressed: _close,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Fechar reconciliação'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReconciliationData {
  const _ReconciliationData(this.transactions, this.included);
  final List<Map<String, dynamic>> transactions;
  final Set<String> included;
}

class _CashSessionsScreen extends StatefulWidget {
  const _CashSessionsScreen();

  @override
  State<_CashSessionsScreen> createState() => _CashSessionsScreenState();
}

class _CashSessionsScreenState extends State<_CashSessionsScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listCashSessions();

  Future<void> _openSession() async {
    final accounts = await _repository.listAccounts();
    if (!mounted) return;
    final cashAccounts = accounts
        .where((row) =>
            row['account_type']?.toString() == 'cash' ||
            row['type']?.toString() == 'cash')
        .toList();
    final result = await _cashOpenDialog(context, accounts: cashAccounts);
    if (result == null) return;
    try {
      await _repository.openCashSession(
        result['account_id'].toString(),
        treasuryNumber(result['opening_amount']),
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _closeSession(Map<String, dynamic> row) async {
    final result = await _cashCloseDialog(context);
    if (result == null) return;
    try {
      await _repository.closeCashSession(
        row['id'].toString(),
        treasuryNumber(result['counted_amount']),
        result['notes']?.toString() ?? '',
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  Future<void> _approve(Map<String, dynamic> row) async {
    final reason = await _reasonDialog(context, 'Justificação da aprovação');
    if (reason == null) return;
    try {
      await _repository.approveCashSession(row['id'].toString(), reason);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessões de caixa')),
      floatingActionButton: _repository.canManageCash && !_repository.isDemo
          ? FloatingActionButton.extended(
              onPressed: _openSession,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Abrir caixa'),
            )
          : null,
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo) ...[
                const _DemoBanner(),
                const SizedBox(height: 12),
              ],
              if (rows.isEmpty)
                const _EmptyCard('Sem sessões de caixa registadas.')
              else
                ...rows.map((row) {
                  final status = row['status']?.toString() ?? 'open';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  row['account_name']?.toString() ?? 'Caixa',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              _StatusChip(status: status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('Abertura: ${_money(row['opening_amount'])}'),
                          if (row['expected_amount'] != null)
                            Text('Esperado: ${_money(row['expected_amount'])}'),
                          if (row['counted_amount'] != null)
                            Text('Contado: ${_money(row['counted_amount'])}'),
                          if (row['difference_amount'] != null)
                            Text('Diferença: ${_money(row['difference_amount'])}'),
                          if (!_repository.isDemo) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (status == 'open' && _repository.canManageCash)
                                  FilledButton(
                                    onPressed: () => _closeSession(row),
                                    child: const Text('Fechar caixa'),
                                  ),
                                if (status == 'pending_approval' &&
                                    _repository.canApproveCash)
                                  FilledButton.tonal(
                                    onPressed: () => _approve(row),
                                    child: const Text('Aprovar diferença'),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _CostCentersScreen extends StatefulWidget {
  const _CostCentersScreen();

  @override
  State<_CostCentersScreen> createState() => _CostCentersScreenState();
}

class _CostCentersScreenState extends State<_CostCentersScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _future = _repository.listCostCenters(includeInactive: true);

  Future<void> _edit([Map<String, dynamic>? row]) async {
    final result = await _costCenterDialog(context, row: row);
    if (result == null) return;
    try {
      await _repository.saveCostCenter(
        id: row?['id']?.toString(),
        name: result['name'].toString(),
        code: result['code']?.toString() ?? '',
        active: result['active'] == true,
      );
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centros de custo')),
      floatingActionButton: _repository.canPlan && !_repository.isDemo
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Adicionar'),
            )
          : null,
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo) ...[
                const _DemoBanner(),
                const SizedBox(height: 12),
              ],
              ...rows.map(
                (row) => Card(
                  child: ListTile(
                    leading: Icon(
                      row['active'] == false
                          ? Icons.pause_circle_outline
                          : Icons.account_tree_outlined,
                    ),
                    title: Text(row['name']?.toString() ?? 'Centro'),
                    subtitle: Text(
                      [
                        row['code']?.toString(),
                        row['active'] == false ? 'Inativo' : 'Ativo',
                      ].where((value) => value != null && value.isNotEmpty).join(' • '),
                    ),
                    trailing: _repository.canPlan && !_repository.isDemo
                        ? const Icon(Icons.edit_outlined)
                        : null,
                    onTap: _repository.canPlan && !_repository.isDemo
                        ? () => _edit(row)
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReversalScreen extends StatefulWidget {
  const _ReversalScreen();

  @override
  State<_ReversalScreen> createState() => _ReversalScreenState();
}

class _ReversalScreenState extends State<_ReversalScreen> {
  final TreasuryOperationalRepository _repository =
      TreasuryOperationalRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _repository.listReversibleTransactions();

  Future<void> _reverse(Map<String, dynamic> row) async {
    final reason = await _reasonDialog(context, 'Motivo da reversão');
    if (reason == null) return;
    try {
      await _repository.reverseTransaction(row['id'].toString(), reason);
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reversões de movimentos')),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo) ...[
                const _DemoBanner(),
                const SizedBox(height: 12),
              ],
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Reverter não apaga o histórico'),
                  subtitle: Text(
                    'É criado um movimento inverso ligado ao lançamento original. Movimentos de outros módulos devem ser corrigidos na respetiva origem.',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                const _EmptyCard('Sem movimentos elegíveis para reversão.')
              else
                ...rows.map(
                  (row) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row['description']?.toString() ?? 'Movimento',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_date(row['transaction_date'])} • '
                            '${row['account_name'] ?? 'Conta'} • ${_money(row['amount'])}',
                          ),
                          if (_repository.canReverse && !_repository.isDemo) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => _reverse(row),
                              icon: const Icon(Icons.undo_outlined),
                              label: const Text('Reverter movimento'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.overdue = false});
  final String status;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(overdue ? 'Em atraso' : _statusLabel(status)));
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.inbox_outlined),
        title: Text(message),
      ),
    );
  }
}

Future<Map<String, dynamic>?> _obligationDialog(
  BuildContext context, {
  required String title,
}) async {
  final counterparty = TextEditingController();
  final description = TextEditingController();
  final dueDate = TextEditingController(
    text: DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T').first,
  );
  final amount = TextEditingController();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: counterparty,
              decoration: const InputDecoration(labelText: 'Entidade / fornecedor'),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Descrição'),
            ),
            TextField(
              controller: dueDate,
              decoration: const InputDecoration(labelText: 'Vencimento (AAAA-MM-DD)'),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor (€)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'counterparty': counterparty.text,
            'description': description.text,
            'due_date': dueDate.text,
            'amount': amount.text.replaceAll(',', '.'),
          }),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  counterparty.dispose();
  description.dispose();
  dueDate.dispose();
  amount.dispose();
  return result;
}

Future<Map<String, dynamic>?> _settlementDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> accounts,
  required double outstanding,
  required bool payable,
}) async {
  if (accounts.isEmpty) return null;
  String? accountId = accounts.first['id']?.toString();
  final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
  final method = TextEditingController();
  final notes = TextEditingController();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(payable ? 'Registar pagamento' : 'Registar recebimento'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Conta financeira'),
                items: accounts
                    .map(
                      (row) => DropdownMenuItem<String>(
                        value: row['id']?.toString(),
                        child: Text(row['name']?.toString() ?? 'Conta'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => accountId = value),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor (€)'),
              ),
              TextField(
                controller: method,
                decoration: const InputDecoration(labelText: 'Método de pagamento'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: accountId == null
                ? null
                : () => Navigator.of(context).pop({
                      'account_id': accountId,
                      'amount': amount.text.replaceAll(',', '.'),
                      'payment_method': method.text,
                      'notes': notes.text,
                    }),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  method.dispose();
  notes.dispose();
  return result;
}

Future<Map<String, dynamic>?> _budgetDialog(BuildContext context) async {
  final name = TextEditingController();
  final start = TextEditingController(text: '${DateTime.now().year}-01-01');
  final end = TextEditingController(text: '${DateTime.now().year}-12-31');
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Novo orçamento'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: start, decoration: const InputDecoration(labelText: 'Início (AAAA-MM-DD)')),
            TextField(controller: end, decoration: const InputDecoration(labelText: 'Fim (AAAA-MM-DD)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'name': name.text,
            'period_start': start.text,
            'period_end': end.text,
          }),
          child: const Text('Criar'),
        ),
      ],
    ),
  );
  name.dispose();
  start.dispose();
  end.dispose();
  return result;
}

Future<Map<String, dynamic>?> _budgetLineDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> centers,
}) async {
  final label = TextEditingController();
  final amount = TextEditingController();
  String type = 'expense';
  String? centerId;
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Linha do orçamento'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: label, decoration: const InputDecoration(labelText: 'Descrição')),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: 'income', child: Text('Receita')),
                  DropdownMenuItem(value: 'expense', child: Text('Despesa')),
                ],
                onChanged: (value) => setDialogState(() => type = value ?? 'expense'),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Valor planeado (€)'),
              ),
              DropdownButtonFormField<String?>(
                initialValue: centerId,
                decoration: const InputDecoration(labelText: 'Centro de custo (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sem centro específico')),
                  ...centers.map(
                    (row) => DropdownMenuItem<String?>(
                      value: row['id']?.toString(),
                      child: Text(row['name']?.toString() ?? 'Centro'),
                    ),
                  ),
                ],
                onChanged: (value) => setDialogState(() => centerId = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'label': label.text,
              'line_type': type,
              'planned_amount': amount.text.replaceAll(',', '.'),
              'cost_center_id': centerId,
            }),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  label.dispose();
  amount.dispose();
  return result;
}

Future<Map<String, dynamic>?> _reconciliationDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> accounts,
}) async {
  if (accounts.isEmpty) return null;
  String? accountId = accounts.first['id']?.toString();
  final now = DateTime.now();
  final start = TextEditingController(
    text: '${now.year}-${now.month.toString().padLeft(2, '0')}-01',
  );
  final end = TextEditingController(text: now.toIso8601String().split('T').first);
  final opening = TextEditingController();
  final closing = TextEditingController();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Nova reconciliação'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: const InputDecoration(labelText: 'Conta'),
                items: accounts
                    .map((row) => DropdownMenuItem<String>(
                          value: row['id']?.toString(),
                          child: Text(row['name']?.toString() ?? 'Conta'),
                        ))
                    .toList(),
                onChanged: (value) => setDialogState(() => accountId = value),
              ),
              TextField(controller: start, decoration: const InputDecoration(labelText: 'Início (AAAA-MM-DD)')),
              TextField(controller: end, decoration: const InputDecoration(labelText: 'Fim (AAAA-MM-DD)')),
              TextField(
                controller: opening,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Saldo inicial do extrato'),
              ),
              TextField(
                controller: closing,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Saldo final do extrato'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: accountId == null
                ? null
                : () => Navigator.of(context).pop({
                      'account_id': accountId,
                      'period_start': start.text,
                      'period_end': end.text,
                      'statement_opening_balance': opening.text.replaceAll(',', '.'),
                      'statement_closing_balance': closing.text.replaceAll(',', '.'),
                    }),
            child: const Text('Criar'),
          ),
        ],
      ),
    ),
  );
  start.dispose();
  end.dispose();
  opening.dispose();
  closing.dispose();
  return result;
}

Future<Map<String, dynamic>?> _cashOpenDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> accounts,
}) async {
  if (accounts.isEmpty) {
    _showError(context, 'Não existe nenhuma conta ativa do tipo Caixa / Dinheiro.');
    return null;
  }
  String? accountId = accounts.first['id']?.toString();
  final amount = TextEditingController();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Abrir sessão de caixa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: accountId,
              decoration: const InputDecoration(labelText: 'Caixa'),
              items: accounts
                  .map((row) => DropdownMenuItem<String>(
                        value: row['id']?.toString(),
                        child: Text(row['name']?.toString() ?? 'Caixa'),
                      ))
                  .toList(),
              onChanged: (value) => setDialogState(() => accountId = value),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor contado na abertura'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: accountId == null
                ? null
                : () => Navigator.of(context).pop({
                      'account_id': accountId,
                      'opening_amount': amount.text.replaceAll(',', '.'),
                    }),
            child: const Text('Abrir'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  return result;
}

Future<Map<String, dynamic>?> _cashCloseDialog(BuildContext context) async {
  final amount = TextEditingController();
  final notes = TextEditingController();
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Fechar sessão de caixa'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Valor contado no fecho'),
          ),
          TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notas')),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop({
            'counted_amount': amount.text.replaceAll(',', '.'),
            'notes': notes.text,
          }),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
  amount.dispose();
  notes.dispose();
  return result;
}

Future<Map<String, dynamic>?> _costCenterDialog(
  BuildContext context, {
  Map<String, dynamic>? row,
}) async {
  final name = TextEditingController(text: row?['name']?.toString() ?? '');
  final code = TextEditingController(text: row?['code']?.toString() ?? '');
  var active = row?['active'] != false;
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(row == null ? 'Novo centro de custo' : 'Editar centro de custo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
            TextField(controller: code, decoration: const InputDecoration(labelText: 'Código')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: active,
              onChanged: (value) => setDialogState(() => active = value),
              title: const Text('Ativo'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              'name': name.text,
              'code': code.text,
              'active': active,
            }),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  code.dispose();
  return result;
}

Future<String?> _reasonDialog(BuildContext context, String title) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Justificação'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Confirmar'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result == null || result.length < 3 ? null : result;
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString())),
  );
}

String _money(Object? value) =>
    '${treasuryNumber(value).toStringAsFixed(2).replaceAll('.', ',')} €';

String _date(Object? value) {
  final text = value?.toString() ?? '';
  if (text.length < 10) return text;
  final parts = text.substring(0, 10).split('-');
  if (parts.length != 3) return text;
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

String _statusLabel(String? value) => switch (value) {
      'open' => 'Aberto',
      'partial' => 'Parcial',
      'paid' => 'Liquidado',
      'cancelled' => 'Cancelado',
      'draft' => 'Rascunho',
      'approved' => 'Aprovado',
      'closed' => 'Fechado',
      'pending_approval' => 'Aguarda aprovação',
      'income' => 'Receita',
      'expense' => 'Despesa',
      'transfer' => 'Transferência',
      _ => value ?? '',
    };
