import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/module_definition.dart';
import '../core/notification_center.dart';
import '../core/permissions.dart';
import '../core/reporting.dart';
import '../repositories/activity_repository.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import 'activity_screen.dart';
import 'login_screen.dart';
import 'module_router.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int selected = 0;
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
      'inventory' => session.can(AppPermission.viewInventory),
      'documents' => session.can(AppPermission.viewDocuments),
      'communication' => session.can(AppPermission.viewCommunication),
      'reports' => ReportCatalog.canOpenCenter(session.can),
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
      if (selected >= modules.length) selected = 0;
    });
  }

  Future<void> _openNotifications() async {
    final route = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
    );
    if (!mounted) return;
    _refreshUnread();
    if (route != null) await _openActionRoute(route);
  }

  Future<void> _openActionRoute(String route) async {
    final code = notificationModuleFromRoute(route);
    if (code == null || !mounted) return;
    final modules = _visibleModules;
    final index = modules.indexWhere((module) => module.code == code);
    if (index < 0) return;
    setState(() => selected = index);
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
