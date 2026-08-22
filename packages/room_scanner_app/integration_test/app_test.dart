import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:room_scanner_ar/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App inicia correctamente', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Room Scanner AR'), findsOneWidget);
  });
}
