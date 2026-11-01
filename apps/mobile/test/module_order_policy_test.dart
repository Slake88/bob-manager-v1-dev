import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/core/module_order_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final canonical = appModules.map((module) => module.code).toList();

  test('repõe itens em falta e remove duplicados e módulos desconhecidos', () {
    final order = normalizeModuleOrder(
      <Object?>['bar', 'bar', 'future_module', 42, 'treasury'],
      canonical,
    );

    expect(order.length, 17);
    expect(order.toSet(), canonical.toSet());
    expect(order.take(2), ['bar', 'treasury']);
    expect(order.skip(2),
        canonical.where((code) => code != 'bar' && code != 'treasury'));
  });

  test('dados malformados preservam a ordem original completa', () {
    expect(normalizeModuleOrder('not-an-array', canonical), canonical);
  });

  test('um reset é reconhecido como a ausência de preferência', () {
    expect(isCanonicalModuleOrder(canonical, canonical), isTrue);
    expect(
      isCanonicalModuleOrder(
          <String>['future_module', ...canonical], canonical),
      isTrue,
    );
  });
}
