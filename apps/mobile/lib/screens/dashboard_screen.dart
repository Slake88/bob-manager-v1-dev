import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dashboard_repository.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: DashboardRepository().summary(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final euro = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
        final cards = <(String, String, IconData)>[
          ('Membros ativos', '${data['members']}', Icons.groups_outlined),
          ('Prospects', '${data['prospects']}', Icons.shield_outlined),
          ('Saldo total', euro.format(data['total_balance']), Icons.account_balance_wallet_outlined),
          ('Quotas pendentes', euro.format(data['fee_outstanding']), Icons.receipt_long_outlined),
          ('Eventos abertos', '${data['open_events']}', Icons.event_outlined),
          ('Stock baixo', '${data['low_stock']}', Icons.inventory_2_outlined),
          ('Documentos a expirar', '${data['expiring_documents']}', Icons.event_busy_outlined),
          ('Aprovações pendentes', '${data['pending_approvals']}', Icons.approval_outlined),
        ];

        final monthlyResult = (data['monthly_income'] as num).toDouble() -
            (data['monthly_expense'] as num).toDouble();

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
                      width: 240,
                      child: Card(
                        child: ListTile(
                          leading: CircleAvatar(child: Icon(item.$3)),
                          title: Text(item.$1),
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
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resultado do mês', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      euro.format(monthlyResult),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
