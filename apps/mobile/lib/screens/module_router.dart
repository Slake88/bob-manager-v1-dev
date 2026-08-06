import 'package:flutter/material.dart';

import '../core/module_definition.dart';
import 'communication_screen.dart';
import 'dashboard_screen.dart';
import 'documents_screen.dart';
import 'emergency_screen.dart';
import 'events_screen.dart';
import 'fees_screen.dart';
import 'inventory_screen.dart';
import 'lottery_screen.dart';
import 'members_screen.dart';
import 'treasury_screen.dart';

class ModuleRouter extends StatelessWidget {
  const ModuleRouter({super.key, required this.module});

  final ModuleDefinition module;

  @override
  Widget build(BuildContext context) {
    return switch (module.code) {
      'dashboard' => const DashboardScreen(),
      'members' => const MembersScreen(),
      'treasury' => const TreasuryScreen(),
      'fees' => const FeesScreen(),
      'lottery' => const LotteryScreen(),
      'events' => const EventsScreen(),
      'inventory' => const InventoryScreen(),
      'documents' => const DocumentsScreen(),
      'communication' => const CommunicationScreen(),
      'reports' => const _ReportsScreen(),
      'settings' => const _SettingsScreen(),
      'emergency' => const EmergencyScreen(),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ReportsScreen extends StatelessWidget {
  const _ReportsScreen();

  @override
  Widget build(BuildContext context) {
    const reports = [
      ('Membros', 'Listas, cargos, motas, patches e participação.'),
      ('Quotas', 'Mapa mensal, anual, dívida, créditos e comprovativos.'),
      ('Tesouraria', 'Contas, movimentos, centros de custo e resultados.'),
      ('Euromilhões', 'Participantes, chaves, sorteios, acertos e saldo.'),
      ('Eventos', 'Participantes, orçamento, stock e relatório final.'),
      ('Inventário', 'Stock, vendas, reservas, validades e margens.'),
      ('Documentos', 'Validades, privacidade, categorias e arquivo.'),
      ('Comunicação', 'Comunicados, audiências e confirmações de leitura.'),
      ('Livro Anual', 'Cápsula do Tempo do Blue On Black.'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Relatórios e importação',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...reports.map(
          (report) => Card(
            child: ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: Text(report.$1),
              subtitle: Text(report.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${report.$1}: relatório preparado na RC1.')),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    const settings = [
      ('Identidade do clube', 'Blue On Black, logótipo, cores e Club House.'),
      ('Cargos', 'Cargo principal, cargos adicionais e hierarquia.'),
      ('Perfis e permissões', 'Alteráveis apenas pela direção autorizada.'),
      ('Contas', 'Caixa, Banco CGD, Quotas, Reserva, Representação, Marketing, Euromilhões e Club House.'),
      ('Centros de custo', 'Club House, Representação, Eventos e restantes centros.'),
      ('Quotas', '25 € mensais e inscrição manual de Prospect.'),
      ('Inventário', 'Artigos, stock mínimo, reservas, vendas e Club House.'),
      ('Documentos', 'Categorias, privacidade, validade e arquivo digital.'),
      ('Comunicação', 'Audiências, prioridades e confirmação de leitura.'),
      ('Auditoria e backups', 'Histórico, exportação integral e recuperação.'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Configurações', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...settings.map(
          (setting) => Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(setting.$1),
              subtitle: Text(setting.$2),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
        ),
      ],
    );
  }
}
