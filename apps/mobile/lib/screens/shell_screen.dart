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
      'treasury' => session.can(AppPermission.viewTreasury),
      'settings' => session.can(AppPermission.manageSettings),
      'reports' => session.can(AppPermission.viewFinancialReports),
      _ => session.authenticated,
    };
  }

  @override
  Widget build(BuildContext context) {
    final modules = _visibleModules;
    if (modules.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Não existem módulos disponíveis.')),
      );
    }

    if (selected >= modules.length) {
      selected = 0;
    }
    final module = modules[selected];
    final session = AppSession.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(module.title),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => setState(() {}),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  session.role,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
