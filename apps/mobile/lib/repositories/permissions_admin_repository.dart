import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';
import '../services/auth_service.dart';

class PermissionsAdminRepository {
  SupabaseClient get _client => Supabase.instance.client;

  void _requireSuperAdmin() {
    if (!AppSession.instance.superAdmin) {
      throw StateError('Apenas o Super Admin pode gerir permissões.');
    }
  }

  Future<Map<String, Map<String, bool>>> roleMatrix() async {
    _requireSuperAdmin();
    final response = await _client
        .from('club_role_permissions')
        .select('role_key,permission_key,allowed')
        .eq('club_id', AppSession.instance.clubId);
    final result = <String, Map<String, bool>>{};
    for (final row in List<Map<String, dynamic>>.from(response)) {
      result.putIfAbsent(row['role_key'].toString(), () => <String, bool>{})[
          row['permission_key'].toString()] = row['allowed'] == true;
    }
    return result;
  }

  Future<void> setRolePermission({
    required String roleKey,
    required AppPermission permission,
    required bool allowed,
  }) async {
    _requireSuperAdmin();
    await _client.from('club_role_permissions').upsert({
      'club_id': AppSession.instance.clubId,
      'role_key': roleKey,
      'permission_key': permission.key,
      'allowed': allowed,
      'updated_by': AppSession.instance.profileId,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'club_id,role_key,permission_key');
  }

  Future<List<Map<String, dynamic>>> users() async {
    _requireSuperAdmin();
    final memberships = await _client
        .from('club_memberships')
        .select('profile_id,access_role,active')
        .eq('club_id', AppSession.instance.clubId)
        .eq('active', true);
    final rows = List<Map<String, dynamic>>.from(memberships);
    final result = <Map<String, dynamic>>[];
    for (final membership in rows) {
      final profileId = membership['profile_id'].toString();
      final profile = await _client
          .from('profiles')
          .select('full_name')
          .eq('id', profileId)
          .maybeSingle();
      result.add({
        ...membership,
        'full_name': profile?['full_name']?.toString() ?? profileId,
      });
    }
    result.sort((a, b) => a['full_name'].toString().compareTo(b['full_name'].toString()));
    return result;
  }

  Future<Map<String, bool>> userOverrides(String profileId) async {
    _requireSuperAdmin();
    final response = await _client
        .from('user_permission_overrides')
        .select('permission_key,allowed')
        .eq('club_id', AppSession.instance.clubId)
        .eq('profile_id', profileId);
    return {
      for (final row in List<Map<String, dynamic>>.from(response))
        row['permission_key'].toString(): row['allowed'] == true,
    };
  }

  Future<void> setUserOverride({
    required String profileId,
    required AppPermission permission,
    required bool? allowed,
  }) async {
    _requireSuperAdmin();
    if (allowed == null) {
      await _client
          .from('user_permission_overrides')
          .delete()
          .eq('club_id', AppSession.instance.clubId)
          .eq('profile_id', profileId)
          .eq('permission_key', permission.key);
    } else {
      await _client.from('user_permission_overrides').upsert({
        'club_id': AppSession.instance.clubId,
        'profile_id': profileId,
        'permission_key': permission.key,
        'allowed': allowed,
        'updated_by': AppSession.instance.profileId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'club_id,profile_id,permission_key');
    }
    if (profileId == AppSession.instance.profileId) {
      await AuthService.instance.refreshPermissions();
    }
  }
}
