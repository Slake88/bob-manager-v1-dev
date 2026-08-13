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
  manageTreasuryPlanning,
  manageCashSessions,
  approveCashDifferences,
  reverseTreasuryMovement,
  viewFees,
  manageFees,
  viewLottery,
  manageLottery,
  viewEvents,
  manageEvents,
  manageEventParticipants,
  viewInventory,
  manageInventory,
  sellInventory,
  manageMerchandising,
  manageBar,
  selectBarFinancialAccount,
  manageAssets,
  performInventoryCount,
  viewDocuments,
  viewSensitiveDocuments,
  manageDocuments,
  viewCommunication,
  manageCommunication,
  acknowledgeCommunication,
  manageImports,
  manageUserAccess,
  manageSettings,
}

extension AppPermissionMeta on AppPermission {
  String get key => name;

  String get module => switch (this) {
        AppPermission.viewMembers ||
        AppPermission.editOwnMemberProfile ||
        AppPermission.manageMembers => 'Membros',
        AppPermission.viewEmergencyData => 'Emergência',
        AppPermission.viewTreasury ||
        AppPermission.createTreasuryMovement ||
        AppPermission.transferBetweenAccounts ||
        AppPermission.manageFinancialAccounts ||
        AppPermission.approveExpenseRequests ||
        AppPermission.viewFinancialReports ||
        AppPermission.manageTreasuryPlanning ||
        AppPermission.manageCashSessions ||
        AppPermission.approveCashDifferences ||
        AppPermission.reverseTreasuryMovement => 'Tesouraria',
        AppPermission.viewFees || AppPermission.manageFees => 'Quotas',
        AppPermission.viewLottery || AppPermission.manageLottery => 'Euromilhões',
        AppPermission.viewEvents ||
        AppPermission.manageEvents ||
        AppPermission.manageEventParticipants => 'Eventos',
        AppPermission.viewInventory ||
        AppPermission.manageInventory ||
        AppPermission.sellInventory ||
        AppPermission.manageMerchandising ||
        AppPermission.manageBar ||
        AppPermission.selectBarFinancialAccount ||
        AppPermission.manageAssets ||
        AppPermission.performInventoryCount => 'Património & Inventário',
        AppPermission.viewDocuments ||
        AppPermission.viewSensitiveDocuments ||
        AppPermission.manageDocuments => 'Documentos',
        AppPermission.viewCommunication ||
        AppPermission.manageCommunication ||
        AppPermission.acknowledgeCommunication => 'Comunicação',
        AppPermission.manageImports ||
        AppPermission.manageUserAccess ||
        AppPermission.manageSettings => 'Administração',
      };

  String get label => switch (this) {
        AppPermission.viewMembers => 'Ver membros',
        AppPermission.editOwnMemberProfile => 'Editar o próprio perfil',
        AppPermission.manageMembers => 'Criar e editar membros',
        AppPermission.viewEmergencyData => 'Ver dados de emergência',
        AppPermission.viewTreasury => 'Ver tesouraria',
        AppPermission.createTreasuryMovement => 'Criar receitas e despesas',
        AppPermission.transferBetweenAccounts => 'Transferir entre contas',
        AppPermission.manageFinancialAccounts => 'Gerir contas e centros de custo',
        AppPermission.approveExpenseRequests => 'Aprovar pedidos de despesa',
        AppPermission.viewFinancialReports => 'Ver relatórios financeiros',
        AppPermission.manageTreasuryPlanning => 'Gerir planeamento financeiro',
        AppPermission.manageCashSessions => 'Gerir sessões de caixa',
        AppPermission.approveCashDifferences => 'Aprovar diferenças de caixa',
        AppPermission.reverseTreasuryMovement => 'Reverter movimentos de tesouraria',
        AppPermission.viewFees => 'Ver quotas',
        AppPermission.manageFees => 'Gerir quotas e pagamentos',
        AppPermission.viewLottery => 'Ver Euromilhões',
        AppPermission.manageLottery => 'Gerir Euromilhões e pagamentos',
        AppPermission.viewEvents => 'Ver eventos',
        AppPermission.manageEvents => 'Criar e editar eventos',
        AppPermission.manageEventParticipants => 'Gerir participantes e voluntários',
        AppPermission.viewInventory => 'Ver Património & Inventário',
        AppPermission.manageInventory => 'Gerir inventário geral',
        AppPermission.sellInventory => 'Registar vendas',
        AppPermission.manageMerchandising => 'Gerir Loja e merchandising',
        AppPermission.manageBar => 'Gerir Bar e consumíveis',
        AppPermission.selectBarFinancialAccount => 'Escolher conta financeira do Bar',
        AppPermission.manageAssets => 'Gerir património e equipamentos',
        AppPermission.performInventoryCount => 'Realizar inventário físico',
        AppPermission.viewDocuments => 'Ver documentos',
        AppPermission.viewSensitiveDocuments => 'Ver documentos sensíveis',
        AppPermission.manageDocuments => 'Gerir documentos',
        AppPermission.viewCommunication => 'Ver comunicação',
        AppPermission.manageCommunication => 'Gerir comunicação',
        AppPermission.acknowledgeCommunication => 'Confirmar leitura',
        AppPermission.manageImports => 'Importar dados por ficheiro',
        AppPermission.manageUserAccess => 'Gerir contas e acessos de utilizadores',
        AppPermission.manageSettings => 'Gerir configurações',
      };
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
      AppPermission.manageEventParticipants =>
        role == AppRole.secretary ||
        role == AppRole.roadCaptain ||
        role == AppRole.eventsManager,
      AppPermission.viewInventory => role != AppRole.unknown,
      AppPermission.manageInventory ||
      AppPermission.manageMerchandising ||
      AppPermission.manageBar ||
      AppPermission.manageAssets ||
      AppPermission.performInventoryCount => role == AppRole.inventoryManager,
      AppPermission.selectBarFinancialAccount =>
        role == AppRole.president || role == AppRole.treasurer,
      AppPermission.sellInventory =>
        role == AppRole.inventoryManager || role == AppRole.treasurer,
      AppPermission.viewDocuments => role != AppRole.unknown,
      AppPermission.viewSensitiveDocuments =>
        role == AppRole.secretary || role == AppRole.treasurer,
      AppPermission.manageDocuments => role == AppRole.secretary,
      AppPermission.viewCommunication => role != AppRole.unknown,
      AppPermission.manageCommunication => role == AppRole.secretary,
      AppPermission.acknowledgeCommunication => role != AppRole.unknown,
      AppPermission.manageMembers => role == AppRole.secretary,
      AppPermission.manageFinancialAccounts ||
      AppPermission.manageImports ||
      AppPermission.manageUserAccess ||
      AppPermission.manageSettings => false,
    };
  }

  static const Set<AppRole> _legacyFullAccessRoles = {
    AppRole.president,
    AppRole.vicePresident,
    AppRole.administrator,
  };
}
