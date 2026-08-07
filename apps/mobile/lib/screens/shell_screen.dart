import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/module_definition.dart';
import '../core/permissions.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'module_router.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int selected = 0;

  List<ModuleDefinition> get _visibleModules {
    return appModules.where(_canViewModule).toList();
  }

  bool _canViewModule(ModuleDefinition module) {
    final session = AppSession.instance;
    return switch (module.code) {
      'dashboard' => session.authenticated,
      'members' => session.can(AppPermission.viewMembers),
      'treasury' => session.can(AppPermission.viewTreasury),
      'fees' => session.can(AppPermission.viewFees),
      'lottery' => session.can(AppPermission.viewLottery),
      'events' => session.can(AppPermission.viewEvents),
      'inventory' => session.can(AppPermission.viewInventory),
      'documents' => session.can(AppPermission.viewDocuments),
      'communication' => session.can(AppPermission.viewCommunication),
      'reports' => session.can(AppPermission.viewFinancialReports),
      'settings' => session.can(AppPermission.manageSettings),
      'emergency' => session.can(AppPermission.viewEmergencyData),
      _ => false,
    };
  }

  Future<void> _refreshPermissions() async {
    await AuthService.instance.refreshPermissions();
    if (!mounted) return;
    setState(() {
      final modules = _visibleModules;
      if (selected >= modules.length) selected = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final modules = _visibleModules;
    if (modules.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Não existem módulos disponíveis.')),
      );
    }

    if (selected >= modules.length) selected = 0;
    final module = modules[selected];
    final session = AppSession.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(module.title),
        actions: [
          IconButton(
            tooltip: 'Atualizar permissões',
            onPressed: _refreshPermissions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: NavigationDrawer(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          setState(() => selected = index);
          Navigator.pop(context);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BLUE ON BLACK',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  session.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(session.role, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(),
          ...modules.map(
            (item) => NavigationDrawerDestination(
              icon: Icon(item.icon),
              label: Text(item.title),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Terminar sessão'),
            onTap: () async {
              await AuthService.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (_) => false,
              );
            },
          ),
        ],
      ),
      body: ModuleRouter(module: module),
    );
  }
}
