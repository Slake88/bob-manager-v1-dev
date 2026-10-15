import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  bool get needsPasswordSetup {
    if (AppConfig.demoMode) return false;
    return Supabase.instance.client.auth.currentUser?.userMetadata?['must_set_password'] == true;
  }

  Future<void> signIn(String email, String password) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Indica o email e a palavra-passe.');
    }

    if (AppConfig.demoMode) {
      if (!AppConfig.explicitDemoMode) {
        throw const AuthException(
          'A aplicação não está configurada para ligar ao Supabase.',
        );
      }
      AppSession.instance.authenticate(
        newProfileId: 'demo-profile',
        newClubId: '00000000-0000-0000-0000-000000000001',
        newFullName: 'Israel Sousa',
        newRole: 'super_admin',
      );
      AppSession.instance.applyPermissions(AppPermission.values.map((p) => p.key));
      return;
    }

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const AuthException('Não foi possível iniciar sessão.');
      }

      await _hydrateSession(user.id, fallbackName: normalizedEmail);
    } on AuthException {
      AppSession.instance.clear();
      rethrow;
    } on PostgrestException catch (error) {
      AppSession.instance.clear();
      throw AuthException(_friendlyDatabaseError(error));
    } catch (_) {
      AppSession.instance.clear();
      throw const AuthException(
        'Não foi possível concluir o login. Verifica a ligação e tenta novamente.',
      );
    }
  }

  Future<bool> restore() async {
    if (AppConfig.demoMode) {
      return false;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      AppSession.instance.clear();
      return false;
    }

    try {
      await _hydrateSession(
        user.id,
        fallbackName: user.email ?? 'Utilizador',
      );
      return true;
    } catch (_) {
      await Supabase.instance.client.auth.signOut();
      AppSession.instance.clear();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      if (!AppConfig.demoMode) {
        await Supabase.instance.client.auth.signOut();
      }
    } finally {
      AppSession.instance.clear();
    }
  }

  Future<void> sendPasswordReset(String email) async {
    if (AppConfig.demoMode) return;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthException('Indica um email válido.');
    }
    final redirectTo = _webRedirectUrl();
    await Supabase.instance.client.auth.resetPasswordForEmail(
      normalizedEmail,
      redirectTo: redirectTo,
    );
  }

  Future<void> completePasswordSetup(String password) async {
    if (AppConfig.demoMode) return;
    if (password.length < 8) {
      throw const AuthException(
        'A palavra-passe deve ter pelo menos 8 caracteres.',
      );
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw const AuthException('A sessão de ativação já não é válida.');
    }

    await Supabase.instance.client.auth.updateUser(
      UserAttributes(
        password: password,
        data: const {'must_set_password': false},
      ),
    );
    await _hydrateSession(
      user.id,
      fallbackName: user.email ?? 'Utilizador',
    );
  }

  Future<void> refreshPermissions() async {
    if (!AppSession.instance.authenticated || AppConfig.demoMode) return;
    await _hydratePermissions(
      AppSession.instance.clubId,
      AppSession.instance.profileId,
      AppSession.instance.role,
    );
  }

  Future<void> _hydrateSession(
    String profileId, {
    required String fallbackName,
  }) async {
    final membership = await Supabase.instance.client
        .from('club_memberships')
        .select('club_id, access_role')
        .eq('profile_id', profileId)
        .eq('active', true)
        .limit(1)
        .maybeSingle();

    if (membership == null) {
      throw const AuthException(
        'O utilizador não tem uma associação ativa a nenhum clube.',
      );
    }

    final clubId = membership['club_id']?.toString();
    if (clubId == null || clubId.isEmpty) {
      throw const AuthException('A associação do utilizador não tem clube.');
    }

    final profile = await Supabase.instance.client
        .from('profiles')
        .select('full_name,active')
        .eq('id', profileId)
        .maybeSingle();

    if (profile?['active'] == false) {
      throw const AuthException('O acesso deste utilizador está bloqueado.');
    }

    final fullName = profile?['full_name']?.toString().trim();
    final role = membership['access_role']?.toString() ?? 'member';

    AppSession.instance.authenticate(
      newProfileId: profileId,
      newClubId: clubId,
      newFullName: fullName == null || fullName.isEmpty ? fallbackName : fullName,
      newRole: role,
    );

    await _hydratePermissions(clubId, profileId, role);
  }

  Future<void> _hydratePermissions(
    String clubId,
    String profileId,
    String role,
  ) async {
    if (AppSession.instance.superAdmin) {
      AppSession.instance.applyPermissions(AppPermission.values.map((p) => p.key));
      return;
    }

    final values = await Future.wait([
      Supabase.instance.client
          .from('club_role_permissions')
          .select('permission_key,allowed')
          .eq('club_id', clubId)
          .eq('role_key', role),
      Supabase.instance.client
          .from('user_permission_overrides')
          .select('permission_key,allowed')
          .eq('club_id', clubId)
          .eq('profile_id', profileId),
    ]);

    final effective = <String>{};
    for (final row in List<Map<String, dynamic>>.from(values[0] as List)) {
      if (row['allowed'] == true) effective.add(row['permission_key'].toString());
    }
    for (final row in List<Map<String, dynamic>>.from(values[1] as List)) {
      final key = row['permission_key'].toString();
      if (row['allowed'] == true) {
        effective.add(key);
      } else {
        effective.remove(key);
      }
    }
    AppSession.instance.applyPermissions(effective);
  }

  static String? _webRedirectUrl() {
    final uri = Uri.base;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri.replace(path: '/', query: null, fragment: null).toString();
  }

  static String _friendlyDatabaseError(PostgrestException error) {
    if (error.code == 'PGRST200') {
      return 'A configuração de acesso do utilizador está desatualizada. '
          'Atualiza a aplicação e tenta novamente.';
    }
    return 'Não foi possível carregar a associação do utilizador ao clube.';
  }
}
