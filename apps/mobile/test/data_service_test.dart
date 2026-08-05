import 'package:bob_manager_mobile/services/data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Modo de demonstração permite criar, editar e eliminar membros', () async {
    final before = await DataService.instance.list('members');

    final created = await DataService.instance.insert('members', {
      'full_name': 'Membro de Teste',
      'status': 'prospect',
      'primary_role': 'Prospect',
    });

    final afterInsert = await DataService.instance.list('members');
    expect(afterInsert.length, before.length + 1);

    final updated = await DataService.instance.update(
      'members',
      created['id'].toString(),
      {'nickname': 'Teste'},
    );
    expect(updated['nickname'], 'Teste');

    await DataService.instance.delete('members', created['id'].toString());
    final afterDelete = await DataService.instance.list('members');
    expect(afterDelete.length, before.length);
  });

  test('Euromilhões usa participantes e chaves individuais', () async {
    final rows = await DataService.instance.list('lottery_participants');
    expect(rows, isNotEmpty);
    expect(rows.first['numbers'], isNotNull);
    expect(rows.first['stars'], isNotNull);
    expect(rows.first['member_name'], isNotNull);
  });
}
