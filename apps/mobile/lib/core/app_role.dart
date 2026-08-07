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
      'presidente' || 'president' => AppRole.president,
      'vice presidente' || 'vice president' => AppRole.vicePresident,
      'super admin' ||
      'super administrador' ||
      'administrador' ||
      'administrator' ||
      'admin' => AppRole.administrator,
      'tesoureiro' || 'treasurer' => AppRole.treasurer,
      'secretario' || 'secretary' => AppRole.secretary,
      'road captain' => AppRole.roadCaptain,
      'responsavel inventario' ||
      'responsavel de inventario' ||
      'inventory manager' => AppRole.inventoryManager,
      'responsavel eventos' ||
      'responsavel de eventos' ||
      'events manager' => AppRole.eventsManager,
      'responsavel euromilhoes' ||
      'responsavel de euromilhoes' ||
      'euromillions manager' => AppRole.euromillionsManager,
      'prospect' => AppRole.prospect,
      'membro' || 'member' => AppRole.member,
      _ => AppRole.unknown,
    };
  }
}
