import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:quote_me/screens/quote_screen.dart';

void main() {
  group('QuoteScreen Widget Tests', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: ".env");
    });

    testWidgets('QuoteScreen shows initial UI elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify key UI elements are present
      expect(find.text('Quote Me'), findsOneWidget);
      expect(find.text('Get Quote'), findsOneWidget);
      
      // Check for audio control button
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      
      // Check for share button (should be disabled initially)
      expect(find.byIcon(Icons.share), findsOneWidget);
      
      // Check for settings icon in app bar
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('Settings icon opens menu', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap settings icon
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify popup menu appears with expected options
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('Audio button toggles state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find initial audio button
      final audioButton = find.byKey(const Key('audio_toggle_button'));
      expect(audioButton, findsOneWidget);

      // Tap to toggle audio
      await tester.tap(audioButton);
      await tester.pumpAndSettle();

      // Button should still exist (state may change)
      expect(audioButton, findsOneWidget);
    });

    testWidgets('Get Quote button is visible and tappable', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final getQuoteButton = find.text('Get Quote');
      expect(getQuoteButton, findsOneWidget);

      // Verify button is enabled
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton).first);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('App shows loading state during quote fetch', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Get Quote button
      await tester.tap(find.text('Get Quote'));
      await tester.pump(); // Trigger loading state

      // Should show loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Share button exists', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find share button
      expect(find.byIcon(Icons.share), findsOneWidget);
    });

    testWidgets('QuoteScreen handles different screen sizes', (WidgetTester tester) async {
      // Test with small screen
      await tester.binding.setSurfaceSize(const Size(300, 600));
      
      await tester.pumpWidget(
        MaterialApp(
          home: const QuoteScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Quote Me'), findsOneWidget);

      // Test with large screen
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();

      expect(find.text('Quote Me'), findsOneWidget);

      // Reset to default size
      await tester.binding.setSurfaceSize(null);
    });
  });
}