import 'package:flutter_test/flutter_test.dart';

import 'package:bob_manager_mobile/core/global_search.dart';
import 'package:bob_manager_mobile/core/permissions.dart';

void main() {
  test('normalização global ignora acentos, espaços e separadores', () {
    expect(normalizeGlobalSearchToken('José da Silva'), 'josedasilva');
    expect(normalizeGlobalSearchToken('AA-01-BB'), 'aa01bb');
    expect(normalizeGlobalSearchToken('  Peça / Bar  '), 'pecabar');
  });

  test('política mostra apenas tipos dos módulos permitidos', () {
    final allowed = <AppPermission>{
      AppPermission.viewMembers,
      AppPermission.viewEvents,
    };

    final types = GlobalSearchPolicy.visibleTypes(allowed.contains);

    expect(
      types,
      [
        GlobalSearchType.member,
        GlobalSearchType.motorcycle,
        GlobalSearchType.event,
      ],
    );
    expect(types, isNot(contains(GlobalSearchType.document)));
    expect(types, isNot(contains(GlobalSearchType.product)));
  });

  test('resultado RPC é convertido sem campos extra', () {
    final result = GlobalSearchResult.fromMap({
      'result_type': 'motorcycle',
      'entity_id': 'moto-1',
      'parent_id': 'member-1',
      'title': 'Harley-Davidson Road Glide',
      'subtitle': 'AA-01-BB • 2026',
      'detail': 'Mota principal',
      'module_code': 'members',
      'score': 130,
      'email': 'não deve ser usado',
      'tax_number': 'não deve ser usado',
    });

    expect(result.type, GlobalSearchType.motorcycle);
    expect(result.entityId, 'moto-1');
    expect(result.parentId, 'member-1');
    expect(result.moduleCode, 'members');
    expect(result.score, 130);
  });
}
