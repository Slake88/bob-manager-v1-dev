import 'package:flutter/material.dart';

import '../services/data_service.dart';

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

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

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.emergency, color: Colors.red),
                title: Text('Vista de Emergência'),
                subtitle: Text(
                  'Acesso auditado a contactos e informação médica essencial.',
                ),
              ),
            ),
            ...snapshot.data!.map(
              (member) => Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('${member['full_name']}'),
                  subtitle: Text(
                    '${member['nickname'] ?? ''} • '
                    '${member['phone'] ?? 'Sem telefone'}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.medical_information),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Dados médicos carregados quando existirem.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
