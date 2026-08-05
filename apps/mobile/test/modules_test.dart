import 'package:bob_manager_mobile/core/module_definition.dart'; import 'package:flutter_test/flutter_test.dart';
void main(){test('Todos os módulos aprovados existem',(){expect(appModules.map((m)=>m.code),containsAll(['dashboard','members','treasury','fees','lottery','events','inventory','documents','communication','reports','settings','emergency']));});}
