class WeeklyOfficerRules {
  const WeeklyOfficerRules._();

  static String normalizeRole(String? value) {
    return (value ?? '')
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
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static bool canManageRole(String? role, {bool superAdmin = false}) {
    if (superAdmin) return true;
    final normalized = normalizeRole(role);
    return normalized == 'super_admin' ||
        normalized == 'presidente' ||
        normalized == 'president' ||
        normalized == 'vice_presidente' ||
        normalized == 'vice_president';
  }

  static bool countsAsOfficialDinner(Map<String, dynamic> row) {
    final kind = row['dinner_kind']?.toString() ?? '';
    final status = row['status']?.toString() ?? '';
    return kind == 'regular' &&
        (status == 'planned' || status == 'completed') &&
        row['assigned_member_id'] != null;
  }

  static List<Map<String, dynamic>> sortDinnersNearestFirst(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final result = rows.toList(growable: false);
    result.sort((a, b) {
      final aDate = DateTime.tryParse(a['dinner_date']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['dinner_date']?.toString() ?? '');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return result;
  }

  static String displayMember(Map<String, dynamic>? member) {
    if (member == null) return 'Sem responsável';
    final nickname = member['nickname']?.toString().trim() ?? '';
    if (nickname.isNotEmpty) return nickname;
    final fullName = member['full_name']?.toString().trim() ?? '';
    return fullName.isEmpty ? 'Membro' : fullName;
  }

  static String dinnerStatusLabel(String? status) => switch (status) {
        'planned' => 'Planeado',
        'closed' => 'Fechado',
        'completed' => 'Concluído',
        'cancelled' => 'Cancelado',
        _ => status?.trim().isEmpty ?? true ? '—' : status!,
      };

  static String availabilityLabel(String? status) => switch (status) {
        'active' => 'Ativo',
        'absent' => 'Ausente',
        'inactive' => 'Inativo',
        _ => 'Ativo',
      };

  static String swapStatusLabel(String? status) => switch (status) {
        'pending' => 'Pendente',
        'accepted' => 'Aceite — aguarda Direção',
        'rejected' => 'Recusada',
        'applied' => 'Aplicada',
        'cancelled' => 'Cancelada',
        _ => status?.trim().isEmpty ?? true ? '—' : status!,
      };
}
