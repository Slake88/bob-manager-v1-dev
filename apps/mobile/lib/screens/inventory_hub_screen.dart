import 'package:flutter/material.dart';

import '../repositories/inventory_foundation_repository.dart';
import 'assets_module_screen.dart';
import 'assets_qr_screen.dart';
import 'bar_screen_v3.dart';
import 'inventory_movements_screen.dart';
import 'physical_inventory_screen.dart';
import 'shop_management_screen.dart';
import 'shop_screen.dart';

class InventoryHubScreen extends StatefulWidget {
  const InventoryHubScreen({super.key});

  @override
  State<InventoryHubScreen> createState() => _InventoryHubScreenState();
}

class _InventoryHubScreenState extends State<InventoryHubScreen> {
  final InventoryFoundationRepository _repository = InventoryFoundationRepository();
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
      length: 7,
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
                Tab(text: 'QR', icon: Icon(Icons.qr_code_scanner)),
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
                const BarScreenV3(),
                const AssetsModuleScreen(),
                const AssetsQrScreen(),
                const InventoryMovementsScreen(),
                const PhysicalInventoryScreen(),
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
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            onRefresh();
            await future;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('Património & Inventário', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
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
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.manage_search_outlined)),
                  title: const Text('Gestão avançada da Loja'),
                  subtitle: const Text('Definir artigos para Público / Prospect / Full Color, preços próprios e ver o que falta encomendar ao fornecedor.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const ShopManagementScreen())),
                ),
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
          subtitle: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

String _money(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  return number.toStringAsFixed(2).replaceAll('.', ',');
}

String _number(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;
  if (number == number.roundToDouble()) return number.toInt().toString();
  return number.toStringAsFixed(2).replaceAll('.', ',');
}
