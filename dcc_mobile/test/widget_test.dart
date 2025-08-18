import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:quote_me/main.dart';

void main() {
  setUpAll(() async {
    // Load environment variables for tests
    TestWidgetsFlutterBinding.ensureInitialized();
    await dotenv.load(fileName: ".env");
  });

  testWidgets('QuoteMeApp loads and shows title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const QuoteMeApp());
    await tester.pumpAndSettle();

    // Verify that the app shows the Quote Me title
    expect(find.text('Quote Me'), findsOneWidget);
    
    // Verify that the Get Quote button exists
    expect(find.text('Get Quote'), findsOneWidget);
  });
}
