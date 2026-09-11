class AgendaRules {
  const AgendaRules._();

  static const Map<String, String> filterLabels = {
    'all': 'Tudo',
    'meetings': 'Reuniões',
    'events': 'Eventos',
    'birthdays': 'Aniversários',
    'milestones': 'Marcos',
    'dinners': 'Jantares',
    'deadlines': 'Prazos',
    'charges': 'Cobranças',
  };

  static DateTime monthStart(DateTime value) =>
      DateTime(value.year, value.month, 1);

  static DateTime monthEnd(DateTime value) =>
      DateTime(value.year, value.month + 1, 0);

  static List<DateTime> monthGrid(DateTime month) {
    final first = monthStart(month);
    final start =
        first.subtract(Duration(days: first.weekday - DateTime.monday));
    return List<DateTime>.generate(
      42,
      (index) => DateTime(start.year, start.month, start.day + index),
      growable: false,
    );
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool inMonth(DateTime day, DateTime month) =>
      day.year == month.year && day.month == month.month;

  static DateTime rowDate(Map<String, dynamic> row) {
    final raw = row['starts_at']?.toString() ?? '';
    return DateTime.parse(raw).toLocal();
  }

  static bool matchesFilter(Map<String, dynamic> row, String filter) {
    if (filter == 'all') return true;
    final source = row['source_type']?.toString() ?? '';
    final kind = row['item_kind']?.toString() ?? '';

    return switch (filter) {
      'meetings' => source == 'agenda' && kind == 'meeting',
      'events' => source == 'event',
      'birthdays' => source == 'member' && kind == 'birthday',
      'milestones' =>
        source == 'member' && (kind == 'prospect' || kind == 'full_colors'),
      'dinners' => source == 'weekly_dinner',
      'deadlines' => source == 'document' ||
          (source == 'agenda' && (kind == 'deadline' || kind == 'reminder')),
      'charges' => source == 'fee',
      _ => true,
    };
  }

  static String kindLabel(Map<String, dynamic> row) {
    final source = row['source_type']?.toString() ?? '';
    final kind = row['item_kind']?.toString() ?? '';

    if (source == 'event') return 'Evento';
    if (source == 'weekly_dinner') {
      return kind == 'dinner_extraordinary'
          ? 'Jantar extraordinário'
          : 'Jantar';
    }
    if (source == 'document') return 'Prazo';
    if (source == 'fee') return 'Cobrança';
    if (source == 'member') {
      return switch (kind) {
        'birthday' => 'Aniversário',
        'prospect' => 'Prospect',
        'full_colors' => 'Full Colors',
        _ => 'Membro',
      };
    }
    return switch (kind) {
      'meeting' => 'Reunião',
      'deadline' => 'Prazo',
      'reminder' => 'Lembrete',
      _ => 'Agenda',
    };
  }

  static bool isHighPriority(Map<String, dynamic> row) =>
      row['priority']?.toString() == 'high' ||
      row['item_status']?.toString() == 'overdue';
}
