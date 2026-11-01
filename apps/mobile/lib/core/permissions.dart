import 'app_role.dart';

enum AppPermission {
  viewDashboard,
  viewActivity,
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
  manageTreasuryPlanning,
  manageCashSessions,
  approveCashDifferences,
  reverseTreasuryMovement,
  viewFinancialRequests,
  manageOwnFinancialRequests,
  viewFees,
  manageFees,
  viewLottery,
  manageLottery,
  viewEvents,
  manageEvents,
  manageEventParticipants,
  proposeEvents,
  approveEventProposals,
  manageEventRoadbook,
  manageEventOperations,
  manageRockRide,
  manageEventFinance,
  viewBar,
  manageBar,
  selectBarFinancialAccount,
  viewInventory,
  manageInventory,
  sellInventory,
  manageMerchandising,
  manageAssets,
  performInventoryCount,
  viewDocuments,
  viewSensitiveDocuments,
  manageDocuments,
  approveDocuments,
  runDocumentOcr,
  manageEventGallery,
  manageAnnualBooks,
  viewCommunication,
  manageCommunication,
  acknowledgeCommunication,
  viewWeeklyOfficer,
  manageWeeklyOfficer,
  viewAgenda,
  viewDirectionAgenda,
  manageAgenda,
  manageImports,
  manageUserAccess,
  manageSettings,
}

extension AppPermissionMeta on AppPermission {
  String get key => name;

  static const Set<String> _knownMembershipRoleKeys = {
    'president',
    'vice_president',
    'admin',
    'administrator',
    'treasurer',
    'secretary',
    'road_captain',
    'sergeant_at_arms',
    'inventory_manager',
    'event_manager',
    'events_manager',
    'euromillions_manager',
    'prospect',
    'member',
    'super_admin',
    // Values accepted by AppRole.fromValue in Portuguese installations.
    'presidente',
    'vice_presidente',
    'administrador',
    'tesoureiro',
    'secretario',
    'responsavel_de_inventario',
    'responsavel_inventario',
    'responsavel_de_eventos',
    'responsavel_eventos',
    'responsavel_euromilhoes',
    'sargento_de_armas',
    'sargento_armas',
    'full_color',
  };

  bool? defaultAllowedForRole(String roleKey) {
    final role =
        roleKey.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (this) {
      AppPermission.viewDashboard ||
      AppPermission.viewActivity ||
      AppPermission.viewFinancialRequests ||
      AppPermission.manageOwnFinancialRequests ||
      AppPermission.viewWeeklyOfficer ||
      AppPermission.viewAgenda =>
        _knownMembershipRoleKeys.contains(role),
      AppPermission.viewDirectionAgenda => const {
          'president',
          'vice_president',
          'secretary',
          'treasurer',
          'admin',
          'administrator',
          'super_admin',
        }.contains(role),
      AppPermission.manageAgenda => const {
          'president',
          'vice_president',
          'secretary',
          'admin',
          'administrator',
        }.contains(role),
      AppPermission.manageWeeklyOfficer => const {
          'president',
          'vice_president',
          'super_admin',
        }.contains(role),
      _ => null,
    };
  }

  String get module => switch (this) {
        AppPermission.viewDashboard => 'Dashboard',
        AppPermission.viewActivity => 'Atividade',
        AppPermission.viewMembers ||
        AppPermission.editOwnMemberProfile ||
        AppPermission.manageMembers =>
          'Membros',
        AppPermission.viewEmergencyData => 'Emergência',
        AppPermission.viewTreasury ||
        AppPermission.createTreasuryMovement ||
        AppPermission.transferBetweenAccounts ||
        AppPermission.manageFinancialAccounts ||
        AppPermission.viewFinancialReports ||
        AppPermission.manageTreasuryPlanning ||
        AppPermission.manageCashSessions ||
        AppPermission.approveCashDifferences ||
        AppPermission.reverseTreasuryMovement =>
          'Tesouraria',
        AppPermission.viewFinancialRequests ||
        AppPermission.manageOwnFinancialRequests ||
        AppPermission.approveExpenseRequests =>
          'Pedidos & Pagamentos',
        AppPermission.viewFees || AppPermission.manageFees => 'Quotas',
        AppPermission.viewLottery ||
        AppPermission.manageLottery =>
          'Euromilhões',
        AppPermission.viewEvents ||
        AppPermission.manageEvents ||
        AppPermission.manageEventParticipants ||
        AppPermission.proposeEvents ||
        AppPermission.approveEventProposals ||
        AppPermission.manageEventRoadbook ||
        AppPermission.manageEventOperations ||
        AppPermission.manageRockRide ||
        AppPermission.manageEventFinance =>
          'Eventos',
        AppPermission.viewBar ||
        AppPermission.manageBar ||
        AppPermission.selectBarFinancialAccount =>
          'Bar',
        AppPermission.viewInventory ||
        AppPermission.manageInventory ||
        AppPermission.sellInventory ||
        AppPermission.manageMerchandising ||
        AppPermission.manageAssets ||
        AppPermission.performInventoryCount =>
          'Património & Inventário',
        AppPermission.viewDocuments ||
        AppPermission.viewSensitiveDocuments ||
        AppPermission.manageDocuments ||
        AppPermission.approveDocuments ||
        AppPermission.runDocumentOcr ||
        AppPermission.manageEventGallery ||
        AppPermission.manageAnnualBooks =>
          'Documentos',
        AppPermission.viewCommunication ||
        AppPermission.manageCommunication ||
        AppPermission.acknowledgeCommunication =>
          'Comunicação',
        AppPermission.viewWeeklyOfficer ||
        AppPermission.manageWeeklyOfficer =>
          'Oficial da Semana',
        AppPermission.viewAgenda ||
        AppPermission.viewDirectionAgenda ||
        AppPermission.manageAgenda =>
          'Agenda',
        AppPermission.manageImports ||
        AppPermission.manageUserAccess ||
        AppPermission.manageSettings =>
          'Administração',
      };

  String get label => switch (this) {
        AppPermission.viewDashboard => 'Consultar Dashboard',
        AppPermission.viewActivity => 'Consultar atividade',
        AppPermission.viewMembers => 'Ver membros',
        AppPermission.editOwnMemberProfile => 'Editar o próprio perfil',
        AppPermission.manageMembers => 'Criar e editar membros',
        AppPermission.viewEmergencyData => 'Ver dados de emergência',
        AppPermission.viewTreasury => 'Ver tesouraria',
        AppPermission.createTreasuryMovement => 'Criar receitas e despesas',
        AppPermission.transferBetweenAccounts => 'Transferir entre contas',
        AppPermission.manageFinancialAccounts =>
          'Gerir contas e centros de custo',
        AppPermission.approveExpenseRequests => 'Aprovar pedidos de despesa',
        AppPermission.viewFinancialReports => 'Ver relatórios financeiros',
        AppPermission.manageTreasuryPlanning => 'Gerir planeamento financeiro',
        AppPermission.manageCashSessions => 'Gerir sessões de caixa',
        AppPermission.approveCashDifferences => 'Aprovar diferenças de caixa',
        AppPermission.reverseTreasuryMovement =>
          'Reverter movimentos de tesouraria',
        AppPermission.viewFinancialRequests => 'Consultar pedidos e pagamentos',
        AppPermission.manageOwnFinancialRequests =>
          'Criar e gerir os próprios pedidos',
        AppPermission.viewFees => 'Ver quotas',
        AppPermission.manageFees => 'Gerir quotas e pagamentos',
        AppPermission.viewLottery => 'Ver Euromilhões',
        AppPermission.manageLottery => 'Gerir Euromilhões e pagamentos',
        AppPermission.viewEvents => 'Ver eventos',
        AppPermission.manageEvents => 'Criar e editar eventos',
        AppPermission.manageEventParticipants =>
          'Gerir participantes e voluntários',
        AppPermission.proposeEvents => 'Propor eventos',
        AppPermission.approveEventProposals => 'Aprovar propostas de eventos',
        AppPermission.manageEventRoadbook => 'Gerir roadbook de eventos',
        AppPermission.manageEventOperations => 'Gerir operação de eventos',
        AppPermission.manageRockRide => 'Gerir Rock & Ride In',
        AppPermission.manageEventFinance => 'Gerir área financeira de eventos',
        AppPermission.viewBar => 'Ver Bar',
        AppPermission.manageBar => 'Gerir Bar, stock e vendas',
        AppPermission.selectBarFinancialAccount =>
          'Escolher conta financeira do Bar',
        AppPermission.viewInventory => 'Ver Património & Inventário',
        AppPermission.manageInventory => 'Gerir inventário geral',
        AppPermission.sellInventory => 'Registar vendas',
        AppPermission.manageMerchandising => 'Gerir Loja e merchandising',
        AppPermission.manageAssets => 'Gerir património e equipamentos',
        AppPermission.performInventoryCount => 'Realizar inventário físico',
        AppPermission.viewDocuments => 'Ver documentos',
        AppPermission.viewSensitiveDocuments => 'Ver documentos sensíveis',
        AppPermission.manageDocuments => 'Gerir documentos',
        AppPermission.approveDocuments => 'Aprovar documentos',
        AppPermission.runDocumentOcr => 'Executar OCR documental',
        AppPermission.manageEventGallery => 'Gerir galeria de eventos',
        AppPermission.manageAnnualBooks => 'Gerir Livro anual',
        AppPermission.viewCommunication => 'Ver comunicação',
        AppPermission.manageCommunication => 'Gerir comunicação',
        AppPermission.acknowledgeCommunication => 'Confirmar leitura',
        AppPermission.viewWeeklyOfficer => 'Consultar Oficial da Semana',
        AppPermission.manageWeeklyOfficer => 'Gerir Oficial da Semana',
        AppPermission.viewAgenda => 'Consultar Agenda',
        AppPermission.viewDirectionAgenda => 'Ver itens da Direção na Agenda',
        AppPermission.manageAgenda => 'Gerir Agenda',
        AppPermission.manageImports => 'Importar dados por ficheiro',
        AppPermission.manageUserAccess =>
          'Gerir contas e acessos de utilizadores',
        AppPermission.manageSettings => 'Gerir configurações',
      };
}

Set<String> resolveEffectivePermissionKeys({
  required String roleKey,
  required Iterable<Map<String, dynamic>> roleRows,
  required Iterable<Map<String, dynamic>> userOverrides,
}) {
  final roleValues = <String, bool>{
    for (final row in roleRows)
      row['permission_key'].toString(): row['allowed'] == true,
  };
  final effective = <String>{};
  for (final permission in AppPermission.values) {
    final configured = roleValues[permission.key];
    if (configured ?? permission.defaultAllowedForRole(roleKey) ?? false) {
      effective.add(permission.key);
    }
  }
  for (final row in userOverrides) {
    final key = row['permission_key'].toString();
    if (row['allowed'] == true) {
      effective.add(key);
    } else {
      effective.remove(key);
    }
  }
  return effective;
}

class PermissionPolicy {
  const PermissionPolicy._();

  static Set<AppPermission>? _effectivePermissions;
  static bool _superAdmin = false;

  static void configure({
    required Iterable<String> permissionKeys,
    required bool superAdmin,
  }) {
    _superAdmin = superAdmin;
    _effectivePermissions = permissionKeys
        .map((key) {
          for (final permission in AppPermission.values) {
            if (permission.key == key) return permission;
          }
          return null;
        })
        .whereType<AppPermission>()
        .toSet();
  }

  static void reset() {
    _effectivePermissions = null;
    _superAdmin = false;
  }

  static bool allows(AppRole role, AppPermission permission) {
    if (_superAdmin) return true;
    final effective = _effectivePermissions;
    if (effective != null) return effective.contains(permission);

    if (_legacyFullAccessRoles.contains(role)) return true;
    return switch (permission) {
      AppPermission.viewDashboard ||
      AppPermission.viewActivity ||
      AppPermission.viewFinancialRequests ||
      AppPermission.viewWeeklyOfficer ||
      AppPermission.viewAgenda ||
      AppPermission.manageOwnFinancialRequests =>
        role != AppRole.unknown,
      AppPermission.viewDirectionAgenda =>
        role == AppRole.secretary || role == AppRole.treasurer,
      AppPermission.manageWeeklyOfficer =>
        role == AppRole.president || role == AppRole.vicePresident,
      AppPermission.manageAgenda => role == AppRole.president ||
          role == AppRole.vicePresident ||
          role == AppRole.secretary,
      AppPermission.viewMembers => role != AppRole.unknown,
      AppPermission.editOwnMemberProfile => role != AppRole.unknown,
      AppPermission.viewEmergencyData => role != AppRole.unknown,
      AppPermission.viewTreasury => role == AppRole.treasurer,
      AppPermission.createTreasuryMovement => role == AppRole.treasurer,
      AppPermission.transferBetweenAccounts => role == AppRole.treasurer,
      AppPermission.approveExpenseRequests => role == AppRole.treasurer,
      AppPermission.viewFinancialReports => role == AppRole.treasurer,
      AppPermission.manageTreasuryPlanning => role == AppRole.treasurer,
      AppPermission.manageCashSessions => role == AppRole.treasurer,
      AppPermission.approveCashDifferences => false,
      AppPermission.reverseTreasuryMovement => role == AppRole.treasurer,
      AppPermission.viewFees => role != AppRole.unknown,
      AppPermission.manageFees =>
        role == AppRole.treasurer || role == AppRole.secretary,
      AppPermission.viewLottery => role != AppRole.unknown,
      AppPermission.manageLottery =>
        role == AppRole.treasurer || role == AppRole.euromillionsManager,
      AppPermission.viewEvents => role != AppRole.unknown,
      AppPermission.manageEvents =>
        role == AppRole.secretary || role == AppRole.eventsManager,
      AppPermission.manageEventParticipants => role == AppRole.secretary ||
          role == AppRole.roadCaptain ||
          role == AppRole.eventsManager,
      AppPermission.proposeEvents => role != AppRole.unknown,
      AppPermission.approveEventProposals =>
        role == AppRole.secretary || role == AppRole.treasurer,
      AppPermission.manageEventRoadbook ||
      AppPermission.manageEventOperations =>
        role == AppRole.secretary ||
            role == AppRole.roadCaptain ||
            role == AppRole.eventsManager,
      AppPermission.manageRockRide =>
        role == AppRole.secretary || role == AppRole.eventsManager,
      AppPermission.manageEventFinance =>
        role == AppRole.treasurer || role == AppRole.eventsManager,
      AppPermission.viewBar => role != AppRole.unknown,
      AppPermission.manageBar => role == AppRole.inventoryManager,
      AppPermission.selectBarFinancialAccount =>
        role == AppRole.president || role == AppRole.treasurer,
      AppPermission.viewInventory => role != AppRole.unknown,
      AppPermission.manageInventory ||
      AppPermission.manageMerchandising ||
      AppPermission.manageAssets ||
      AppPermission.performInventoryCount =>
        role == AppRole.inventoryManager,
      AppPermission.sellInventory =>
        role == AppRole.inventoryManager || role == AppRole.treasurer,
      AppPermission.viewDocuments => role != AppRole.unknown,
      AppPermission.viewSensitiveDocuments =>
        role == AppRole.secretary || role == AppRole.treasurer,
      AppPermission.manageDocuments => role == AppRole.secretary,
      AppPermission.approveDocuments => role == AppRole.secretary,
      AppPermission.runDocumentOcr => role == AppRole.secretary,
      AppPermission.manageEventGallery =>
        role == AppRole.secretary || role == AppRole.eventsManager,
      AppPermission.manageAnnualBooks => role == AppRole.secretary,
      AppPermission.viewCommunication => role != AppRole.unknown,
      AppPermission.manageCommunication => role == AppRole.secretary,
      AppPermission.acknowledgeCommunication => role != AppRole.unknown,
      AppPermission.manageMembers => role == AppRole.secretary,
      AppPermission.manageFinancialAccounts ||
      AppPermission.manageImports ||
      AppPermission.manageUserAccess ||
      AppPermission.manageSettings =>
        false,
    };
  }

  static const Set<AppRole> _legacyFullAccessRoles = {
    AppRole.president,
    AppRole.vicePresident,
    AppRole.administrator,
  };
}
