import 'package:flutter/material.dart';

import '../repositories/documents_advanced_repository.dart';
import 'annual_books_screen.dart';
import 'document_approvals_screen.dart';
import 'document_gallery_screen.dart';
import 'document_library_advanced_screen.dart';
import 'document_personal_archive_screen.dart';

class DocumentsModuleScreen extends StatefulWidget {
  const DocumentsModuleScreen({super.key});

  @override
  State<DocumentsModuleScreen> createState() => _DocumentsModuleScreenState();
}

class _DocumentsModuleScreenState extends State<DocumentsModuleScreen> {
  final DocumentsAdvancedRepository _repository = DocumentsAdvancedRepository();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DocumentLibraryAdvancedScreen(repository: _repository),
          DocumentPersonalArchiveScreen(repository: _repository),
          DocumentApprovalsScreen(repository: _repository),
          DocumentGalleryScreen(repository: _repository),
          AnnualBooksScreen(repository: _repository),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.lock_outline),
            selectedIcon: Icon(Icons.lock),
            label: 'Meu arquivo',
          ),
          NavigationDestination(
            icon: Icon(Icons.approval_outlined),
            selectedIcon: Icon(Icons.approval),
            label: 'Aprovar',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Galeria',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Livro',
          ),
        ],
      ),
    );
  }
}
