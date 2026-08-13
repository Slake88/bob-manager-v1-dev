import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/club_export.dart';
import 'club_export_screen.dart';
import 'reports_screen.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final canExport = ClubExportPolicy.canExport(AppSession.instance);

    if (!canExport) return const ReportsScreen();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.folder_zip_outlined),
              ),
              title: const Text('Exportação Integral do Clube'),
              subtitle: const Text(
                'Arquivo administrativo em ZIP com manifest, CSVs, '
                'auditoria e opções protegidas.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ClubExportScreen(),
                ),
              ),
            ),
          ),
        ),
        const Expanded(child: ReportsScreen()),
      ],
    );
  }
}
