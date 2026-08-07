import 'package:flutter/material.dart';

import '../repositories/inventory_foundation_repository.dart';
import 'shop_screen.dart';

class InventoryHubScreen extends StatefulWidget {
  const InventoryHubScreen({super.key});

  @override
  State<InventoryHubScreen> createState() => _InventoryHubScreenState();
}

class _InventoryHubScreenState extends State<InventoryHubScreen> {
  final InventoryFoundationRepository _repository =
      InventoryFoundationRepository();
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.summary();
  }

  void _reload() => setState(() => _future = _repository.summary());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Material(
            child: TabBar(
              isScrollable: true,
              tabs: const [
                Tab(text: 'Resumo', icon: Icon(Icons.dashboard_outlined)),
                Tab(text: 'Loja', icon: Icon(Icons.storefront_outlined)),
                Tab(text: 'Bar', icon: Icon(Icons.local_bar_outlined)),
                Tab(text: 'Património', icon: Icon(Icons.home_repair_service_outlined)),
                Tab(text: 'Movimentos', icon: Icon(Icons.swap_horiz_outlined)),
                Tab(text: 'Inventário físico', icon: Icon(Icons.fact_check_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SummaryTab(future: _future, onRefresh: _reload),
                const ShopScreen(),
                const _FoundationPlaceholder(
                  icon: Icons.local_bar_outlined,
                  title: 'Bar',
                  description:
                      'Estrutura criada. Nos próximos blocos entram consumíveis, unidades e conversões.',
                ),
                const _FoundationPlaceholder(
                  icon: Icons.home_repair_service_outlined,
                  title: 'Património',
                  description:
                      'Estrutura criada para equipamentos, localizações, empréstimos e manutenção.',
                ),
                const _FoundationPlaceholder(
                  icon: Icons.swap_horiz_outlined,
                  title: 'Movimentos',
                  description:
                      'Será a visão unificada de entradas, saídas, vendas, entregas e ajustes.',
                ),
                const _FoundationPlaceholder(
                  icon: Icons.fact_check_outlined,
                  title: 'Inventário físico',
                  description:
                      'Preparado para contagens e comparação entre stock teórico e real.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.future, required this.onRefresh});

  final Future<Map<String, dynamic>> future;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            onRefresh();
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Património & Inventário',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              const Text('Visão global da Loja, Bar e património relevante do clube.'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric('Loja', '${data['shop_products'] ?? 0}', Icons.storefront_outlined),
                  _Metric('Bar', '${data['bar_products'] ?? 0}', Icons.local_bar_outlined),
                  _Metric('Património', '${data['assets'] ?? 0}', Icons.home_repair_service_outlined),
                  _Metric('Stock baixo', '${data['low_stock'] ?? 0}', Icons.warning_amber_outlined),
                  _Metric('Reservado', _number(data['reserved_units']), Icons.bookmark_outline),
                  _Metric('Valor stock', '${_money(data['stock_value'])} €', Icons.euro_outlined),
                  _Metric('Valor património', '${_money(data['asset_value'])} €', Icons.account_balance_outlined),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(label),
          subtitle: Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
      ),
    );
  }
}

class _FoundationPlaceholder extends StatelessWidget {
  const _FoundationPlaceholder({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(icon, size: 52),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(description, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _money(Object? value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  return number.toStringAsFixed(2).replaceAll('.', ',');
}

String _number(Object? value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;
  if (number == number.roundToDouble()) return number.toInt().toString();
  return number.toStringAsFixed(2).replaceAll('.', ',');
}
