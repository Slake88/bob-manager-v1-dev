import 'package:flutter/material.dart';

import '../core/permissions.dart';
import '../repositories/permissions_admin_repository.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final PermissionsAdminRepository _repository = PermissionsAdminRepository();
  late Future<_PermissionsData> _future;
  String _role = 'prospect';
  String? _selectedProfile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = Future.wait([
      _repository.roleMatrix(),
      _repository.users(),
    ]).then(
      (values) => _PermissionsData(
        matrix: values[0] as Map<String, Map<String, bool>>,
        users: List<Map<String, dynamic>>.from(values[1] as List),
      ),
    );
  }

  Future<void> _setRolePermission(
    AppPermission permission,
    bool value,
  ) async {
    try {
      await _repository.setRolePermission(
        roleKey: _role,
        permission: permission,
        allowed: value,
      );
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _openUser(Map<String, dynamic> user) async {
    final profileId = user['profile_id'].toString();
    setState(() => _selectedProfile = profileId);
    try {
      final overrides = await _repository.userOverrides(profileId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _UserPermissionDialog(
          repository: _repository,
          user: user,
          initialOverrides: overrides,
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _selectedProfile = null;
          _reload();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissões')),
      body: FutureBuilder<_PermissionsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!;
          final roleValues = data.matrix[_role] ?? const <String, bool>{};
          final grouped = <String, List<AppPermission>>{};
          for (final permission in AppPermission.values) {
            grouped.putIfAbsent(permission.module, () => []).add(permission);
          }

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                const Material(
                  child: TabBar(
                    tabs: [
                      Tab(text: 'Por cargo', icon: Icon(Icons.badge_outlined)),
                      Tab(
                        text: 'Por utilizador',
                        icon: Icon(Icons.person_outline),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Card(
                            child: ListTile(
                              leading: Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                              title: Text('Super Admin'),
                              subtitle: Text(
                                'Tem sempre acesso total. As suas permissões não podem ser removidas.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _role,
                            decoration: const InputDecoration(
                              labelText: 'Cargo / perfil',
                            ),
                            items: _roles
                                .map(
                                  (role) => DropdownMenuItem(
                                    value: role.key,
                                    child: Text(role.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _role = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          const Card(
                            child: ListTile(
                              leading: Icon(Icons.sync_outlined),
                              title: Text('Aplicação das alterações'),
                              subtitle: Text(
                                'Os utilizadores recebem a nova matriz ao iniciar sessão ou ao carregar em Atualizar permissões.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final entry in grouped.entries)
                            Card(
                              child: ExpansionTile(
                                initiallyExpanded:
                                    entry.key == 'Tesouraria' ||
                                    entry.key == 'Eventos',
                                title: Text(entry.key),
                                subtitle: Text(
                                  '${entry.value.where((p) => roleValues[p.key] == true).length} de ${entry.value.length} permissões ativas',
                                ),
                                children: [
                                  for (final permission in entry.value)
                                    SwitchListTile.adaptive(
                                      title: Text(permission.label),
                                      value:
                                          roleValues[permission.key] == true,
                                      onChanged: (value) =>
                                          _setRolePermission(
                                        permission,
                                        value,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          const Card(
                            child: ListTile(
                              leading: Icon(Icons.info_outline),
                              title: Text('Exceções individuais'),
                              subtitle: Text(
                                'Uma exceção pode permitir ou bloquear uma ação apenas para esse utilizador, sem alterar o cargo inteiro.',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (data.users.isEmpty)
                            const Card(
                              child: ListTile(
                                title: Text('Sem utilizadores ativos.'),
                              ),
                            )
                          else
                            for (final user in data.users)
                              Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(
                                    user['full_name']?.toString() ??
                                        'Utilizador',
                                  ),
                                  subtitle: Text(
                                    _roleLabel(
                                      user['access_role']?.toString() ??
                                          'member',
                                    ),
                                  ),
                                  trailing: _selectedProfile ==
                                          user['profile_id']?.toString()
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : user['access_role']?.toString() ==
                                              'super_admin'
                                          ? const Icon(Icons.lock_outline)
                                          : const Icon(Icons.chevron_right),
                                  onTap: user['access_role']?.toString() ==
                                          'super_admin'
                                      ? null
                                      : () => _openUser(user),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _UserPermissionDialog extends StatefulWidget {
  const _UserPermissionDialog({
    required this.repository,
    required this.user,
    required this.initialOverrides,
  });

  final PermissionsAdminRepository repository;
  final Map<String, dynamic> user;
  final Map<String, bool> initialOverrides;

  @override
  State<_UserPermissionDialog> createState() =>
      _UserPermissionDialogState();
}

class _UserPermissionDialogState extends State<_UserPermissionDialog> {
  late Map<String, bool> _overrides;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _overrides = Map<String, bool>.from(widget.initialOverrides);
  }

  Future<void> _set(AppPermission permission, bool? value) async {
    setState(() => _saving = true);
    try {
      await widget.repository.setUserOverride(
        profileId: widget.user['profile_id'].toString(),
        permission: permission,
        allowed: value,
      );
      if (!mounted) return;
      setState(() {
        if (value == null) {
          _overrides.remove(permission.key);
        } else {
          _overrides[permission.key] = value;
        }
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogHeight = (screenSize.height * 0.72).clamp(360.0, 620.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(widget.user['full_name']?.toString() ?? 'Utilizador'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: SizedBox(
          width: screenSize.width,
          height: dialogHeight,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Cargo base: ${_roleLabel(widget.user['access_role']?.toString() ?? 'member')}\n'
                  'Herdar = usa a configuração do cargo.',
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (final permission in AppPermission.values)
                      Card(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 430;
                            final selector = DropdownButton<bool?>(
                              value: _overrides.containsKey(permission.key)
                                  ? _overrides[permission.key]
                                  : null,
                              items: const [
                                DropdownMenuItem<bool?>(
                                  value: null,
                                  child: Text('Herdar'),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: true,
                                  child: Text('Permitir'),
                                ),
                                DropdownMenuItem<bool?>(
                                  value: false,
                                  child: Text('Bloquear'),
                                ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) => _set(permission, value),
                            );

                            if (narrow) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      permission.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    Text(
                                      permission.module,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    selector,
                                  ],
                                ),
                              );
                            }

                            return ListTile(
                              title: Text(permission.label),
                              subtitle: Text(permission.module),
                              trailing: selector,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
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
    );
  }
}

class _PermissionsData {
  const _PermissionsData({required this.matrix, required this.users});

  final Map<String, Map<String, bool>> matrix;
  final List<Map<String, dynamic>> users;
}

class _RoleOption {
  const _RoleOption(this.key, this.label);

  final String key;
  final String label;
}

const _roles = <_RoleOption>[
  _RoleOption('president', 'Presidente'),
  _RoleOption('vice_president', 'Vice-Presidente'),
  _RoleOption('admin', 'Administrador'),
  _RoleOption('treasurer', 'Tesoureiro'),
  _RoleOption('secretary', 'Secretário'),
  _RoleOption('road_captain', 'Road Captain'),
  _RoleOption('sergeant_at_arms', 'Sargento de Armas'),
  _RoleOption('inventory_manager', 'Responsável de Inventário'),
  _RoleOption('event_manager', 'Responsável de Eventos'),
  _RoleOption('euromillions_manager', 'Responsável Euromilhões'),
  _RoleOption('prospect', 'Prospect'),
  _RoleOption('member', 'Membro / Full Color'),
];

String _roleLabel(String key) {
  for (final role in _roles) {
    if (role.key == key) return role.label;
  }
  if (key == 'super_admin') return 'Super Admin';
  return key;
}
