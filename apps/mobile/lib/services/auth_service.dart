import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';
import '../core/permissions.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  static const _networkTimeout = Duration(seconds: 25);

  int _operationGeneration = 0;

  bool get needsPasswordSetup {
    if (AppConfig.demoMode) return false;
    return Supabase.instance.client.auth.currentUser
            ?.userMetadata?['must_set_password'] ==
        true;
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
      AppSession.instance
          .applyPermissions(AppPermission.values.map((p) => p.key));
      return;
    }

    final generation = ++_operationGeneration;
    var authSessionCreated = false;
    try {
      final response = await Supabase.instance.client.auth
          .signInWithPassword(
            email: normalizedEmail,
            password: password,
          )
          .timeout(_networkTimeout);
      final user = response.user;
      if (user == null) {
        throw const AuthException('Não foi possível iniciar sessão.');
      }

      authSessionCreated = true;
      await _hydrateSession(
        user.id,
        fallbackName: normalizedEmail,
        generation: generation,
      ).timeout(_networkTimeout);
    } on TimeoutException {
      // A Future timeout does not cancel the HTTP request. Invalidate this
      // hydration so a late response cannot authenticate a stale screen.
      // Keep the Supabase session untouched: the server may have accepted the
      // login even if its response was delayed.
      ++_operationGeneration;
      AppSession.instance.clear();
      throw const AuthException(
        'A ligação demorou mais do que o esperado. Verifica a ligação e tenta novamente.',
      );
    } on AuthException {
      ++_operationGeneration;
      if (authSessionCreated) {
        await _bestEffortSignOut();
      }
      AppSession.instance.clear();
      rethrow;
    } on PostgrestException catch (error) {
      ++_operationGeneration;
      if (authSessionCreated) {
        await _bestEffortSignOut();
      }
      AppSession.instance.clear();
      throw AuthException(_friendlyDatabaseError(error));
    } catch (_) {
      ++_operationGeneration;
      if (authSessionCreated) {
        await _bestEffortSignOut();
      }
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

    final generation = ++_operationGeneration;
    try {
      await _hydrateSession(
        user.id,
        fallbackName: user.email ?? 'Utilizador',
        generation: generation,
      ).timeout(_networkTimeout);
      return true;
    } on AuthException {
      // Missing/inactive membership is a definitive authorization failure.
      // Transient database/network errors are deliberately not converted into
      // a logout; the bootstrap screen offers a bounded retry instead.
      await _bestEffortSignOut();
      AppSession.instance.clear();
      return false;
    } on TimeoutException {
      ++_operationGeneration;
      AppSession.instance.clear();
      rethrow;
    } catch (_) {
      ++_operationGeneration;
      AppSession.instance.clear();
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      if (!AppConfig.demoMode) {
        await Supabase.instance.client.auth.signOut().timeout(_networkTimeout);
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
    await Supabase.instance.client.auth
        .resetPasswordForEmail(
          normalizedEmail,
          redirectTo: redirectTo,
        )
        .timeout(_networkTimeout);
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

    await Supabase.instance.client.auth
        .updateUser(
          UserAttributes(
            password: password,
            data: const {'must_set_password': false},
          ),
        )
        .timeout(_networkTimeout);
    await _hydrateSession(
      user.id,
      fallbackName: user.email ?? 'Utilizador',
      generation: _operationGeneration,
    ).timeout(_networkTimeout);
  }

  Future<void> refreshPermissions() async {
    if (!AppSession.instance.authenticated || AppConfig.demoMode) return;
    final clubId = AppSession.instance.clubId;
    final profileId = AppSession.instance.profileId;
    final role = AppSession.instance.role;
    final generation = _operationGeneration;
    final permissions = await _loadPermissions(
      clubId,
      profileId,
      role,
    ).timeout(_networkTimeout);
    if (generation == _operationGeneration &&
        AppSession.instance.authenticated &&
        AppSession.instance.clubId == clubId &&
        AppSession.instance.profileId == profileId) {
      AppSession.instance.applyPermissions(permissions);
    }
  }

  Future<void> _hydrateSession(
    String profileId, {
    required String fallbackName,
    required int generation,
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

    if (generation != _operationGeneration) return;

    final permissions = await _loadPermissions(clubId, profileId, role);
    if (generation != _operationGeneration) return;

    AppSession.instance.authenticate(
      newProfileId: profileId,
      newClubId: clubId,
      newFullName:
          fullName == null || fullName.isEmpty ? fallbackName : fullName,
      newRole: role,
    );

    AppSession.instance.applyPermissions(permissions);
  }

  Future<void> _bestEffortSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut().timeout(_networkTimeout);
    } catch (_) {
      // Do not keep the UI blocked while a best-effort cleanup is pending.
    }
  }

  Future<Set<String>> _loadPermissions(
    String clubId,
    String profileId,
    String role,
  ) async {
    if (role.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_') ==
        'super_admin') {
      return AppPermission.values.map((p) => p.key).toSet();
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

    return resolveEffectivePermissionKeys(
      roleKey: role,
      roleRows: List<Map<String, dynamic>>.from(values[0] as List),
      userOverrides: List<Map<String, dynamic>>.from(values[1] as List),
    );
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
