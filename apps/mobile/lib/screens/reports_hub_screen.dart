import 'package:flutter/material.dart';

import '../core/app_session.dart';
import '../core/club_export.dart';
import '../core/importing.dart';
import 'club_export_screen.dart';
import 'import_wizard_screen.dart';
import 'reports_screen.dart';

class ReportsHubScreen extends StatelessWidget {
  const ReportsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppSession.instance;
    final canExport = ClubExportPolicy.canExport(session);
    final canImport = ImportCatalog.canOpen(session);

    if (!canExport && !canImport) return const ReportsScreen();

    return Column(
      children: [
        if (canExport)
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
        if (canImport)
          Padding(
            padding: EdgeInsets.fromLTRB(16, canExport ? 8 : 16, 16, 0),
            child: Card(
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.upload_file_outlined),
                ),
                title: const Text('Assistente de Importação'),
                subtitle: const Text(
                  'CSV/Excel com mapeamento, pré-visualização, correção, '
                  'validação server-side e reversão protegida.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ImportWizardScreen(),
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
