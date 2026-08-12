import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/member_photo_repository.dart';
import '../repositories/member_repository.dart';
import '../widgets/member_photo_avatar.dart';
import 'entity_form_screen.dart';
import 'member_history_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.member});

  final Map<String, dynamic> member;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final MemberRepository _repository = MemberRepository();
  final MemberPhotoRepository _photoRepository = MemberPhotoRepository();
  final ImagePicker _imagePicker = ImagePicker();
  late Map<String, dynamic> _member;
  late Future<Map<String, int>> _relatedCounts;
  bool _photoBusy = false;

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
    _member = Map<String, dynamic>.from(widget.member);
    _relatedCounts = _loadRelatedCounts();
  }

  Future<Map<String, int>> _loadRelatedCounts() async {
    final id = _member['id'].toString();
    final results = await Future.wait([
      _repository.related('motorcycles', id),
      _repository.related('maintenance_records', id),
      _repository.related('member_patch_awards', id),
      _repository.related('member_timeline', id),
    ]);
    return {
      'motorcycles': results[0].length,
      'maintenance': results[1].length,
      'patches': results[2].length,
      'timeline': results[3].length,
    };
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: memberDefinition,
          initialValues: _member,
          readOnlyKeys: _memberReadOnlyKeys,
          onSave: (values, id) async {
            await _repository.saveMember(values, memberId: id);
          },
        ),
      ),
    );
    if (changed != true) return;
    final refreshed = await _repository.getMember(_member['id'].toString());
    if (refreshed != null && mounted) {
      setState(() {
        _member = refreshed;
        _relatedCounts = _loadRelatedCounts();
      });
    }
  }

  Future<void> _openHistory(int initialIndex) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemberHistoryScreen(
          member: _member,
          initialIndex: initialIndex,
        ),
      ),
    );
    if (!mounted) return;
    final refreshed = await _repository.getMember(_member['id'].toString());
    setState(() {
      if (refreshed != null) _member = refreshed;
      _relatedCounts = _loadRelatedCounts();
    });
  }

  Future<void> _refreshMember() async {
    final refreshed = await _repository.getMember(_member['id'].toString());
    if (refreshed == null || !mounted) return;
    setState(() => _member = refreshed);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _imagePicker.pickImage(source: source);
    if (file == null || !mounted) return;

    setState(() => _photoBusy = true);
    try {
      await _photoRepository.uploadMemberPhoto(
        memberId: _member['id'].toString(),
        file: file,
      );
      await _refreshMember();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotografia do membro atualizada.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível atualizar a fotografia: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _confirmRemovePhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover fotografia?'),
        content: const Text(
          'A fotografia deixará de aparecer no perfil e na lista de membros.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _photoBusy = true);
    try {
      await _photoRepository.removeMemberPhoto(_member['id'].toString());
      await _refreshMember();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotografia removida.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível remover a fotografia: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _showPhotoActions() async {
    if (!_canManage || _photoBusy) return;
    final hasPhoto = (_member['photo_path']?.toString().trim() ?? '').isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text('Fotografia do membro'),
              subtitle: Text('Escolhe a origem da imagem.'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Câmara'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeria'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remover fotografia'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmRemovePhoto();
                },
              ),
          ],
        ),
      ),
    );
  }

  String _text(String key, [String fallback = '—']) {
    final value = _member[key];
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString();
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _areaTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required int tab,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(label: Text('$count'), visualDensity: VisualDensity.compact),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => _openHistory(tab),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _text('full_name', 'Membro');
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Editar membro',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        MemberPhotoAvatar(
                          member: _member,
                          repository: _photoRepository,
                          radius: 42,
                          thumbnail: false,
                        ),
                        if (_photoBusy)
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(),
                          )
                        else if (_canManage)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: Theme.of(context).colorScheme.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _showPhotoActions,
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(
                                    Icons.photo_camera_outlined,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_text('nickname', '').isNotEmpty)
                          Text('“${_text('nickname')}”'),
                        const SizedBox(height: 6),
                        Text('${_text('primary_role')} • ${_text('status')}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _section(
            context,
            title: 'Identificação e percurso',
            icon: Icons.badge_outlined,
            children: [
              _line('Número', _text('member_number')),
              _line('Estado', _text('status')),
              _line('Cargo principal', _text('primary_role')),
              _line('Cargos adicionais', _text('additional_roles')),
              _line('Nascimento', _text('birth_date')),
              _line('Entrada Prospect', _text('prospect_joined_at')),
              _line('Full Color', _text('full_colors_at')),
            ],
          ),
          _section(
            context,
            title: 'Contactos',
            icon: Icons.contact_phone_outlined,
            children: [
              _line('Telefone', _text('phone')),
              _line('Email', _text('email')),
              _line('Morada', _text('address')),
              _line('Localidade', _text('locality')),
            ],
          ),
          _section(
            context,
            title: 'Emergência e saúde',
            icon: Icons.emergency_outlined,
            children: [
              _line('Contacto', _text('emergency_name')),
              _line('Relação', _text('emergency_relation')),
              _line('Telefone', _text('emergency_phone')),
              _line('Grupo sanguíneo', _text('blood_type')),
              _line('Alergias', _text('allergies')),
              _line('Observações médicas', _text('medical_notes')),
            ],
          ),
          _section(
            context,
            title: 'Mota principal',
            icon: Icons.two_wheeler_outlined,
            children: [
              _line('Marca', _text('motorcycle_brand')),
              _line('Modelo', _text('motorcycle_model')),
              _line('Ano', _text('motorcycle_year')),
              _line('Matrícula', _text('motorcycle_registration')),
            ],
          ),
          FutureBuilder<Map<String, int>>(
            future: _relatedCounts,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              final counts = snapshot.data!;
              return _section(
                context,
                title: 'Histórico avançado',
                icon: Icons.account_tree_outlined,
                children: [
                  _areaTile(
                    icon: Icons.two_wheeler_outlined,
                    title: 'Motas',
                    subtitle: 'Motas atuais e arquivo histórico.',
                    count: counts['motorcycles'] ?? 0,
                    tab: 0,
                  ),
                  const Divider(),
                  _areaTile(
                    icon: Icons.build_outlined,
                    title: 'Manutenções',
                    subtitle: 'Serviços, custos, próximas revisões e documentos privados.',
                    count: counts['maintenance'] ?? 0,
                    tab: 1,
                  ),
                  const Divider(),
                  _areaTile(
                    icon: Icons.military_tech_outlined,
                    title: 'Patches',
                    subtitle: 'Aprovação, entrega institucional e integração com stock.',
                    count: counts['patches'] ?? 0,
                    tab: 2,
                  ),
                  const Divider(),
                  _areaTile(
                    icon: Icons.timeline_outlined,
                    title: 'Timeline',
                    subtitle: 'Percurso automático do membro e eventos relevantes.',
                    count: counts['timeline'] ?? 0,
                    tab: 3,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
