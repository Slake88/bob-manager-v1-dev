import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/images/default_image_processor.dart';
import '../core/images/image_pipeline_service.dart';
import '../core/images/image_profiles.dart';
import '../core/permissions.dart';

class MemberPhotoRepository {
  MemberPhotoRepository({SupabaseClient? client}) : _client = client;

  static const String bucketName = 'member-photos';
  static const int signedUrlLifetimeSeconds = 3600;

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  static String photoPath({
    required String clubId,
    required String memberId,
    required int version,
  }) =>
      '$clubId/members/$memberId/photo_$version.jpg';

  static String thumbnailPathFor(String photoPath) {
    final slash = photoPath.lastIndexOf('/');
    if (slash < 0) return photoPath;
    final directory = photoPath.substring(0, slash + 1);
    final fileName = photoPath.substring(slash + 1);
    if (!fileName.startsWith('photo_')) return photoPath;
    return '$directory${fileName.replaceFirst('photo_', 'thumb_')}';
  }

  Future<String> uploadMemberPhoto({
    required String memberId,
    required XFile file,
  }) async {
    _require(AppPermission.manageMembers);
    if (AppConfig.demoMode) {
      throw StateError('A fotografia de membro requer ligação ao Supabase.');
    }

    final member = await _supabase
        .from('members')
        .select('id,photo_path')
        .eq('id', memberId)
        .eq('club_id', _clubId)
        .single();
    final previousPath = member['photo_path']?.toString();

    const pipeline = ImagePipelineService(
      processor: DefaultImageProcessor(),
    );
    final processed = await pipeline.process(
      file: file,
      profile: ImageProfiles.member,
    );

    final version = DateTime.now().microsecondsSinceEpoch;
    final path = photoPath(
      clubId: _clubId,
      memberId: memberId,
      version: version,
    );
    final thumbnailPath = thumbnailPathFor(path);

    var mainUploaded = false;
    var thumbnailUploaded = false;
    try {
      await _supabase.storage.from(bucketName).uploadBinary(
            path,
            processed.optimized,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      mainUploaded = true;

      await _supabase.storage.from(bucketName).uploadBinary(
            thumbnailPath,
            processed.thumbnail,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      thumbnailUploaded = true;

      await _supabase
          .from('members')
          .update({'photo_path': path})
          .eq('id', memberId)
          .eq('club_id', _clubId);
    } catch (_) {
      final uploaded = <String>[
        if (mainUploaded) path,
        if (thumbnailUploaded) thumbnailPath,
      ];
      if (uploaded.isNotEmpty) {
        try {
          await _supabase.storage.from(bucketName).remove(uploaded);
        } catch (_) {
          // Best-effort cleanup. The original error is more relevant to the caller.
        }
      }
      rethrow;
    }

    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != path) {
      try {
        await _supabase.storage.from(bucketName).remove([
          previousPath,
          thumbnailPathFor(previousPath),
        ]);
      } catch (_) {
        // A fotografia nova já está ativa. Um ficheiro antigo órfão não deve
        // invalidar uma substituição concluída com sucesso.
      }
    }

    return path;
  }

  Future<void> removeMemberPhoto(String memberId) async {
    _require(AppPermission.manageMembers);
    if (AppConfig.demoMode) return;

    final member = await _supabase
        .from('members')
        .select('photo_path')
        .eq('id', memberId)
        .eq('club_id', _clubId)
        .single();
    final path = member['photo_path']?.toString();

    await _supabase
        .from('members')
        .update({'photo_path': null})
        .eq('id', memberId)
        .eq('club_id', _clubId);

    if (path == null || path.isEmpty) return;
    try {
      await _supabase.storage.from(bucketName).remove([
        path,
        thumbnailPathFor(path),
      ]);
    } catch (_) {
      // A referência já foi removida do perfil. Limpeza de órfãos pode ser
      // repetida numa manutenção futura sem bloquear o utilizador.
    }
  }

  Future<String?> signedMemberPhotoUrl(
    Object? photoPath, {
    bool thumbnail = true,
  }) async {
    final path = photoPath?.toString().trim() ?? '';
    if (path.isEmpty || AppConfig.demoMode) return null;
    final requestedPath = thumbnail ? thumbnailPathFor(path) : path;
    return _supabase.storage.from(bucketName).createSignedUrl(
          requestedPath,
          signedUrlLifetimeSeconds,
        );
  }

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para gerir a fotografia deste membro.');
    }
  }
}
