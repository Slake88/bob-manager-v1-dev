import 'package:flutter/material.dart';

import '../core/fees_economics.dart';
import '../repositories/fees_operational_repository.dart';
import 'fees_member_detail_screen.dart';
import 'fees_receive_payment_screen.dart';
import 'fees_reported_payments_screen.dart';
import 'fees_settings_operational_screen.dart';

class FeesOperationalScreen extends StatefulWidget {
  const FeesOperationalScreen({super.key});

  @override
  State<FeesOperationalScreen> createState() => _FeesOperationalScreenState();
}

class _FeesOperationalScreenState extends State<FeesOperationalScreen> {
  final FeesOperationalRepository _repository = FeesOperationalRepository();
  late Future<_FeesOverview> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_FeesOverview> _load() async {
    final obligations = await _repository.listObligations();
    final reported = await _repository.listReportedPayments();
    final outstanding = obligations.fold<double>(
      0,
      (sum, row) => sum + feeObligationOutstanding(row),
    );
    final overdue = obligations
        .where((row) => feeObligationOverdue(row))
        .fold<double>(0, (sum, row) => sum + feeObligationOutstanding(row));
    return _FeesOverview(
      outstanding: outstanding,
      overdue: overdue,
      pendingReports: reported.where((row) => row['status'] == 'pending').length,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FeesOverview>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (_repository.isDemo)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.visibility_outlined),
                    title: Text('Modo Demo — apenas leitura'),
                    subtitle: Text('As operações não alteram o Supabase.'),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(label: 'Em dívida', value: _money(data.outstanding)),
                  _Metric(label: 'Vencido', value: _money(data.overdue)),
                  _Metric(
                    label: 'Comunicados pendentes',
                    value: '${data.pendingReports}',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Operações de quotas', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1000
                      ? 3
                      : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                  final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
                  final cards = <Widget>[
                    if (_repository.canManage)
                      _ActionCard(
                        width: width,
                        icon: Icons.payments_outlined,
                        title: 'Receber pagamento',
                        subtitle: 'Distribuir um recebimento por vários meses e crédito.',
                        onTap: () => _open(const FeesReceivePaymentScreen()),
                      ),
                    _ActionCard(
                      width: width,
                      icon: Icons.person_search_outlined,
                      title: 'Por membro',
                      subtitle: 'Saldo, quotas, crédito, pagamentos, isenções e ajustes.',
                      onTap: () => _open(const FeesMemberDetailScreen()),
                    ),
                    _ActionCard(
                      width: width,
                      icon: Icons.receipt_long_outlined,
                      title: 'Pagamentos comunicados',
                      subtitle: _repository.canManage
                          ? 'Validar comprovativos ou consultar o histórico.'
                          : 'Comunicar um pagamento e acompanhar a validação.',
                      onTap: () => _open(const FeesReportedPaymentsScreen()),
                    ),
                    if (_repository.canManage)
                      _ActionCard(
                        width: width,
                        icon: Icons.settings_outlined,
                        title: 'Configuração',
                        subtitle: 'Mensalidade, inscrição e dia de vencimento.',
                        onTap: () => _open(const FeesSettingsOperationalScreen()),
                      ),
                  ];
                  return Wrap(spacing: 12, runSpacing: 12, children: cards);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeesOverview {
  const _FeesOverview({
    required this.outstanding,
    required this.overdue,
    required this.pendingReports,
  });
  final double outstanding;
  final double overdue;
  final int pendingReports;
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(subtitle),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _money(double value) => '${value.toStringAsFixed(2)} €';
