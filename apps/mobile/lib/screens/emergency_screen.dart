import 'package:flutter/material.dart';

import '../services/data_service.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showEmergencyDetails(Map<String, dynamic> member) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        String value(String key) {
          final item = member[key];
          return item == null || item.toString().trim().isEmpty
              ? 'Não registado'
              : item.toString();
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  value('full_name'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('${value('nickname')} • ${value('primary_role')}'),
                const SizedBox(height: 16),
                _EmergencyLine(label: 'Telefone', value: value('phone')),
                _EmergencyLine(
                  label: 'Contacto de emergência',
                  value: value('emergency_name'),
                ),
                _EmergencyLine(
                  label: 'Relação',
                  value: value('emergency_relation'),
                ),
                _EmergencyLine(
                  label: 'Telefone emergência',
                  value: value('emergency_phone'),
                ),
                _EmergencyLine(
                  label: 'Grupo sanguíneo',
                  value: value('blood_type'),
                ),
                _EmergencyLine(label: 'Alergias', value: value('allergies')),
                _EmergencyLine(
                  label: 'Informação médica',
                  value: value('medical_notes'),
                ),
                _EmergencyLine(
                  label: 'Mota',
                  value:
                      '${value('motorcycle_brand')} ${value('motorcycle_model')}',
                ),
                _EmergencyLine(
                  label: 'Matrícula',
                  value: value('motorcycle_registration'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext),
                  icon: const Icon(Icons.check),
                  label: const Text('Fechar'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DataService.instance.list('members'),
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
          return member.values.any(
            (value) => value.toString().toLowerCase().contains(query),
          );
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.emergency, color: Colors.red),
                title: Text('Vista de Emergência'),
                subtitle: Text(
                  'Contactos, alergias, informação médica, mota e matrícula. O acesso deverá ficar auditado na base real.',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Pesquisar membro, alcunha ou matrícula',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            ...members.map(
              (member) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('${member['full_name']}'),
                  subtitle: Text(
                    '${member['nickname'] ?? ''} • '
                    '${member['motorcycle_registration'] ?? 'Sem matrícula'}',
                  ),
                  trailing: const Icon(Icons.medical_information_outlined),
                  onTap: () => _showEmergencyDetails(member),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EmergencyLine extends StatelessWidget {
  const _EmergencyLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
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
}
