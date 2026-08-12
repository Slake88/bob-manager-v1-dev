import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/member_photo_repository.dart';
import '../repositories/member_repository.dart';
import '../widgets/member_photo_avatar.dart';
import 'entity_form_screen.dart';
import 'member_detail_screen.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final MemberRepository _repository = MemberRepository();
  final MemberPhotoRepository _photoRepository = MemberPhotoRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future;

  bool get _canManage => PermissionPolicy.allows(
        AppRole.fromValue(AppSession.instance.role),
        AppPermission.manageMembers,
      );

  Set<String> get _memberReadOnlyKeys =>
      AppSession.instance.canEditMemberMilestoneDates
          ? const <String>{}
          : const <String>{'prospect_joined_at', 'full_colors_at'};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    _future = _repository.listMembers();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openForm([Map<String, dynamic>? member]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: memberDefinition,
          initialValues: member,
          readOnlyKeys: _memberReadOnlyKeys,
          onSave: (values, id) async {
            await _repository.saveMember(values, memberId: id);
          },
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _openDetails(Map<String, dynamic> member) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberDetailScreen(member: member),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar membro?'),
        content: Text(
          'Pretendes eliminar ${member['full_name'] ?? 'este membro'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteMember(member['id'].toString());
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final query = _searchController.text.trim().toLowerCase();
          final members = snapshot.data!.where((member) {
            if (query.isEmpty) return true;
            return [
              member['full_name'],
              member['nickname'],
              member['member_number'],
              member['motorcycle_model'],
              member['motorcycle_registration'],
            ].any(
              (value) => value.toString().toLowerCase().contains(query),
            );
          }).toList();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText:
                        'Pesquisar por nome, alcunha, número, mota ou matrícula',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${members.length} membro${members.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ...members.map(
                  (member) => Card(
                    child: ListTile(
                      leading: MemberPhotoAvatar(
                        member: member,
                        repository: _photoRepository,
                        radius: 22,
                      ),
                      title: Text(member['full_name']?.toString() ?? 'Membro'),
                      subtitle: Text(
                        [
                          member['nickname'],
                          member['member_number'],
                          member['status'],
                          member['primary_role'],
                        ]
                            .where(
                              (value) =>
                                  value != null && value.toString().isNotEmpty,
                            )
                            .join(' • '),
                      ),
                      trailing: _canManage
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') _openForm(member);
                                if (value == 'delete') _delete(member);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Editar'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Eliminar'),
                                ),
                              ],
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: () => _openDetails(member),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Novo membro'),
            )
          : null,
    );
  }
}
