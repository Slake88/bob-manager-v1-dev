import 'package:bob_manager_mobile/repositories/member_lifecycle_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('caminho de documento de manutenção fica isolado por clube e membro', () {
    final path = MemberLifecycleRepository.maintenanceAttachmentPath(
      'club-1',
      'member-2',
      'maintenance-3',
      123456,
      'Fatura Oficina #45.pdf',
    );

    expect(
      path,
      'club-1/members/member-2/maintenance/maintenance-3/'
      '123456_Fatura_Oficina_45.pdf',
    );
  });

  test('formatos permitidos de manutenção são normalizados', () {
    expect(
      MemberLifecycleRepository.mimeTypeForName('fatura.PDF'),
      'application/pdf',
    );
    expect(
      MemberLifecycleRepository.mimeTypeForName('foto.JPEG'),
      'image/jpeg',
    );
    expect(MemberLifecycleRepository.mimeTypeForName('imagem.webp'), 'image/webp');
    expect(MemberLifecycleRepository.mimeTypeForName('ficheiro.exe'), isNull);
  });

  test('estados de patches têm etiquetas portuguesas', () {
    expect(MemberLifecycleRepository.patchStatusLabel('pending'), 'Pendente');
    expect(MemberLifecycleRepository.patchStatusLabel('approved'), 'Aprovado');
    expect(MemberLifecycleRepository.patchStatusLabel('delivered'), 'Entregue');
    expect(MemberLifecycleRepository.patchStatusLabel('cancelled'), 'Cancelado');
  });
}
