import 'package:flutter/material.dart';

import '../repositories/inventory_advanced_repository.dart';
import 'inventory_breakages_screen.dart';
import 'inventory_lots_screen.dart';
import 'inventory_reservations_screen.dart';

class InventoryAdvancedScreen extends StatefulWidget {
  const InventoryAdvancedScreen({super.key});

  @override
  State<InventoryAdvancedScreen> createState() => _InventoryAdvancedScreenState();
}

class _InventoryAdvancedScreenState extends State<InventoryAdvancedScreen> {
  final InventoryAdvancedRepository _repository = InventoryAdvancedRepository();
  late Future<Map<String, dynamic>> _summary;

  @override
  void initState() {
    super.initState();
    _summary = _repository.summary();
  }

  void _reloadSummary() {
    if (!mounted) return;
    setState(() => _summary = _repository.summary());
  }

  @override
  Widget build(BuildContext context) {
    if (!_repository.canView) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Sem permissão para consultar o inventário.'),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _summary,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: const Text('Não foi possível carregar o resumo'),
                      subtitle: Text(snapshot.error.toString()),
                      trailing: IconButton(
                        onPressed: _reloadSummary,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              return _AdvancedSummary(
                data: data,
                manager: _repository.canManage,
                onRefresh: _reloadSummary,
              );
            },
          ),
          const Material(
            child: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: 'Reservas', icon: Icon(Icons.bookmark_outline)),
                Tab(text: 'Lotes & Validades', icon: Icon(Icons.event_available_outlined)),
                Tab(text: 'Quebras', icon: Icon(Icons.broken_image_outlined)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                InventoryReservationsScreen(
                  repository: _repository,
                  onChanged: _reloadSummary,
                ),
                InventoryLotsScreen(
                  repository: _repository,
                  onChanged: _reloadSummary,
                ),
                InventoryBreakagesScreen(
                  repository: _repository,
                  onChanged: _reloadSummary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSummary extends StatelessWidget {
  const _AdvancedSummary({
    required this.data,
    required this.manager,
    required this.onRefresh,
  });

  final Map<String, dynamic> data;
  final bool manager;
  final VoidCallback onRefresh;

  int _int(String key) => int.tryParse(data[key]?.toString() ?? '') ?? 0;
  double _number(String key) => inventoryQuantity(data[key]);

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _Metric(
        icon: Icons.bookmark_outline,
        label: 'Reservas ativas',
        value: '${_int('active_reservations')}',
      ),
      _Metric(
        icon: Icons.alarm_outlined,
        label: 'A terminar em 3 dias',
        value: '${_int('reservations_expiring_soon')}',
      ),
      if (manager)
        _Metric(
          icon: Icons.event_available_outlined,
          label: 'Validade ≤ 30 dias',
          value: '${_int('lots_expiring_30d')}',
        ),
      if (manager)
        _Metric(
          icon: Icons.warning_amber_outlined,
          label: 'Lotes expirados',
          value: '${_int('expired_lots')}',
        ),
      if (manager)
        _Metric(
          icon: Icons.broken_image_outlined,
          label: 'Quebras este mês',
          value: _formatQuantity(_number('breakage_units_month')),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Stock avançado',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: metrics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => metrics[index],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2);
}
