import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../repositories/admin_repository.dart';
import 'permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AdminRepository _repository = AdminRepository();
  late Future<List<Map<String, dynamic>>> _settingsFuture;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _repository.listSettings();
  }

  void _reload() {
    setState(() => _settingsFuture = _repository.listSettings());
  }

  Future<void> _editSetting([Map<String, dynamic>? setting]) async {
    final keyController = TextEditingController(text: setting?['key']?.toString() ?? '');
    final valueController = TextEditingController(text: setting?['value']?.toString() ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(setting == null ? 'Nova configuração' : 'Editar configuração'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: keyController, decoration: const InputDecoration(labelText: 'Chave')),
            TextField(controller: valueController, decoration: const InputDecoration(labelText: 'Valor')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
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

  Future<void> _showAuditLog() async {
    final rows = await _repository.listAuditLog();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Auditoria'),
        content: SizedBox(
          width: 620,
          child: rows.isEmpty
              ? const Text('Ainda não existem registos de auditoria.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(row['description']?.toString() ?? row['action']?.toString() ?? 'Alteração'),
                      subtitle: Text(row['created_at']?.toString() ?? ''),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }

  Future<void> _openPermissions() async {
    if (!AppSession.instance.superAdmin) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PermissionsScreen()),
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
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text('Administração', style: Theme.of(context).textTheme.headlineSmall),
                OutlinedButton.icon(onPressed: _showAuditLog, icon: const Icon(Icons.history), label: const Text('Auditoria')),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Perfis e permissões'),
                subtitle: Text(
                  AppSession.instance.superAdmin
                      ? 'Definir o que cada cargo e utilizador pode ver e fazer.'
                      : 'A gestão da matriz de permissões é exclusiva do Super Admin.',
                ),
                trailing: AppSession.instance.superAdmin ? const Icon(Icons.chevron_right) : const Icon(Icons.lock_outline),
                onTap: AppSession.instance.superAdmin ? _openPermissions : null,
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('Contas e centros de custo'),
                subtitle: Text('A gestão operacional das contas é feita diretamente na Tesouraria.'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Parâmetros do clube', style: Theme.of(context).textTheme.titleLarge)),
                FilledButton.icon(onPressed: () => _editSetting(), icon: const Icon(Icons.add), label: const Text('Novo')),
              ],
            ),
            const SizedBox(height: 8),
            if (settings.isEmpty)
              const Card(child: ListTile(title: Text('Sem parâmetros personalizados'), subtitle: Text('Os valores padrão da RC1 estão ativos.')))
            else
              ...settings.map(
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
        );
      },
    );
  }
}
