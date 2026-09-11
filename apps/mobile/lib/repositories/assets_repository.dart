import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class AssetsRepository {
  SupabaseClient get _client => Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  void _require(AppPermission permission) {
    if (!AppSession.instance.can(permission)) {
      throw StateError('Sem permissão para executar esta operação.');
    }
  }

  Future<List<Map<String, dynamic>>> assets() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_assets')
        .select('id,asset_number,qr_code,name,category,description,brand,model,serial_number,acquisition_date,acquisition_value,current_value,supplier,condition,location_id,responsible_member_id,photo_path,warranty_until,requires_inspection,inspection_interval_months,last_inspection_at,next_inspection_at,custom_attributes,active,notes,created_at,updated_at,inventory_locations(name),members(full_name,nickname)')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('asset_number');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> locations() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_locations')
        .select('id,name,description,active')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> categories() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('inventory_categories')
        .select('id,name,active')
        .eq('club_id', _clubId)
        .eq('area', 'asset')
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> members() async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('members')
        .select('id,full_name,nickname,status')
        .eq('club_id', _clubId)
        .order('full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> eventsForAsset(String assetId) async {
    _require(AppPermission.viewInventory);
    final response = await _client
        .from('asset_events')
        .select('id,event_type,title,description,metadata,created_at')
        .eq('club_id', _clubId)
        .eq('asset_id', assetId)
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, String>> nextCodes() async {
    _require(AppPermission.manageAssets);
    final response = await _client.rpc('next_asset_codes_v1', params: {
      'target_club': _clubId,
    });
    final map = Map<String, dynamic>.from(response as Map);
    return {
      'asset_number': map['asset_number']?.toString() ?? '',
      'qr_code': map['qr_code']?.toString() ?? '',
    };
  }

  Future<Map<String, dynamic>> saveAsset({
    String? id,
    required String assetNumber,
    required String qrCode,
    required String name,
    required String category,
    required String description,
    required String brand,
    required String model,
    required String serialNumber,
    required String condition,
    String? locationId,
    String? responsibleMemberId,
    DateTime? acquisitionDate,
    required double acquisitionValue,
    required double currentValue,
    required String supplier,
    DateTime? warrantyUntil,
    required bool requiresInspection,
    int? inspectionIntervalMonths,
    DateTime? lastInspectionAt,
    DateTime? nextInspectionAt,
    required Map<String, dynamic> customAttributes,
    required String notes,
  }) async {
    _require(AppPermission.manageAssets);
    if (name.trim().isEmpty) throw ArgumentError('Indica o nome do bem.');
    if (assetNumber.trim().isEmpty) throw ArgumentError('Código patrimonial inválido.');

    final values = <String, dynamic>{
      'club_id': _clubId,
      'asset_number': assetNumber.trim(),
      'qr_code': qrCode.trim().isEmpty ? null : qrCode.trim(),
      'name': name.trim(),
      'category': category.trim().isEmpty ? 'Outros' : category.trim(),
      'description': _nullIfEmpty(description),
      'brand': _nullIfEmpty(brand),
      'model': _nullIfEmpty(model),
      'serial_number': _nullIfEmpty(serialNumber),
      'condition': condition,
      'location_id': locationId,
      'responsible_member_id': responsibleMemberId,
      'acquisition_date': _date(acquisitionDate),
      'acquisition_value': acquisitionValue,
      'current_value': currentValue,
      'supplier': _nullIfEmpty(supplier),
      'warranty_until': _date(warrantyUntil),
      'requires_inspection': requiresInspection,
      'inspection_interval_months': requiresInspection ? inspectionIntervalMonths : null,
      'last_inspection_at': requiresInspection ? _date(lastInspectionAt) : null,
      'next_inspection_at': requiresInspection ? _date(nextInspectionAt) : null,
      'custom_attributes': customAttributes,
      'notes': _nullIfEmpty(notes),
      'active': true,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (id == null) {
      final response = await _client
          .from('inventory_assets')
          .insert({...values, 'created_by': AppSession.instance.profileId})
          .select()
          .single();
      final asset = Map<String, dynamic>.from(response);
      await logEvent(
        asset['id'].toString(),
        type: 'created',
        title: 'Bem criado',
        description: '${asset['asset_number']} · ${asset['name']}',
      );
      return asset;
    }

    final response = await _client
        .from('inventory_assets')
        .update(values..remove('club_id'))
        .eq('id', id)
        .eq('club_id', _clubId)
        .select()
        .single();
    await logEvent(id, type: 'updated', title: 'Ficha atualizada');
    return Map<String, dynamic>.from(response);
  }

  Future<void> logEvent(
    String assetId, {
    required String type,
    required String title,
    String? description,
    Map<String, dynamic> metadata = const {},
  }) async {
    _require(AppPermission.manageAssets);
    await _client.rpc('log_asset_event_v1', params: {
      'target_club': _clubId,
      'p_asset': assetId,
      'p_type': type,
      'p_title': title,
      'p_description': description,
      'p_metadata': metadata,
    });
  }

  Future<void> addLocation(String name) async {
    _require(AppPermission.manageAssets);
    final clean = name.trim();
    if (clean.isEmpty) return;
    await _client.from('inventory_locations').upsert({
      'club_id': _clubId,
      'name': clean,
      'active': true,
    }, onConflict: 'club_id,name');
  }

  Future<void> addCategory(String name) async {
    _require(AppPermission.manageAssets);
    final clean = name.trim();
    if (clean.isEmpty) return;
    await _client.from('inventory_categories').upsert({
      'club_id': _clubId,
      'area': 'asset',
      'name': clean,
      'active': true,
    }, onConflict: 'club_id,area,name');
  }

  Future<String> uploadPrimaryImage({
    required String assetId,
    required XFile file,
  }) async {
    _require(AppPermission.manageAssets);
    final Uint8List bytes = await file.readAsBytes();
    final lower = file.name.toLowerCase();
    final extension = lower.endsWith('.png')
        ? 'png'
        : lower.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final path = '$_clubId/assets/$assetId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await _client.storage.from('inventory-media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: file.mimeType, upsert: false),
        );
    await _client
        .from('inventory_assets')
        .update({'photo_path': path, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', assetId)
        .eq('club_id', _clubId);
    await _client.from('asset_images').update({'is_primary': false}).eq('asset_id', assetId);
    await _client.from('asset_images').insert({
      'club_id': _clubId,
      'asset_id': assetId,
      'storage_path': path,
      'image_type': 'main',
      'is_primary': true,
      'created_by': AppSession.instance.profileId,
    });
    await logEvent(assetId, type: 'photo', title: 'Fotografia principal alterada');
    return path;
  }

  String? publicImageUrl(Object? path) {
    final value = path?.toString();
    if (value == null || value.isEmpty) return null;
    return _client.storage.from('inventory-media').getPublicUrl(value);
  }

  String? _nullIfEmpty(String value) => value.trim().isEmpty ? null : value.trim();
  String? _date(DateTime? value) => value?.toIso8601String().split('T').first;
}
