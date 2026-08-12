import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_session.dart';
import '../core/permissions.dart';

class UserAccessRepository {
  SupabaseClient get _client => Supabase.instance.client;

  void _requireAccessManagement() {
    if (!AppSession.instance.can(AppPermission.manageUserAccess)) {
      throw StateError('Sem permissão para gerir contas e acessos.');
    }
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    _requireAccessManagement();
    final data = await _invoke('list');
    return List<Map<String, dynamic>>.from(
      data['accounts'] as List? ?? const [],
    );
  }

  Future<void> invite({
    required String memberId,
    required String email,
    required String accessRole,
  }) async {
    _requireAccessManagement();
    await _invoke(
      'invite',
      extra: {
        'member_id': memberId,
        'email': email.trim(),
        'access_role': accessRole,
      },
    );
  }

  Future<void> resendInvite(String profileId) async {
    _requireAccessManagement();
    await _invoke('resend_invite', extra: {'profile_id': profileId});
  }

  Future<void> sendPasswordReset(String profileId) async {
    _requireAccessManagement();
    final redirect = _webRedirectUrl();
    await _invoke(
      'send_password_reset',
      extra: {
        'profile_id': profileId,
        if (redirect != null) 'redirect_to': redirect,
      },
    );
  }

  Future<void> block(String profileId) async {
    _requireAccessManagement();
    await _invoke('block', extra: {'profile_id': profileId});
  }

  Future<void> unblock(String profileId) async {
    _requireAccessManagement();
    await _invoke('unblock', extra: {'profile_id': profileId});
  }

  Future<void> changeRole({
    required String profileId,
    required String accessRole,
  }) async {
    _requireAccessManagement();
    await _invoke(
      'change_role',
      extra: {'profile_id': profileId, 'access_role': accessRole},
    );
  }

  Future<Map<String, dynamic>> _invoke(
    String action, {
    Map<String, dynamic> extra = const {},
  }) async {
    final response = await _client.functions.invoke(
      'user-access-admin',
      body: {
        'action': action,
        'club_id': AppSession.instance.clubId,
        ...extra,
      },
    );
    final value = response.data;
    if (value is Map) {
      final data = Map<String, dynamic>.from(value);
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty) {
        throw StateError(_friendlyError(error));
      }
      return data;
    }
    throw StateError('Resposta inválida do serviço de gestão de acessos.');
  }

  static String _friendlyError(String error) => switch (error) {
        'user_access_permission_required' =>
          'Sem permissão para gerir contas e acessos.',
        'member_already_has_access' => 'Este membro já tem uma conta associada.',
        'email_already_registered' =>
          'Este email já está registado no BOB Manager.',
        'account_already_active' =>
          'A conta já está ativa. Usa antes a reposição de palavra-passe.',
        'super_admin_cannot_be_blocked_here' ||
        'super_admin_role_cannot_be_changed_here' =>
          'A conta Super Admin está protegida neste ecrã.',
        'auth_user_not_found' => 'A conta Auth já não existe no Supabase.',
        _ => error,
      };

  static String? _webRedirectUrl() {
    final uri = Uri.base;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.replace(path: '/', query: null, fragment: null).toString();
  }
}
