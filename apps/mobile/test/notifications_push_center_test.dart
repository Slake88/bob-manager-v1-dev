import 'package:bob_manager_mobile/core/notification_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filtro unread mostra apenas notificações não lidas', () {
    expect(
      notificationMatchesFilter(
        {'read_at': null, 'priority': 'normal'},
        NotificationViewFilter.unread,
      ),
      isTrue,
    );
    expect(
      notificationMatchesFilter(
        {'read_at': '2026-08-11T10:00:00Z', 'priority': 'normal'},
        NotificationViewFilter.unread,
      ),
      isFalse,
    );
  });

  test('high e urgent são prioridades destacadas', () {
    expect(notificationIsUrgent({'priority': 'high'}), isTrue);
    expect(notificationIsUrgent({'priority': 'urgent'}), isTrue);
    expect(notificationIsUrgent({'priority': 'normal'}), isFalse);
  });

  test('rota financeira abre Pedidos e Pagamentos', () {
    expect(notificationModuleFromRoute('/financial'), 'financial');
  });

  test('rota Euromilhões é normalizada para lottery', () {
    expect(notificationModuleFromRoute('/euromillions/draw/123'), 'lottery');
  });

  test('rota desconhecida não força navegação', () {
    expect(notificationModuleFromRoute('/nao-existe/123'), isNull);
  });
}
