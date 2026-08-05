import 'package:bob_manager_mobile/core/entity_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Todos os módulos CRUD principais têm definição e campos', () {
    expect(mainEntityDefinitions.keys, containsAll([
      'members',
      'treasury',
      'fees',
      'lottery',
      'events',
      'inventory',
      'documents',
      'communication',
    ]));

    for (final definition in mainEntityDefinitions.values) {
      expect(definition.table, isNotEmpty);
      expect(definition.primaryField, isNotEmpty);
      expect(definition.fields, isNotEmpty);
    }
  });

  test('Membros contém os campos aprovados essenciais', () {
    final keys = memberDefinition.fields.map((field) => field.key).toSet();
    expect(keys, containsAll([
      'birth_date',
      'prospect_joined_at',
      'full_colors_at',
      'primary_role',
      'additional_roles',
      'emergency_name',
      'allergies',
      'medical_notes',
      'motorcycle_brand',
      'motorcycle_model',
      'motorcycle_year',
      'motorcycle_registration',
    ]));
  });
}
