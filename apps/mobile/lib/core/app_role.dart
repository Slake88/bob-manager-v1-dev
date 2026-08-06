enum AppRole {
  president,
  vicePresident,
  administrator,
  treasurer,
  secretary,
  roadCaptain,
  inventoryManager,
  eventsManager,
  euromillionsManager,
  prospect,
  member,
  unknown;

  static AppRole fromValue(String? value) {
    final normalized = (value ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');

    return switch (normalized) {
      'presidente' => AppRole.president,
      'vice presidente' => AppRole.vicePresident,
      'super admin' ||
      'super administrador' ||
      'administrador' ||
      'administrator' => AppRole.administrator,
      'tesoureiro' => AppRole.treasurer,
      'secretario' => AppRole.secretary,
      'road captain' => AppRole.roadCaptain,
      'responsavel inventario' || 'responsavel de inventario' =>
        AppRole.inventoryManager,
      'responsavel eventos' || 'responsavel de eventos' =>
        AppRole.eventsManager,
      'responsavel euromilhoes' || 'responsavel de euromilhoes' =>
        AppRole.euromillionsManager,
      'prospect' => AppRole.prospect,
      'membro' || 'member' => AppRole.member,
      _ => AppRole.unknown,
    };
  }
}
