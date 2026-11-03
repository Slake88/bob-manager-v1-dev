import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/adaptive_layout.dart';
import 'package:bob_manager_mobile/core/app_navigation.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';

void main() {
  group('AppBreakpoints', () {
    test('classifica larguras compactas, médias e expandidas', () {
      expect(AppBreakpoints.forWidth(320), AppLayoutSize.compact);
      expect(AppBreakpoints.forWidth(599), AppLayoutSize.compact);
      expect(AppBreakpoints.forWidth(600), AppLayoutSize.medium);
      expect(AppBreakpoints.forWidth(999), AppLayoutSize.medium);
      expect(AppBreakpoints.forWidth(1000), AppLayoutSize.expanded);
      expect(AppBreakpoints.forWidth(1440), AppLayoutSize.expanded);
    });
  });

  group('AppNavigationPolicy', () {
    test('prioriza destinos principais do mobile', () {
      final visible = appModules
          .where(
            (module) => <String>{
              'events',
              'documents',
              'dashboard',
              'agenda',
              'bar',
              'members',
              'treasury',
            }.contains(module.code),
          )
          .toList();

      final plan = AppNavigationPolicy.plan(visible);

      expect(
        plan.primary.map((module) => module.code).toList(),
        ['dashboard', 'members', 'bar', 'events'],
      );
      expect(
        plan.secondary.map((module) => module.code).toSet(),
        {'treasury', 'agenda', 'documents'},
      );
    });

    test('preenche destinos principais quando faltam prioridades', () {
      final visible = appModules
          .where(
            (module) => <String>{
              'dashboard',
              'treasury',
              'fees',
            }.contains(module.code),
          )
          .toList();

      final plan = AppNavigationPolicy.plan(visible);

      expect(plan.primary.length, 3);
      expect(plan.primary.first.code, 'dashboard');
      expect(plan.secondary, isEmpty);
      expect(plan.compactSelectedIndex('fees'), 2);
    });

    test('Mais fica selecionado para um módulo secundário', () {
      final visible = appModules
          .where(
            (module) => <String>{
              'dashboard',
              'members',
              'bar',
              'events',
              'documents',
            }.contains(module.code),
          )
          .toList();
      final plan = AppNavigationPolicy.plan(visible);

      expect(plan.compactSelectedIndex('documents'), plan.primary.length);
    });

    test('resolve seleção removida para Dashboard', () {
      final visible = appModules
          .where(
            (module) => <String>{'dashboard', 'agenda'}.contains(module.code),
          )
          .toList();

      expect(
        AppNavigationPolicy.resolveSelected(visible, 'members').code,
        'dashboard',
      );
    });
  });
}
