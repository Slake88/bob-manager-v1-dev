import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import 'shop_repository.dart';

extension ProductImagesRepositoryExtension on ShopRepository {
  SupabaseClient get _imagesClient => Supabase.instance.client;
  String get _imagesClubId => AppSession.instance.clubId;

  void _requireImagesManage() {
    if (!AppSession.instance.can(AppPermission.manageMerchandising)) {
      throw StateError('Sem permissão para gerir fotografias dos artigos.');
    }
  }

  Future<List<Map<String, dynamic>>> productImages(String productId) async {
    final response = await _imagesClient
        .from('product_images')
        .select('id,storage_path,is_primary,created_at')
        .eq('club_id', _imagesClubId)
        .eq('product_id', productId)
        .order('is_primary', ascending: false)
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> setPrimaryProductImage({
    required String productId,
    required String imageId,
    required String storagePath,
  }) async {
    _requireImagesManage();
    await _imagesClient
        .from('product_images')
        .update({'is_primary': false})
        .eq('club_id', _imagesClubId)
        .eq('product_id', productId);
    await _imagesClient
        .from('product_images')
        .update({'is_primary': true})
        .eq('club_id', _imagesClubId)
        .eq('id', imageId);
    await _imagesClient
        .from('products')
        .update({'photo_path': storagePath})
        .eq('club_id', _imagesClubId)
        .eq('id', productId);
  }

  Future<String> uploadGalleryImage({
    required String productId,
    required XFile file,
  }) async {
    _requireImagesManage();
    final Uint8List bytes = await file.readAsBytes();
    final extension = file.name.toLowerCase().endsWith('.png')
        ? 'png'
        : file.name.toLowerCase().endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final path = '$_imagesClubId/products/$productId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _imagesClient.storage.from('inventory-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    final current = await _imagesClient
        .from('products')
        .select('photo_path')
        .eq('club_id', _imagesClubId)
        .eq('id', productId)
        .single();
    final first = (current['photo_path']?.toString() ?? '').isEmpty;
    final inserted = await _imagesClient.from('product_images').insert({
      'club_id': _imagesClubId,
      'product_id': productId,
      'storage_path': path,
      'is_primary': first,
      'created_by': AppSession.instance.profileId,
    }).select('id').single();
    if (first) {
      await setPrimaryProductImage(
        productId: productId,
        imageId: inserted['id'].toString(),
        storagePath: path,
      );
    }
    return path;
  }

  Future<void> deleteProductImage({
    required String productId,
    required String imageId,
    required String storagePath,
    required bool wasPrimary,
  }) async {
    _requireImagesManage();
    await _imagesClient.storage.from('inventory-media').remove([storagePath]);
    await _imagesClient
        .from('product_images')
        .delete()
        .eq('club_id', _imagesClubId)
        .eq('id', imageId);
    if (!wasPrimary) return;
    final remaining = await productImages(productId);
    if (remaining.isEmpty) {
      await _imagesClient
          .from('products')
          .update({'photo_path': null})
          .eq('club_id', _imagesClubId)
          .eq('id', productId);
      return;
    }
    final next = remaining.first;
    await setPrimaryProductImage(
      productId: productId,
      imageId: next['id'].toString(),
      storagePath: next['storage_path'].toString(),
    );
  }
}
