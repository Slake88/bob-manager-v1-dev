import 'package:flutter/material.dart';

import '../core/entity_definition.dart';
import '../services/data_service.dart';
import 'entity_form_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.member});

  final Map<String, dynamic> member;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  late Map<String, dynamic> _member;

  @override
  void initState() {
    super.initState();
    _member = Map<String, dynamic>.from(widget.member);
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntityFormScreen(
          definition: memberDefinition,
          initialValues: _member,
        ),
      ),
    );
    if (changed != true) return;
    final refreshed = await DataService.instance.getById(
      memberDefinition.table,
      _member['id'].toString(),
    );
    if (refreshed != null && mounted) {
      setState(() => _member = refreshed);
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
    final motorcycle = [
      _text('motorcycle_brand', ''),
      _text('motorcycle_model', ''),
      _text('motorcycle_year', ''),
    ].where((value) => value.isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('full_name', 'Membro')),
        actions: [
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
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        child: Text(
                          _text('full_name', '?').substring(0, 1).toUpperCase(),
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                      const CircleAvatar(
                        radius: 15,
                        child: Icon(Icons.photo_camera_outlined, size: 16),
                      ),
                    ],
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _text('full_name'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_text('nickname', '').isNotEmpty)
                          Text('“${_text('nickname')}”'),
                        const SizedBox(height: 6),
                        Text(
                          '${_text('primary_role')} • ${_text('status')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (motorcycle.isNotEmpty) Text(motorcycle),
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
              _line('Código postal', _text('postal_code')),
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
              const SizedBox(height: 8),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.build_outlined),
                title: Text('Manutenção e documentos'),
                subtitle: Text(
                  'A estrutura definitiva está preparada para várias motas, serviços, custos e anexos.',
                ),
              ),
            ],
          ),
          _section(
            context,
            title: 'Áreas ligadas',
            icon: Icons.account_tree_outlined,
            children: const [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.timeline_outlined),
                title: Text('Timeline'),
                subtitle: Text('Percurso, cargos, patches e participação em eventos.'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.receipt_long_outlined),
                title: Text('Quotas'),
                subtitle: Text('Saldo e histórico ficam no módulo Quotas.'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.casino_outlined),
                title: Text('Euromilhões'),
                subtitle: Text('Chave individual, pagamentos e acertos.'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_outlined),
                title: Text('Eventos'),
                subtitle: Text('Presenças, acompanhantes e voluntariado.'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
