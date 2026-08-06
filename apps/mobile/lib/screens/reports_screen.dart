import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/dashboard_repository.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: DashboardRepository().reportsSummary(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        final euro = NumberFormat.currency(locale: 'pt_PT', symbol: '€');
        final canViewFinancial = data['can_view_financial'] == true;
        final reports = <(String, String, IconData)>[
          ('Membros', '${data['members']} ativos e ${data['prospects']} prospects.', Icons.groups_outlined),
          ('Quotas', '${data['overdue_fees']} vencidas; ${euro.format(data['fee_outstanding'])} pendentes.', Icons.receipt_long_outlined),
          ('Eventos', '${data['open_events']} eventos em preparação ou realização.', Icons.event_outlined),
          ('Inventário', '${data['low_stock']} artigos abaixo do stock recomendado.', Icons.inventory_2_outlined),
          ('Documentos', '${data['expiring_documents']} documentos a expirar nos próximos 30 dias.', Icons.folder_outlined),
          ('Comunicação', '${data['unread_announcements']} comunicados exigem confirmação.', Icons.campaign_outlined),
        ];

        if (canViewFinancial) {
          reports.insert(
            2,
            (
              'Tesouraria',
              'Saldo ${euro.format(data['total_balance'])}; resultado mensal ${euro.format((data['monthly_income'] as num) - (data['monthly_expense'] as num))}.',
              Icons.account_balance_wallet_outlined,
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Relatórios', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Indicadores consolidados da operação do clube.'),
            const SizedBox(height: 12),
            ...reports.map(
              (report) => Card(
                child: ListTile(
                  leading: Icon(report.$3),
                  title: Text(report.$1),
                  subtitle: Text(report.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${report.$1}: exportação será ligada na integração final.')),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
