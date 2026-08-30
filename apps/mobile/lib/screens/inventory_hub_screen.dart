import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../repositories/inventory_foundation_repository.dart';
import 'assets_module_screen.dart';
import 'assets_qr_screen.dart';
import 'inventory_locations_screen.dart';
import 'inventory_movements_screen.dart';
import 'physical_inventory_screen.dart';
import 'product_photos_screen.dart';
import 'shop_management_screen.dart';
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
    final demo = AppConfig.demoMode;

    return DefaultTabController(
      length: 8,
      child: Column(
        children: [
          Material(
            child: TabBar(
              isScrollable: true,
              tabs: const [
                Tab(text: 'Resumo', icon: Icon(Icons.dashboard_outlined)),
                Tab(text: 'Loja', icon: Icon(Icons.storefront_outlined)),
                Tab(text: 'Fotos', icon: Icon(Icons.photo_library_outlined)),
                Tab(
                  text: 'Património',
                  icon: Icon(Icons.home_repair_service_outlined),
                ),
                Tab(text: 'QR', icon: Icon(Icons.qr_code_scanner)),
                Tab(text: 'Localizações', icon: Icon(Icons.place_outlined)),
                Tab(
                  text: 'Movimentos',
                  icon: Icon(Icons.swap_horiz_outlined),
                ),
                Tab(
                  text: 'Inventário físico',
                  icon: Icon(Icons.fact_check_outlined),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SummaryTab(future: _future, onRefresh: _reload),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Loja',
                        icon: Icons.storefront_outlined,
                        description:
                            'Artigos, variantes, encomendas e gestão de merchandising usam dados reais do clube.',
                      )
                    : const ShopScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Fotos de produtos',
                        icon: Icons.photo_library_outlined,
                        description:
                            'A galeria de produtos depende do Storage e dos registos reais do inventário.',
                      )
                    : const ProductPhotosScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Património',
                        icon: Icons.home_repair_service_outlined,
                        description:
                            'Bens, estados, atribuições e operações patrimoniais usam a base de dados do clube.',
                      )
                    : const AssetsModuleScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'QR',
                        icon: Icons.qr_code_scanner,
                        description:
                            'A leitura e associação de códigos QR necessita dos ativos reais do clube.',
                      )
                    : const AssetsQrScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Localizações',
                        icon: Icons.place_outlined,
                        description:
                            'As localizações e respetivos stocks são apresentadas com dados reais por clube.',
                      )
                    : const InventoryLocationsScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Movimentos',
                        icon: Icons.swap_horiz_outlined,
                        description:
                            'Entradas, saídas, transferências e reservas são operações auditadas no ambiente real.',
                      )
                    : const InventoryMovementsScreen(),
                demo
                    ? const _InventoryDemoPreview(
                        title: 'Inventário físico',
                        icon: Icons.fact_check_outlined,
                        description:
                            'As contagens físicas e reconciliações dependem das localizações e stocks reais.',
                      )
                    : const PhysicalInventoryScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryDemoPreview extends StatelessWidget {
  const _InventoryDemoPreview({
    required this.title,
    required this.icon,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.onPrimaryContainer,
                    child: Icon(icon, size: 32),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  const Chip(
                    avatar: Icon(Icons.science_outlined, size: 18),
                    label: Text('Pré-visualização em modo demonstração'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Neste modo não é feita ligação ao Supabase. No ambiente real este separador carrega os dados e operações autorizados pelas permissões do utilizador.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({
    required this.future,
    required this.onRefresh,
  });

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
              const Text(
                'Visão global da Loja, património e inventário físico do clube.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(
                    'Loja',
                    '${data['shop_products'] ?? 0}',
                    Icons.storefront_outlined,
                  ),
                  _Metric(
                    'Património',
                    '${data['assets'] ?? 0}',
                    Icons.home_repair_service_outlined,
                  ),
                  _Metric(
                    'Stock baixo',
                    '${data['low_stock'] ?? 0}',
                    Icons.warning_amber_outlined,
                  ),
                  _Metric(
                    'Reservado',
                    _number(data['reserved_units']),
                    Icons.bookmark_outline,
                  ),
                  _Metric(
                    'Valor stock',
                    '${_money(data['stock_value'])} €',
                    Icons.euro_outlined,
                  ),
                  _Metric(
                    'Valor património',
                    '${_money(data['asset_value'])} €',
                    Icons.account_balance_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.manage_search_outlined),
                  ),
                  title: const Text('Gestão avançada da Loja'),
                  subtitle: const Text(
                    'Definir artigos para Público / Prospect / Full Color, preços próprios e ver o que falta encomendar ao fornecedor.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: AppConfig.demoMode
                      ? () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'A gestão avançada da Loja requer o ambiente real.',
                              ),
                            ),
                          );
                        }
                      : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const ShopManagementScreen(),
                            ),
                          ),
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
