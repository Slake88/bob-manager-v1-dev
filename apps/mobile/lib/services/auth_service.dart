import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../core/app_session.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  Future<void> signIn(String email, String password) async {
    if (AppConfig.demoMode) {
      AppSession.instance.authenticate(
        newProfileId: 'demo-profile',
        newClubId: '00000000-0000-0000-0000-000000000001',
        newFullName: 'Israel Sousa',
        newRole: 'Administrador',
      );
      return;
    }

    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Falha no login.');
    }

    await _hydrateSession(user.id, fallbackName: email);
  }

  Future<bool> restore() async {
    if (AppConfig.demoMode) {
      return false;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return false;
    }

    await _hydrateSession(
      user.id,
      fallbackName: user.email ?? 'Utilizador',
    );
    return true;
  }

  Future<void> signOut() async {
    if (!AppConfig.demoMode) {
      await Supabase.instance.client.auth.signOut();
    }
    AppSession.instance.clear();
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
        .single();

    final profile = row['profiles'];
    final fullName = profile is Map && profile['full_name'] != null
        ? profile['full_name'].toString()
        : fallbackName;

    AppSession.instance.authenticate(
      newProfileId: profileId,
      newClubId: row['club_id'].toString(),
      newFullName: fullName,
      newRole: row['access_role']?.toString() ?? 'Membro',
    );
  }
}
