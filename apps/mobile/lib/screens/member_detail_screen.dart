import 'package:flutter/material.dart';

import '../core/app_role.dart';
import '../core/app_session.dart';
import '../core/entity_definition.dart';
import '../core/permissions.dart';
import '../repositories/member_repository.dart';
import 'entity_form_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.member});

  final Map<String, dynamic> member;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  final MemberRepository _repository = MemberRepository();
  late Map<String, dynamic> _member;
  late Future<Map<String, int>> _relatedCounts;

  bool get _canManage => PermissionPolicy.allows(
        AppRole.fromValue(AppSession.instance.role),
        AppPermission.manageMembers,
      );

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
                  CircleAvatar(
                    radius: 42,
                    child: Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: Theme.of(context).textTheme.headlineSmall),
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
                title: 'Áreas ligadas',
                icon: Icons.account_tree_outlined,
                children: [
                  _line('Motas', counts['motorcycles'].toString()),
                  _line('Manutenções', counts['maintenance'].toString()),
                  _line('Patches', counts['patches'].toString()),
                  _line('Registos na Timeline', counts['timeline'].toString()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
