import 'package:bob_manager_mobile/main.dart'; import 'package:flutter_test/flutter_test.dart';
void main(){testWidgets('Login é apresentado',(tester)async{await tester.pumpWidget(const BobManagerApp());expect(find.text('BOB MANAGER'),findsOneWidget);});}
