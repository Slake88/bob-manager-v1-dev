import 'app_role.dart';

enum AppPermission {
  viewMembers,
  editOwnMemberProfile,
  manageMembers,
  viewEmergencyData,
  viewTreasury,
  createTreasuryMovement,
  transferBetweenAccounts,
  manageFinancialAccounts,
  approveExpenseRequests,
  viewFinancialReports,
  viewFees,
  manageFees,
  viewLottery,
  manageLottery,
  viewEvents,
  manageEvents,
  manageEventParticipants,
  manageSettings,
}

class PermissionPolicy {
  const PermissionPolicy._();

  static bool allows(AppRole role, AppPermission permission) {
    if (_fullAccessRoles.contains(role)) {
      return true;
    }

    return switch (permission) {
      AppPermission.viewMembers => role != AppRole.unknown,
      AppPermission.editOwnMemberProfile => role != AppRole.unknown,
      AppPermission.viewEmergencyData => role != AppRole.unknown,
      AppPermission.viewTreasury => role == AppRole.treasurer,
      AppPermission.createTreasuryMovement => role == AppRole.treasurer,
      AppPermission.transferBetweenAccounts => role == AppRole.treasurer,
      AppPermission.approveExpenseRequests => role == AppRole.treasurer,
      AppPermission.viewFinancialReports => role == AppRole.treasurer,
      AppPermission.viewFees =>
        role == AppRole.treasurer || role == AppRole.secretary,
      AppPermission.manageFees =>
        role == AppRole.treasurer || role == AppRole.secretary,
      AppPermission.viewLottery => role != AppRole.unknown,
      AppPermission.manageLottery => role == AppRole.treasurer,
      AppPermission.viewEvents => role != AppRole.unknown,
      AppPermission.manageEvents => role == AppRole.secretary,
      AppPermission.manageEventParticipants =>
        role == AppRole.secretary || role == AppRole.roadCaptain,
      AppPermission.manageMembers => role == AppRole.secretary,
      AppPermission.manageFinancialAccounts || AppPermission.manageSettings =>
        false,
    };
  }

  static const Set<AppRole> _fullAccessRoles = {
    AppRole.president,
    AppRole.vicePresident,
    AppRole.administrator,
  };
}
