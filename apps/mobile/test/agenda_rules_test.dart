import 'package:bob_manager_mobile/core/agenda_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('grelha mensal tem sempre 42 dias', () {
    expect(AgendaRules.monthGrid(DateTime(2026, 8)).length, 42);
  });

  test('grelha mensal começa numa segunda-feira', () {
    final grid = AgendaRules.monthGrid(DateTime(2026, 8));
    expect(grid.first.weekday, DateTime.monday);
  });

  test('fim de fevereiro respeita ano bissexto', () {
    expect(AgendaRules.monthEnd(DateTime(2028, 2)), DateTime(2028, 2, 29));
    expect(AgendaRules.monthEnd(DateTime(2027, 2)), DateTime(2027, 2, 28));
  });

  test('sameDay ignora a hora', () {
    expect(
      AgendaRules.sameDay(
        DateTime(2026, 8, 12, 8),
        DateTime(2026, 8, 12, 22),
      ),
      isTrue,
    );
  });

  test('filtro de aniversários só aceita birthday', () {
    expect(
      AgendaRules.matchesFilter(
        {'source_type': 'member', 'item_kind': 'birthday'},
        'birthdays',
      ),
      isTrue,
    );
    expect(
      AgendaRules.matchesFilter(
        {'source_type': 'member', 'item_kind': 'full_colors'},
        'birthdays',
      ),
      isFalse,
    );
  });

  test('filtro de prazos inclui documentos e prazos manuais', () {
    expect(
      AgendaRules.matchesFilter(
        {'source_type': 'document', 'item_kind': 'deadline'},
        'deadlines',
      ),
      isTrue,
    );
    expect(
      AgendaRules.matchesFilter(
        {'source_type': 'agenda', 'item_kind': 'deadline'},
        'deadlines',
      ),
      isTrue,
    );
    expect(
      AgendaRules.matchesFilter(
        {'source_type': 'event', 'item_kind': 'event'},
        'deadlines',
      ),
      isFalse,
    );
  });
}
