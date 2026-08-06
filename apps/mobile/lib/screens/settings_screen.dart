import 'package:flutter/material.dart';

import '../repositories/admin_repository.dart';

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
            Row(
              children: [
                Expanded(child: Text('Administração', style: Theme.of(context).textTheme.headlineSmall)),
                OutlinedButton.icon(onPressed: _showAuditLog, icon: const Icon(Icons.history), label: const Text('Auditoria')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: () => _editSetting(), icon: const Icon(Icons.add), label: const Text('Nova configuração')),
              ],
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.security_outlined),
                title: Text('Perfis e permissões'),
                subtitle: Text('Direção, Tesouraria, Secretaria, Eventos, Inventário e restantes cargos.'),
              ),
            ),
            const Card(
              child: ListTile(
                leading: Icon(Icons.account_balance_outlined),
                title: Text('Contas e centros de custo'),
                subtitle: Text('Caixa, Banco CGD, Quotas, Reserva, Representação, Marketing, Euromilhões e Club House.'),
              ),
            ),
            const SizedBox(height: 8),
            Text('Parâmetros do clube', style: Theme.of(context).textTheme.titleLarge),
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
