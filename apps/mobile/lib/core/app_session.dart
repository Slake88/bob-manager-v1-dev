import 'app_role.dart';
import 'permissions.dart';

class AppSession {
  AppSession._();

  static final AppSession instance = AppSession._();

  String clubId = '00000000-0000-0000-0000-000000000001';
  String profileId = 'demo-profile';
  String fullName = 'Administração Blue On Black';
  String role = 'Administrador';
  bool authenticated = false;

  AppRole get currentRole => AppRole.fromValue(role);

  bool can(AppPermission permission) {
    return PermissionPolicy.allows(currentRole, permission);
  }

  void authenticate({
    required String newProfileId,
    required String newClubId,
    required String newFullName,
    required String newRole,
  }) {
    profileId = newProfileId;
    clubId = newClubId;
    fullName = newFullName;
    role = newRole;
    authenticated = true;
  }

  void clear() {
    profileId = 'demo-profile';
    clubId = '00000000-0000-0000-0000-000000000001';
    fullName = 'Administração Blue On Black';
    role = 'Administrador';
    authenticated = false;
  }
}
