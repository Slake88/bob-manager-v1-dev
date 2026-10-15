import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class MemberLifecycleRepository {
  MemberLifecycleRepository({SupabaseClient? client}) : _client = client;

  static const maintenanceBucket = 'member-maintenance';
  static const maxMaintenanceFileBytes = 15 * 1024 * 1024;
  static const signedUrlSeconds = 300;

  final SupabaseClient? _client;
  SupabaseClient get _supabase => _client ?? Supabase.instance.client;
  String get _clubId => AppSession.instance.clubId;

  bool canManageMember(Map<String, dynamic> member) {
    if (AppSession.instance.can(AppPermission.manageMembers)) return true;
    return AppSession.instance.can(AppPermission.editOwnMemberProfile) &&
        member['profile_id']?.toString() == AppSession.instance.profileId;
  }

  bool get canManagePatches => AppSession.instance.can(AppPermission.manageMembers);
  bool get canDeliverPatches => AppSession.instance.can(AppPermission.manageInventory);

  Future<List<Map<String, dynamic>>> motorcycles(String memberId) async {
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final response = await _supabase
        .from('member_motorcycles')
        .select()
        .eq('club_id', _clubId)
        .eq('member_id', memberId)
        .order('active', ascending: false)
        .order('primary_motorcycle', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<String> saveMotorcycle({
    required Map<String, dynamic> member,
    String? motorcycleId,
    required String brand,
    required String model,
    int? year,
    String? registration,
    String? nickname,
    String? acquiredOn,
    String? notes,
    bool primary = false,
  }) async {
    _requireMemberManagement(member);
    if (AppConfig.demoMode) return motorcycleId ?? 'demo-motorcycle';
    final response = await _supabase.rpc(
      'save_member_motorcycle_v1',
      params: {
        'target_club': _clubId,
        'p_member': member['id'].toString(),
        'p_motorcycle': motorcycleId,
        'p_brand': brand.trim(),
        'p_model': model.trim(),
        'p_year': year,
        'p_registration': _empty(registration),
        'p_nickname': _empty(nickname),
        'p_acquired_on': _empty(acquiredOn),
        'p_notes': _empty(notes),
        'p_primary': primary,
      },
    );
    return response.toString();
  }

  Future<void> archiveMotorcycle({
    required Map<String, dynamic> member,
    required String motorcycleId,
    String? retiredOn,
  }) async {
    _requireMemberManagement(member);
    if (AppConfig.demoMode) return;
    await _supabase.rpc(
      'archive_member_motorcycle_v1',
      params: {
        'target_club': _clubId,
        'p_member': member['id'].toString(),
        'p_motorcycle': motorcycleId,
        'p_retired_on': _empty(retiredOn),
      },
    );
  }

  Future<List<Map<String, dynamic>>> maintenance(
    String memberId, {
    String? motorcycleId,
  }) async {
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    var query = _supabase
        .from('maintenance_records')
        .select('*, maintenance_attachments(*)')
        .eq('club_id', _clubId)
        .eq('member_id', memberId);
    if (motorcycleId != null) {
      query = query.eq('motorcycle_id', motorcycleId);
    }
    final response = await query
        .order('service_date', ascending: false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> saveMaintenance({
    required Map<String, dynamic> member,
    required String motorcycleId,
    String? recordId,
    required String serviceDate,
    required String serviceType,
    String? description,
    int? odometerKm,
    String? workshop,
    double cost = 0,
    String? nextServiceDate,
    int? nextServiceKm,
    String? notes,
  }) async {
    _requireMemberManagement(member);
    if (serviceType.trim().isEmpty) {
      throw ArgumentError('Indica o tipo de manutenção.');
    }
    if (AppConfig.demoMode) {
      return {
        'id': recordId ?? 'demo-maintenance',
        'member_id': member['id'],
        'motorcycle_id': motorcycleId,
      };
    }
    final payload = <String, dynamic>{
      'club_id': _clubId,
      'member_id': member['id'].toString(),
      'motorcycle_id': motorcycleId,
      'service_date': serviceDate,
      'service_type': serviceType.trim(),
      'description': _empty(description),
      'odometer_km': odometerKm,
      'workshop': _empty(workshop),
      'cost': cost,
      'next_service_date': _empty(nextServiceDate),
      'next_service_km': nextServiceKm,
      'notes': _empty(notes),
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (recordId == null) {
      final response = await _supabase
          .from('maintenance_records')
          .insert({...payload, 'created_by': AppSession.instance.profileId})
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    }
    final response = await _supabase
        .from('maintenance_records')
        .update(payload)
        .eq('id', recordId)
        .eq('club_id', _clubId)
        .eq('member_id', member['id'].toString())
        .select()
        .single();
    return Map<String, dynamic>.from(response);
  }

  Future<List<Map<String, dynamic>>> uploadMaintenanceFiles({
    required Map<String, dynamic> member,
    required String maintenanceId,
    required List<PlatformFile> files,
  }) async {
    _requireMemberManagement(member);
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final saved = <Map<String, dynamic>>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Não foi possível ler ${file.name}.');
      }
      if (bytes.length > maxMaintenanceFileBytes) {
        throw StateError('${file.name} excede o limite de 15 MB.');
      }
      final mimeType = mimeTypeForName(file.name);
      if (mimeType == null) {
        throw StateError('Formato não suportado: ${file.name}.');
      }
      final path = maintenanceAttachmentPath(
        _clubId,
        member['id'].toString(),
        maintenanceId,
        DateTime.now().microsecondsSinceEpoch,
        file.name,
      );
      await _supabase.storage.from(maintenanceBucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      try {
        final response = await _supabase
            .from('maintenance_attachments')
            .insert({
              'club_id': _clubId,
              'member_id': member['id'].toString(),
              'maintenance_id': maintenanceId,
              'storage_path': path,
              'original_file_name': file.name,
              'mime_type': mimeType,
              'file_size': bytes.length,
              'created_by': AppSession.instance.profileId,
              'updated_by': AppSession.instance.profileId,
            })
            .select()
            .single();
        saved.add(Map<String, dynamic>.from(response));
      } catch (_) {
        try {
          await _supabase.storage.from(maintenanceBucket).remove([path]);
        } catch (_) {}
        rethrow;
      }
    }
    return saved;
  }

  Future<String> signedMaintenanceUrl(String storagePath) async {
    if (AppConfig.demoMode) return '';
    return _supabase.storage
        .from(maintenanceBucket)
        .createSignedUrl(storagePath, signedUrlSeconds);
  }

  Future<void> deleteMaintenanceAttachment({
    required Map<String, dynamic> member,
    required Map<String, dynamic> attachment,
  }) async {
    _requireMemberManagement(member);
    if (AppConfig.demoMode) return;
    final id = attachment['id']?.toString();
    final path = attachment['storage_path']?.toString();
    if (id == null || path == null) return;
    await _supabase
        .from('maintenance_attachments')
        .delete()
        .eq('id', id)
        .eq('club_id', _clubId)
        .eq('member_id', member['id'].toString());
    try {
      await _supabase.storage.from(maintenanceBucket).remove([path]);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> patches(String memberId) async {
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final response = await _supabase
        .from('member_patch_awards')
        .select()
        .eq('club_id', _clubId)
        .eq('member_id', memberId)
        .order('requested_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> patchCatalog() async {
    if (!canManagePatches) {
      throw StateError('Sem permissão para atribuir patches.');
    }
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final response = await _supabase.rpc(
      'member_patch_catalog_v1',
      params: {'target_club': _clubId},
    );
    if (response is! List) return <Map<String, dynamic>>[];
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> requestPatch({
    required String memberId,
    required String productId,
    String? variantId,
    String? notes,
  }) async {
    if (!canManagePatches) throw StateError('Sem permissão para atribuir patches.');
    if (AppConfig.demoMode) return;
    await _supabase.rpc('request_member_patch_v1', params: {
      'target_club': _clubId,
      'p_member': memberId,
      'p_product': productId,
      'p_variant': variantId,
      'p_notes': _empty(notes),
    });
  }

  Future<void> approvePatch(String awardId) async {
    if (!canManagePatches) throw StateError('Sem permissão para aprovar patches.');
    if (AppConfig.demoMode) return;
    await _supabase.rpc('approve_member_patch_v1', params: {
      'target_club': _clubId,
      'p_award': awardId,
    });
  }

  Future<void> cancelPatch(String awardId, {String? notes}) async {
    if (!canManagePatches) throw StateError('Sem permissão para cancelar patches.');
    if (AppConfig.demoMode) return;
    await _supabase.rpc('cancel_member_patch_v1', params: {
      'target_club': _clubId,
      'p_award': awardId,
      'p_notes': _empty(notes),
    });
  }

  Future<List<Map<String, dynamic>>> inventoryLocations() async {
    if (!canDeliverPatches) {
      throw StateError('Sem permissão de Inventário para confirmar entregas.');
    }
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final response = await _supabase
        .from('inventory_locations')
        .select('id,name,code')
        .eq('club_id', _clubId)
        .eq('active', true)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> deliverPatch({
    required String awardId,
    required String locationId,
  }) async {
    if (!canDeliverPatches) {
      throw StateError('Sem permissão de Inventário para confirmar entregas.');
    }
    if (AppConfig.demoMode) return;
    await _supabase.rpc('deliver_member_patch_v1', params: {
      'target_club': _clubId,
      'p_award': awardId,
      'p_location': locationId,
    });
  }

  Future<List<Map<String, dynamic>>> timeline(String memberId) async {
    if (AppConfig.demoMode) return <Map<String, dynamic>>[];
    final response = await _supabase
        .from('member_timeline')
        .select()
        .eq('club_id', _clubId)
        .eq('member_id', memberId)
        .order('event_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(response);
  }

  static String maintenanceAttachmentPath(
    String clubId,
    String memberId,
    String maintenanceId,
    int version,
    String fileName,
  ) {
    return '$clubId/members/$memberId/maintenance/$maintenanceId/'
        '${version}_${safeFileName(fileName)}';
  }

  static String safeFileName(String fileName) {
    final trimmed = fileName.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return trimmed.isEmpty ? 'documento' : trimmed;
  }

  static String? mimeTypeForName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return null;
  }

  static String patchStatusLabel(String status) => switch (status) {
        'pending' => 'Pendente',
        'approved' => 'Aprovado',
        'delivered' => 'Entregue',
        'cancelled' => 'Cancelado',
        _ => status,
      };

  void _requireMemberManagement(Map<String, dynamic> member) {
    if (!canManageMember(member)) {
      throw StateError('Sem permissão para gerir estes dados do membro.');
    }
  }

  static String? _empty(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
