import 'package:bob_manager_mobile/repositories/member_photo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('constrói caminho versionado da fotografia do membro', () {
    expect(
      MemberPhotoRepository.photoPath(
        clubId: 'club-1',
        memberId: 'member-7',
        version: 123456,
      ),
      'club-1/members/member-7/photo_123456.jpg',
    );
  });

  test('deriva caminho da miniatura a partir da fotografia', () {
    expect(
      MemberPhotoRepository.thumbnailPathFor(
        'club-1/members/member-7/photo_123456.jpg',
      ),
      'club-1/members/member-7/thumb_123456.jpg',
    );
  });

  test('mantém caminho legado quando não segue o padrão versionado', () {
    expect(
      MemberPhotoRepository.thumbnailPathFor(
        'club-1/members/member-7/profile.jpg',
      ),
      'club-1/members/member-7/profile.jpg',
    );
  });
}
