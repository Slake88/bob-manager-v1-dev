import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

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
        newRole: 'Administrador',
      );
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

  Future<void> _hydrateSession(
    String profileId, {
    required String fallbackName,
  }) async {
    final row = await Supabase.instance.client
        .from('club_memberships')
        .select('club_id, access_role, profiles(full_name)')
        .eq('profile_id', profileId)
        .eq('active', true)
        .limit(1)
        .maybeSingle();

    if (row == null) {
      throw const AuthException(
        'O utilizador não tem uma associação ativa a nenhum clube.',
      );
    }

    final clubId = row['club_id']?.toString();
    if (clubId == null || clubId.isEmpty) {
      throw const AuthException('A associação do utilizador não tem clube.');
    }

    final profile = row['profiles'];
    final fullName = profile is Map && profile['full_name'] != null
        ? profile['full_name'].toString()
        : fallbackName;

    AppSession.instance.authenticate(
      newProfileId: profileId,
      newClubId: clubId,
      newFullName: fullName,
      newRole: row['access_role']?.toString() ?? 'Membro',
    );
  }
}
