import 'package:flutter/material.dart';

import '../repositories/user_access_repository.dart';

class UserAccessScreen extends StatefulWidget {
  const UserAccessScreen({super.key});

  @override
  State<UserAccessScreen> createState() => _UserAccessScreenState();
}

class _UserAccessScreenState extends State<UserAccessScreen> {
  final UserAccessRepository _repository = UserAccessRepository();
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'all';
  String? _busyProfile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _repository.accounts();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _invite(Map<String, dynamic> account) async {
    final emailController = TextEditingController(
      text: account['email']?.toString() ?? '',
    );
    var role = 'member';
    final result = await showDialog<_InviteData>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Dar acesso a ${account['full_name'] ?? 'membro'}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email de acesso'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Perfil de acesso'),
                  items: userAccessRoles
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.key,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => role = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final email = emailController.text.trim();
                if (!email.contains('@')) return;
                Navigator.pop(
                  dialogContext,
                  _InviteData(email: email, role: role),
                );
              },
              icon: const Icon(Icons.send_outlined),
              label: const Text('Enviar convite'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (result == null) return;

    final memberId = account['member_id']?.toString();
    if (memberId == null || memberId.isEmpty) return;
    await _run(
      account,
      () => _repository.invite(
        memberId: memberId,
        email: result.email,
        accessRole: result.role,
      ),
      'Convite enviado.',
    );
  }

  Future<void> _changeRole(Map<String, dynamic> account) async {
    var role = _canonicalRole(account['access_role']?.toString());
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Alterar perfil de acesso'),
          content: SizedBox(
            width: 480,
            child: DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Perfil'),
              items: userAccessRoles
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.key,
                      child: Text(item.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => role = value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, role),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await _run(
      account,
      () => _repository.changeRole(
        profileId: account['profile_id'].toString(),
        accessRole: selected,
      ),
      'Perfil de acesso atualizado.',
    );
  }

  Future<void> _confirmBlock(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bloquear acesso?'),
        content: Text(
          '${account['full_name'] ?? 'Este utilizador'} deixará de conseguir iniciar sessão no BOB Manager.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Bloquear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      account,
      () => _repository.block(account['profile_id'].toString()),
      'Acesso bloqueado.',
    );
  }

  Future<void> _confirmRemoveAccess(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover conta de acesso?'),
        content: Text(
          '${account['full_name'] ?? 'Este utilizador'} deixará de ter acesso ao BOB Manager. '
          'O email poderá voltar a ser usado num novo convite. O histórico de auditoria será preservado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover conta'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      account,
      () => _repository.removeAccess(account['profile_id'].toString()),
      'Conta de acesso removida.',
    );
  }

  Future<void> _run(
    Map<String, dynamic> account,
    Future<void> Function() action,
    String success,
  ) async {
    final profileId = account['profile_id']?.toString() ?? account['member_id']?.toString();
    setState(() => _busyProfile = profileId);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _busyProfile = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contas e acessos')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final all = snapshot.data!;
          final accounts = all.where((account) {
            if (_filter == 'all') return true;
            return account['access_state']?.toString() == _filter;
          }).toList();

          int count(String state) => all
              .where((row) => row['access_state']?.toString() == state)
              .length;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Text(
                  'Gestão do ciclo de acesso',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Convidar membros, reenviar convites, repor palavras-passe, alterar perfis, bloquear e remover contas de acesso.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: 'Todos (${all.length})',
                      selected: _filter == 'all',
                      onSelected: () => setState(() => _filter = 'all'),
                    ),
                    _FilterChip(
                      label: 'Sem acesso (${count('no_access')})',
                      selected: _filter == 'no_access',
                      onSelected: () => setState(() => _filter = 'no_access'),
                    ),
                    _FilterChip(
                      label: 'Convite enviado (${count('invited')})',
                      selected: _filter == 'invited',
                      onSelected: () => setState(() => _filter = 'invited'),
                    ),
                    _FilterChip(
                      label: 'Ativos (${count('active')})',
                      selected: _filter == 'active',
                      onSelected: () => setState(() => _filter = 'active'),
                    ),
                    _FilterChip(
                      label: 'Bloqueados (${count('blocked')})',
                      selected: _filter == 'blocked',
                      onSelected: () => setState(() => _filter = 'blocked'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (accounts.isEmpty)
                  const Card(
                    child: ListTile(title: Text('Sem contas neste estado.')),
                  )
                else
                  for (final account in accounts) _accountCard(account),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> account) {
    final state = account['access_state']?.toString() ?? 'no_access';
    final profileId = account['profile_id']?.toString() ?? '';
    final identity = profileId.isEmpty
        ? account['member_id']?.toString()
        : profileId;
    final busy = identity != null && identity == _busyProfile;
    final protected = account['protected'] == true;
    final self = account['self'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          leading: CircleAvatar(
            child: Text(_initial(account['full_name']?.toString())),
          ),
          title: Text(account['full_name']?.toString() ?? 'Utilizador'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((account['nickname']?.toString() ?? '').isNotEmpty)
                Text(account['nickname'].toString()),
              Text(account['email']?.toString() ?? 'Sem email definido'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(_stateIcon(state), size: 16),
                    label: Text(userAccessStateLabel(state)),
                  ),
                  if ((account['access_role']?.toString() ?? '').isNotEmpty)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(userAccessRoleLabel(account['access_role'].toString())),
                    ),
                  if (self)
                    const Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('A tua conta'),
                    ),
                ],
              ),
            ],
          ),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : _actions(account, state, protected, self),
        ),
      ),
    );
  }

  Widget _actions(
    Map<String, dynamic> account,
    String state,
    bool protected,
    bool self,
  ) {
    if (protected || self) return const Icon(Icons.lock_outline);
    if (state == 'no_access') {
      return FilledButton.tonalIcon(
        onPressed: account['member_id'] == null ? null : () => _invite(account),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Convidar'),
      );
    }

    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'resend') {
          await _run(
            account,
            () => _repository.resendInvite(account['profile_id'].toString()),
            'Convite reenviado.',
          );
        } else if (value == 'reset') {
          await _run(
            account,
            () => _repository.sendPasswordReset(account['profile_id'].toString()),
            'Email de reposição enviado.',
          );
        } else if (value == 'role') {
          await _changeRole(account);
        } else if (value == 'block') {
          await _confirmBlock(account);
        } else if (value == 'unblock') {
          await _run(
            account,
            () => _repository.unblock(account['profile_id'].toString()),
            'Acesso desbloqueado.',
          );
        } else if (value == 'remove') {
          await _confirmRemoveAccess(account);
        }
      },
      itemBuilder: (_) => [
        if (state == 'invited')
          const PopupMenuItem(
            value: 'resend',
            child: Text('Reenviar convite'),
          ),
        if (state == 'active')
          const PopupMenuItem(
            value: 'reset',
            child: Text('Enviar reposição de palavra-passe'),
          ),
        const PopupMenuItem(
          value: 'role',
          child: Text('Alterar perfil de acesso'),
        ),
        if (state != 'blocked')
          const PopupMenuItem(value: 'block', child: Text('Bloquear acesso')),
        if (state == 'blocked')
          const PopupMenuItem(
            value: 'unblock',
            child: Text('Desbloquear acesso'),
          ),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remover conta de acesso'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _InviteData {
  const _InviteData({required this.email, required this.role});
  final String email;
  final String role;
}

class UserAccessRoleOption {
  const UserAccessRoleOption(this.key, this.label);
  final String key;
  final String label;
}

const userAccessRoles = <UserAccessRoleOption>[
  UserAccessRoleOption('president', 'Presidente'),
  UserAccessRoleOption('vice_president', 'Vice-Presidente'),
  UserAccessRoleOption('admin', 'Administrador'),
  UserAccessRoleOption('treasurer', 'Tesoureiro'),
  UserAccessRoleOption('secretary', 'Secretário'),
  UserAccessRoleOption('road_captain', 'Road Captain'),
  UserAccessRoleOption('sergeant_at_arms', 'Sargento de Armas'),
  UserAccessRoleOption('inventory_manager', 'Responsável de Inventário'),
  UserAccessRoleOption('event_manager', 'Responsável de Eventos'),
  UserAccessRoleOption('euromillions_manager', 'Responsável Euromilhões'),
  UserAccessRoleOption('prospect', 'Prospect'),
  UserAccessRoleOption('member', 'Membro / Full Color'),
];

String userAccessStateLabel(String state) => switch (state) {
      'invited' => 'Convite enviado',
      'active' => 'Ativo',
      'blocked' => 'Bloqueado',
      _ => 'Sem acesso',
    };

String userAccessRoleLabel(String key) {
  final canonical = _canonicalRole(key);
  for (final role in userAccessRoles) {
    if (role.key == canonical) return role.label;
  }
  if (key == 'super_admin') return 'Super Admin';
  return key;
}

String _canonicalRole(String? key) => switch (key) {
      'administrator' => 'admin',
      'events_manager' => 'event_manager',
      null || '' => 'member',
      _ => key,
    };

String _initial(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '?' : text[0].toUpperCase();
}

IconData _stateIcon(String state) => switch (state) {
      'invited' => Icons.mark_email_unread_outlined,
      'active' => Icons.verified_user_outlined,
      'blocked' => Icons.block_outlined,
      _ => Icons.person_off_outlined,
    };
