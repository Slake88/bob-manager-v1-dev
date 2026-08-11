import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../repositories/activity_repository.dart';
import '../services/push_notification_service.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final ActivityRepository _repository = ActivityRepository();
  bool _loading = true;
  bool _devicePushEnabled = false;
  Map<String, Map<String, bool>> _preferences = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await _repository.notificationPreferences();
      final deviceEnabled =
          await PushNotificationService.instance.isPermissionGranted();
      if (!mounted) return;
      setState(() {
        _preferences = values;
        _devicePushEnabled = deviceEnabled;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, bool> _value(String module) =>
      _preferences[module] ?? const {'in_app': true, 'push': true};

  Future<void> _save(
    String module, {
    bool? inApp,
    bool? push,
  }) async {
    final current = _value(module);
    final nextInApp = inApp ?? current['in_app'] ?? true;
    final nextPush = nextInApp ? (push ?? current['push'] ?? true) : false;
    setState(() {
      _preferences = {
        ..._preferences,
        module: {'in_app': nextInApp, 'push': nextPush},
      };
    });
    try {
      await _repository.setNotificationPreference(
        moduleCode: module,
        inAppEnabled: nextInApp,
        pushEnabled: nextPush,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível guardar: $error')),
      );
      await _load();
    }
  }

  Future<void> _enableDevicePush() async {
    final enabled =
        await PushNotificationService.instance.requestPermissionAndRegister();
    if (!mounted) return;
    setState(() => _devicePushEnabled = enabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Notificações push ativadas neste dispositivo.'
              : 'Não foi possível ativar push. Confirma a configuração Firebase e a permissão do sistema.',
        ),
      ),
    );
  }

  Future<void> _disableDevicePush() async {
    await PushNotificationService.instance.disableCurrentDevice();
    if (mounted) setState(() => _devicePushEnabled = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preferências de notificações')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Push neste dispositivo',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (!AppConfig.hasFirebaseConfiguration)
                          const Text(
                            'A caixa de notificações está ativa. O push fica disponível depois de configurar Firebase/FCM para esta instalação.',
                          )
                        else
                          Text(
                            _devicePushEnabled
                                ? 'Este dispositivo está autorizado a receber push.'
                                : 'Ativa a permissão do sistema e regista este dispositivo.',
                          ),
                        const SizedBox(height: 12),
                        if (AppConfig.hasFirebaseConfiguration)
                          FilledButton.icon(
                            onPressed: _devicePushEnabled
                                ? _disableDevicePush
                                : _enableDevicePush,
                            icon: Icon(
                              _devicePushEnabled
                                  ? Icons.notifications_off_outlined
                                  : Icons.notifications_active_outlined,
                            ),
                            label: Text(
                              _devicePushEnabled
                                  ? 'Desativar neste dispositivo'
                                  : 'Ativar push neste dispositivo',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Por módulo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                const Text(
                  'A caixa interna é persistente. Podes escolher em que áreas queres também receber alertas push.',
                ),
                const SizedBox(height: 10),
                for (final item in _modules)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(item.$3),
                          title: Text(item.$2),
                          subtitle: Text(
                            (_value(item.$1)['in_app'] ?? true)
                                ? 'Visível na caixa de notificações'
                                : 'Notificações deste módulo desativadas',
                          ),
                        ),
                        SwitchListTile(
                          title: const Text('Na aplicação'),
                          value: _value(item.$1)['in_app'] ?? true,
                          onChanged: (value) => _save(item.$1, inApp: value),
                        ),
                        SwitchListTile(
                          title: const Text('Push'),
                          value: (_value(item.$1)['in_app'] ?? true) &&
                              (_value(item.$1)['push'] ?? true),
                          onChanged: (_value(item.$1)['in_app'] ?? true)
                              ? (value) => _save(item.$1, push: value)
                              : null,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

const _modules = <(String, String, IconData)>[
  ('general', 'Geral', Icons.notifications_none_outlined),
  ('members', 'Membros', Icons.groups_outlined),
  ('treasury', 'Tesouraria e Pagamentos', Icons.account_balance_wallet_outlined),
  ('fees', 'Quotas', Icons.receipt_long_outlined),
  ('lottery', 'Euromilhões', Icons.casino_outlined),
  ('events', 'Eventos', Icons.event_outlined),
  ('inventory', 'Património, Inventário e Bar', Icons.inventory_2_outlined),
  ('documents', 'Documentos', Icons.folder_outlined),
  ('communication', 'Comunicação', Icons.campaign_outlined),
  ('emergency', 'Emergência', Icons.emergency_outlined),
  ('settings', 'Administração', Icons.admin_panel_settings_outlined),
];
