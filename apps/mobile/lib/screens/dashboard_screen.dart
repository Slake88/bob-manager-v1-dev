import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/dashboard_indicator_detail.dart';
import '../repositories/dashboard_repository.dart';
import '../widgets/dashboard_indicator_detail_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.repository});

  final DashboardRepository? repository;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DashboardRepository _repository;
  late Future<Map<String, dynamic>> _summary;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DashboardRepository();
    _summary = _repository.summary();
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _repository = widget.repository ?? DashboardRepository();
      _summary = _repository.summary();
    }
  }

  Future<void> _open(DashboardIndicator indicator) async {
    await DashboardIndicatorDetailDialog.show(
      context,
      indicator: indicator,
      repository: _repository,
    );
    if (mounted) {
      final refreshed = _repository.summary();
      setState(() {
        _summary = refreshed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _summary,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final canViewFinancial = data['can_view_financial'] == true;
        final euro = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
        final cards = <(DashboardIndicator, String, IconData)>[
          (
            DashboardIndicator.members,
            '${data['members']}',
            Icons.groups_outlined
          ),
          (
            DashboardIndicator.prospects,
            '${data['prospects']}',
            Icons.shield_outlined
          ),
          if (canViewFinancial) ...[
            (
              DashboardIndicator.totalBalance,
              euro.format(data['total_balance']),
              Icons.account_balance_wallet_outlined
            ),
            (
              DashboardIndicator.feeOutstanding,
              euro.format(data['fee_outstanding']),
              Icons.receipt_long_outlined
            ),
          ],
          (
            DashboardIndicator.openEvents,
            '${data['open_events']}',
            Icons.event_outlined
          ),
          (
            DashboardIndicator.lowStock,
            '${data['low_stock']}',
            Icons.inventory_2_outlined
          ),
          (
            DashboardIndicator.expiringDocuments,
            '${data['expiring_documents']}',
            Icons.event_busy_outlined
          ),
          (
            DashboardIndicator.pendingApprovals,
            '${data['pending_approvals']}',
            Icons.approval_outlined
          ),
        ];

        final monthlyResult = canViewFinancial
            ? (data['monthly_income'] as num).toDouble() -
                (data['monthly_expense'] as num).toDouble()
            : 0.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Resumo do clube',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards
                  .map(
                    (item) => SizedBox(
                      width: MediaQuery.sizeOf(context).width < 272
                          ? MediaQuery.sizeOf(context).width - 32
                          : 240,
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(item.$3)),
                          title: Text(item.$1.title),
                          key: ValueKey('dashboard-card-${item.$1.key}'),
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () => _open(item.$1),
                          subtitle: Text(
                            item.$2,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (canViewFinancial) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Resultado do mês',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        euro.format(monthlyResult),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        'Receitas: ${euro.format(data['monthly_income'])} · Despesas: ${euro.format(data['monthly_expense'])}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Alertas prioritários'),
                subtitle: Text(
                  '${data['overdue_fees']} quotas vencidas · '
                  '${data['expiring_documents']} documentos a expirar · '
                  '${data['low_stock']} artigos com stock baixo',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
