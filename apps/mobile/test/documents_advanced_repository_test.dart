import 'package:bob_manager_mobile/core/app_role.dart';
import 'package:bob_manager_mobile/core/app_session.dart';
import 'package:bob_manager_mobile/core/permissions.dart';
import 'package:bob_manager_mobile/repositories/documents_advanced_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    PermissionPolicy.reset();
    AppSession.instance.clear();
    AppSession.instance.role = 'Administrador';
  });

  tearDown(() {
    PermissionPolicy.reset();
    AppSession.instance.clear();
  });

  test('membro vê documentos mas não aprova nem gere livro', () {
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.viewDocuments),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(AppRole.member, AppPermission.approveDocuments),
      isFalse,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.member,
        AppPermission.manageAnnualBooks,
      ),
      isFalse,
    );
  });

  test('secretário gere workflow documental completo', () {
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageDocuments,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.approveDocuments,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.runDocumentOcr,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.secretary,
        AppPermission.manageAnnualBooks,
      ),
      isTrue,
    );
  });

  test('responsável de eventos gere galeria sem aprovar documentos', () {
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.manageEventGallery,
      ),
      isTrue,
    );
    expect(
      PermissionPolicy.allows(
        AppRole.eventsManager,
        AppPermission.approveDocuments,
      ),
      isFalse,
    );
  });

  test('limite pessoal é 500 MB e ratio fica protegido', () {
    expect(
      DocumentsAdvancedRepository.personalLimitBytes,
      500 * 1024 * 1024,
    );
    expect(DocumentsAdvancedRepository.usageRatio(0), 0);
    expect(
      DocumentsAdvancedRepository.usageRatio(250 * 1024 * 1024),
      closeTo(0.5, 0.0001),
    );
    expect(
      DocumentsAdvancedRepository.usageRatio(900 * 1024 * 1024),
      1,
    );
  });

  test('helpers distinguem OCR e galeria', () {
    expect(DocumentsAdvancedRepository.isOcrMime('application/pdf'), isTrue);
    expect(DocumentsAdvancedRepository.isOcrMime('image/webp'), isTrue);
    expect(
      DocumentsAdvancedRepository.isOcrMime('application/msword'),
      isFalse,
    );
    expect(
      DocumentsAdvancedRepository.isGalleryMime('image/jpeg'),
      isTrue,
    );
    expect(
      DocumentsAdvancedRepository.isGalleryMime('application/pdf'),
      isFalse,
    );
    expect(DocumentsAdvancedRepository.scopeLabel('personal'), 'Pessoal');
    expect(
      DocumentsAdvancedRepository.scopeLabel('event_gallery'),
      'Galeria',
    );
  });

  test('formatação de espaço mantém leitura Mobile First', () {
    expect(DocumentsAdvancedRepository.formatBytes(0), '0 B');
    expect(DocumentsAdvancedRepository.formatBytes(1024), '1.0 KB');
    expect(
      DocumentsAdvancedRepository.formatBytes(10 * 1024 * 1024),
      '10.0 MB',
    );
  });

  test('modo demo expõe arquivo, galeria, timeline e livro anual', () async {
    final repository = DocumentsAdvancedRepository();
    final documents = await repository.listDocuments();
    final personal = await repository.listPersonal();
    final gallery = await repository.listGallery('demo-event');
    final books = await repository.listAnnualBooks();
    final timeline = await repository.timelineForYear(DateTime.now().year);

    expect(documents, isNotEmpty);
    expect(personal.single['scope'], 'personal');
    expect(gallery.single['scope'], 'event_gallery');
    expect(books.single['status'], 'draft');
    expect(timeline.single['title'], isNotEmpty);
  });
}
