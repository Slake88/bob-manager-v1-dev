import 'app_session.dart';
import 'club_export.dart';
import 'importing.dart';
import 'module_definition.dart';
import 'permissions.dart';
import 'reporting.dart';

/// Separates navigation visibility from authorization to read module data.
class ModuleAccessPolicy {
  const ModuleAccessPolicy._();

  static bool canView(ModuleDefinition module, AppSession session) {
    if (!session.authenticated) return false;

    return switch (module.code) {
      'dashboard' => session.can(AppPermission.viewDashboard),
      'activity' => session.can(AppPermission.viewActivity),
      'financial' => session.can(AppPermission.viewFinancialRequests),
      'weekly_officer' => session.can(AppPermission.viewWeeklyOfficer),
      'agenda' => session.can(AppPermission.viewAgenda),
      'members' => session.can(AppPermission.viewMembers),
      'treasury' => session.can(AppPermission.viewTreasury),
      'fees' => session.can(AppPermission.viewFees),
      'lottery' => session.can(AppPermission.viewLottery),
      'events' => session.can(AppPermission.viewEvents),
      'bar' => session.can(AppPermission.viewBar),
      'inventory' => session.can(AppPermission.viewInventory),
      'documents' => session.can(AppPermission.viewDocuments),
      'communication' => session.can(AppPermission.viewCommunication),
      'reports' => ReportCatalog.canOpenCenter(session.can) ||
          ClubExportPolicy.canExport(session) ||
          ImportCatalog.canOpen(session),
      'settings' => session.can(AppPermission.manageSettings) ||
          session.can(AppPermission.manageUserAccess),
      'emergency' => session.can(AppPermission.viewEmergencyData),
      _ => false,
    };
  }
}
