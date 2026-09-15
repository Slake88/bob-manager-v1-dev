import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../repositories/admin_repository.dart';
import 'permissions_screen.dart';
import 'user_access_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AdminRepository _repository = AdminRepository();
  late Future<List<Map<String, dynamic>>> _settingsFuture;

  bool get _canManageSettings =>
      AppSession.instance.can(AppPermission.manageSettings);

  bool get _canManageAccess =>
      AppSession.instance.can(AppPermission.manageUserAccess);

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  Future<List<Map<String, dynamic>>> _loadSettings() {
    if (!_canManageSettings) {
      return Future.value(<Map<String, dynamic>>[]);
    }
    return _repository.listSettings();
  }

  void _reload() {
    setState(() {
      _settingsFuture = _loadSettings();
    });
  }

  Future<void> _editSetting([Map<String, dynamic>? setting]) async {
    if (!_canManageSettings) return;
    final keyController =
        TextEditingController(text: setting?['key']?.toString() ?? '');
    final valueController =
        TextEditingController(text: setting?['value']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          setting == null ? 'Nova configuração' : 'Editar configuração',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: keyController,
              decoration: const InputDecoration(labelText: 'Chave'),
            ),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(labelText: 'Valor'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (keyController.text.trim().isEmpty) return;
              await _repository.saveSetting(
                key: keyController.text,
                value: valueController.text,
                settingId: setting?['id']?.toString(),
              );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    keyController.dispose();
    valueController.dispose();
    if (saved == true) _reload();
  }

  Future<void> _editDinnerFee(List<Map<String, dynamic>> settings) async {
    if (!_canManageSettings) return;
    final setting = _findSetting(settings, 'dinner_fee_amount');
    final current = _settingAmount(setting?['value']);
    final controller = TextEditingController(
      text: current == null
          ? ''
          : current.toStringAsFixed(2).replaceAll('.', ','),
    );

    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Valor do jantar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Dinner fee amount (€)',
            helperText: 'Valor fixo usado automaticamente nas vendas do BAR.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;

    final amount = _settingAmount(value);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('O valor do jantar tem de ser superior a zero.'),
          ),
        );
      }
      return;
    }

    try {
      await _repository.saveSetting(
        key: 'dinner_fee_amount',
        value: amount.toStringAsFixed(2),
        settingId: setting?['id']?.toString(),
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Valor do jantar atualizado para ${_settingMoney(amount)}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _showAuditLog() async {
    if (!_canManageSettings) return;
    final rows = await _repository.listAuditLog();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auditoria'),
        content: SizedBox(
          width: 760,
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: rows.isEmpty
              ? const Center(
                  child: Text('Ainda não existem registos de auditoria.'),
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final actor = _auditActor(row);
                    final moment = _auditMoment(row['created_at']);
                    final entity = _auditEntity(row['entity_type']);
                    final action = _auditAction(row['action']);
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.history_outlined),
                      ),
                      title: Text('$action · $entity'),
                      subtitle: Text('$actor\n$moment'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _showAuditDetail(row),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAuditDetail(Map<String, dynamic> row) async {
    if (!mounted) return;
    final actor = _auditActor(row);
    final moment = _auditMoment(row['created_at']);
    final entity = _auditEntity(row['entity_type']);
    final action = _auditAction(row['action']);
    final entityId = row['entity_id']?.toString();
    final before = _auditJson(row['before_data']);
    final after = _auditJson(row['after_data']);

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action · $entity'),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Utilizador'),
                  subtitle: Text(actor),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: const Text('Data e hora'),
                  subtitle: Text(moment),
                ),
                if (entityId != null && entityId.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.tag_outlined),
                    title: const Text('ID do registo'),
                    subtitle: SelectableText(entityId),
                  ),
                if (before != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Antes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(before),
                ],
                if (after != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Depois',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(after),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _openPermissions() async {
    if (!AppSession.instance.superAdmin) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PermissionsScreen()),
    );
  }

  Future<void> _openUserAccess() async {
    if (!_canManageAccess) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const UserAccessScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _settingsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final settings = snapshot.data!;
        final dinnerSetting = _findSetting(settings, 'dinner_fee_amount');
        final dinnerAmount = _settingAmount(dinnerSetting?['value']);
        final customSettings = settings
            .where(
              (setting) => setting['key']?.toString() != 'dinner_fee_amount',
            )
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  'Administração',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (_canManageSettings)
                  OutlinedButton.icon(
                    onPressed: _showAuditLog,
                    icon: const Icon(Icons.history),
                    label: const Text('Auditoria'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Contas e acessos'),
                subtitle: Text(
                  _canManageAccess
                      ? 'Convidar, ativar, repor palavra-passe, alterar perfil e bloquear utilizadores.'
                      : 'Sem permissão para gerir o ciclo de acesso dos utilizadores.',
                ),
                trailing: _canManageAccess
                    ? const Icon(Icons.chevron_right)
                    : const Icon(Icons.lock_outline),
                onTap: _canManageAccess ? _openUserAccess : null,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Perfis e permissões'),
                subtitle: Text(
                  AppSession.instance.superAdmin
                      ? 'Definir o que cada cargo e utilizador pode ver e fazer.'
                      : 'A gestão da matriz de permissões é exclusiva do Super Admin.',
                ),
                trailing: AppSession.instance.superAdmin
                    ? const Icon(Icons.chevron_right)
                    : const Icon(Icons.lock_outline),
                onTap: AppSession.instance.superAdmin ? _openPermissions : null,
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('Contas e centros de custo'),
                subtitle: Text(
                  'A gestão operacional das contas é feita diretamente na Tesouraria.',
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dinner_dining_outlined),
                title: const Text('Valor do jantar'),
                subtitle: Text(
                  dinnerAmount == null || dinnerAmount <= 0
                      ? 'Ainda não definido. É usado automaticamente nas vendas do BAR.'
                      : '${_settingMoney(dinnerAmount)} · usado automaticamente nas vendas do BAR.',
                ),
                trailing: _canManageSettings
                    ? const Icon(Icons.edit_outlined)
                    : const Icon(Icons.lock_outline),
                onTap: _canManageSettings
                    ? () => _editDinnerFee(settings)
                    : null,
              ),
            ),
            if (_canManageSettings) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Parâmetros do clube',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _editSetting(),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (customSettings.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text('Sem parâmetros personalizados'),
                    subtitle: Text('Os valores padrão da RC1 estão ativos.'),
                  ),
                )
              else
                ...customSettings.map(
                  (setting) => Card(
                    child: ListTile(
                      title: Text(setting['key']?.toString() ?? ''),
                      subtitle: Text(setting['value']?.toString() ?? ''),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editSetting(setting),
                    ),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

Map<String, dynamic>? _findSetting(
  List<Map<String, dynamic>> settings,
  String key,
) {
  for (final setting in settings) {
    if (setting['key']?.toString() == key) return setting;
  }
  return null;
}

double? _settingAmount(Object? value) {
  final text = value?.toString().trim().replaceAll(',', '.') ?? '';
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

String _settingMoney(double value) =>
    '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

String _auditActor(Map<String, dynamic> row) {
  final actor = row['actor'];
  if (actor is Map) {
    final name = actor['full_name']?.toString().trim() ?? '';
    final email = actor['email']?.toString().trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return '$name · $email';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
  }
  final actorId = row['actor_id']?.toString().trim() ?? '';
  if (actorId.isEmpty) return 'Sistema / automatismo';
  return 'Utilizador $actorId';
}

String _auditMoment(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return value?.toString() ?? 'Data desconhecida';
  return DateFormat('dd/MM/yyyy HH:mm:ss').format(parsed);
}

String _auditAction(Object? value) {
  return switch (value?.toString()) {
    'created' => 'Criado',
    'updated' => 'Alterado',
    'deleted' => 'Eliminado',
    'insert' => 'Criado',
    'update' => 'Alterado',
    'upsert' => 'Criado/alterado',
    final String text when text.isNotEmpty => text,
    _ => 'Alteração',
  };
}

String _auditEntity(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return 'Registo';
  final normalized = text.replaceAll('_', ' ');
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

String? _auditJson(Object? value) {
  if (value == null) return null;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
