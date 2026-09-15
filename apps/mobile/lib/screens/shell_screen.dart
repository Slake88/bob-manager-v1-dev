import 'dart:async';

import 'package:flutter/material.dart';

import '../core/adaptive_layout.dart';
import '../core/app_navigation.dart';
import '../core/app_session.dart';
import '../core/club_export.dart';
import '../core/importing.dart';
import '../core/module_definition.dart';
import '../core/notification_center.dart';
import '../core/permissions.dart';
import '../core/reporting.dart';
import '../repositories/activity_repository.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import 'activity_screen.dart';
import 'global_search_screen.dart';
import 'login_screen.dart';
import 'module_router.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

enum _ShellAction { refreshPermissions, logout }

class _ShellScreenState extends State<ShellScreen> {
  String _selectedCode = 'dashboard';
  final ActivityRepository _activity = ActivityRepository();
  late Future<int> _unreadFuture;
  Timer? _badgeTimer;
  StreamSubscription<PushMessageEvent>? _foregroundPushSubscription;
  StreamSubscription<String>? _openedPushSubscription;

  @override
  void initState() {
    super.initState();
    _unreadFuture = _activity.unreadCount();
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshUnread(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _configurePush());
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _foregroundPushSubscription?.cancel();
    _openedPushSubscription?.cancel();
    super.dispose();
  }

  List<ModuleDefinition> get _visibleModules {
    return appModules.where(_canViewModule).toList();
  }

  bool _canViewModule(ModuleDefinition module) {
    final session = AppSession.instance;
    return switch (module.code) {
      'dashboard' || 'activity' || 'financial' || 'weekly_officer' || 'agenda' =>
        session.authenticated,
      'members' => session.can(AppPermission.viewMembers),
      'treasury' => session.can(AppPermission.viewTreasury),
      'fees' => session.can(AppPermission.viewFees),
      'lottery' => session.can(AppPermission.viewLottery),
      'events' => session.can(AppPermission.viewEvents),
      'bar' => session.can(AppPermission.viewBar),
      'inventory' => session.can(AppPermission.viewInventory),
      'documents' => session.can(AppPermission.viewDocuments),
      'communication' => session.can(AppPermission.viewCommunication),
      'reports' =>
        ReportCatalog.canOpenCenter(session.can) ||
            ClubExportPolicy.canExport(session) ||
            ImportCatalog.canOpen(session),
      'settings' =>
        session.can(AppPermission.manageSettings) ||
        session.can(AppPermission.manageUserAccess),
      'emergency' => session.can(AppPermission.viewEmergencyData),
      _ => false,
    };
  }

  Future<void> _configurePush() async {
    await PushNotificationService.instance.initialize();
    if (!mounted) return;
    _foregroundPushSubscription ??=
        PushNotificationService.instance.foregroundMessages.listen((message) {
      _refreshUnread();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${message.title}\n${message.body}'),
          action: message.actionRoute == null
              ? null
              : SnackBarAction(
                  label: 'Abrir',
                  onPressed: () => _openActionRoute(message.actionRoute!),
                ),
        ),
      );
    });
    _openedPushSubscription ??=
        PushNotificationService.instance.openedRoutes.listen(_openActionRoute);
    final initialRoute =
        PushNotificationService.instance.takeInitialActionRoute();
    if (initialRoute != null) await _openActionRoute(initialRoute);
  }

  void _refreshUnread() {
    if (!mounted) return;
    setState(() => _unreadFuture = _activity.unreadCount());
  }

  Future<void> _refreshPermissions() async {
    await AuthService.instance.refreshPermissions();
    if (!mounted) return;
    setState(() {
      _unreadFuture = _activity.unreadCount();
      final modules = _visibleModules;
      if (modules.isNotEmpty) {
        _selectedCode =
            AppNavigationPolicy.resolveSelected(modules, _selectedCode).code;
      }
    });
  }

  Future<void> _signOut() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openNotifications() async {
    final route = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
    );
    if (!mounted) return;
    _refreshUnread();
    if (route != null) await _openActionRoute(route);
  }

  Future<void> _openGlobalSearch() async {
    final moduleCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
    );
    if (!mounted || moduleCode == null) return;
    _selectModuleCode(moduleCode);
  }

  Future<void> _openActionRoute(String route) async {
    final code = notificationModuleFromRoute(route);
    if (code == null || !mounted) return;
    _selectModuleCode(code);
  }

  void _selectModuleCode(String code) {
    if (!mounted) return;
    final modules = _visibleModules;
    if (!modules.any((module) => module.code == code)) return;
    setState(() => _selectedCode = code);
  }

  Future<void> _openMoreModules(
    List<ModuleDefinition> modules,
    String selectedCode,
  ) async {
    final session = AppSession.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.86,
        child: _MoreModulesSheet(
          modules: modules,
          selectedCode: selectedCode,
          fullName: session.fullName,
          role: session.role,
          onSelect: (code) {
            Navigator.pop(sheetContext);
            _selectModuleCode(code);
          },
          onRefresh: () async {
            Navigator.pop(sheetContext);
            await _refreshPermissions();
          },
          onLogout: () async {
            Navigator.pop(sheetContext);
            await _signOut();
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(String title) {
    return AppBar(
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Pesquisa Global',
          onPressed: _openGlobalSearch,
          icon: const Icon(Icons.search),
        ),
        FutureBuilder<int>(
          future: _unreadFuture,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return IconButton(
              tooltip: count > 0 ? '$count notificações por ler' : 'Notificações',
              onPressed: _openNotifications,
              icon: Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: const Icon(Icons.notifications_none_outlined),
              ),
            );
          },
        ),
        PopupMenuButton<_ShellAction>(
          tooltip: 'Mais ações',
          onSelected: (action) async {
            switch (action) {
              case _ShellAction.refreshPermissions:
                await _refreshPermissions();
                return;
              case _ShellAction.logout:
                await _signOut();
                return;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _ShellAction.refreshPermissions,
              child: Row(
                children: [
                  Icon(Icons.refresh),
                  SizedBox(width: 12),
                  Text('Atualizar permissões'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _ShellAction.logout,
              child: Row(
                children: [
                  Icon(Icons.logout),
                  SizedBox(width: 12),
                  Text('Terminar sessão'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _navigationPanel({
    required List<ModuleDefinition> modules,
    required String selectedCode,
    required bool closeOnSelect,
  }) {
    final session = AppSession.instance;
    final selectedIndex =
        modules.indexWhere((module) => module.code == selectedCode);
    return NavigationDrawer(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) {
        if (index < 0 || index >= modules.length) return;
        if (closeOnSelect) Navigator.pop(context);
        _selectModuleCode(modules[index].code);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: const Icon(Icons.shield_outlined),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'BOB MANAGER',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                session.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                session.role,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
          leading: const Icon(Icons.refresh),
          title: const Text('Atualizar permissões'),
          onTap: () async {
            if (closeOnSelect) Navigator.pop(context);
            await _refreshPermissions();
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Terminar sessão'),
          onTap: _signOut,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  NavigationBar _compactNavigation(
    AppNavigationPlan plan,
    String selectedCode,
  ) {
    final selectedIndex = plan.compactSelectedIndex(selectedCode);
    return NavigationBar(
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        if (index < plan.primary.length) {
          _selectModuleCode(plan.primary[index].code);
          return;
        }
        _openMoreModules(plan.secondary, selectedCode);
      },
      destinations: [
        ...plan.primary.map(
          (module) => NavigationDestination(
            icon: Icon(module.icon),
            selectedIcon: Icon(module.icon),
            label: module.title,
          ),
        ),
        const NavigationDestination(
          icon: Icon(Icons.apps_outlined),
          selectedIcon: Icon(Icons.apps),
          label: 'Mais',
        ),
      ],
    );
  }

  Widget _mediumNavigation(
    AppNavigationPlan plan,
    String selectedCode,
  ) {
    final selectedIndex = plan.compactSelectedIndex(selectedCode);
    return NavigationRail(
      selectedIndex: selectedIndex,
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.85,
      onDestinationSelected: (index) {
        if (index < plan.primary.length) {
          _selectModuleCode(plan.primary[index].code);
          return;
        }
        _openMoreModules(plan.secondary, selectedCode);
      },
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.shield_outlined),
        ),
      ),
      destinations: [
        ...plan.primary.map(
          (module) => NavigationRailDestination(
            icon: Icon(module.icon),
            selectedIcon: Icon(module.icon),
            label: Text(module.title),
          ),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.apps_outlined),
          selectedIcon: Icon(Icons.apps),
          label: Text('Mais'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final modules = _visibleModules;
    if (modules.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Não existem módulos disponíveis.')),
      );
    }

    final current = AppNavigationPolicy.resolveSelected(modules, _selectedCode);
    _selectedCode = current.code;
    final plan = AppNavigationPolicy.plan(modules);
    final layout = AppBreakpoints.of(context);
    final content = ModuleRouter(module: current);

    if (layout == AppLayoutSize.compact) {
      return Scaffold(
        appBar: _buildAppBar(current.title),
        drawer: _navigationPanel(
          modules: modules,
          selectedCode: current.code,
          closeOnSelect: true,
        ),
        body: content,
        bottomNavigationBar: _compactNavigation(plan, current.code),
      );
    }

    if (layout == AppLayoutSize.medium) {
      return Scaffold(
        appBar: _buildAppBar(current.title),
        body: Row(
          children: [
            _mediumNavigation(plan, current.code),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(current.title),
      body: Row(
        children: [
          SizedBox(
            width: 292,
            child: _navigationPanel(
              modules: modules,
              selectedCode: current.code,
              closeOnSelect: false,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _MoreModulesSheet extends StatelessWidget {
  const _MoreModulesSheet({
    required this.modules,
    required this.selectedCode,
    required this.fullName,
    required this.role,
    required this.onSelect,
    required this.onRefresh,
    required this.onLogout,
  });

  final List<ModuleDefinition> modules;
  final String selectedCode;
  final String fullName;
  final String role;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: const Icon(Icons.shield_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Mais áreas',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Acesso às restantes funcionalidades disponíveis para o teu perfil.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: modules.isEmpty
                ? const Center(
                    child: Text(
                      'Todas as áreas disponíveis já estão na navegação principal.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 2 : 1;
                      return GridView.builder(
                        itemCount: modules.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 92,
                        ),
                        itemBuilder: (context, index) {
                          final module = modules[index];
                          final selected = module.code == selectedCode;
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => onSelect(module.code),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      child: Icon(module.icon),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            module.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            module.description,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(Icons.check_circle),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(Icons.chevron_right),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar permissões'),
              ),
              TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Terminar sessão'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
