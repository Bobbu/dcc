import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:quote_me/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Quote Me App Integration Tests', () {
    setUpAll(() async {
      await dotenv.load(fileName: ".env");
    });

    testWidgets('Complete app flow - get quote and interact', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Verify app loaded
      expect(find.text('Quote Me'), findsOneWidget);
      expect(find.text('Get Quote'), findsOneWidget);

      // Test getting a quote
      await tester.tap(find.text('Get Quote'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Should show a quote or error message
      final hasQuoteText = find.textContaining('"').evaluate().isNotEmpty;
      final hasErrorMessage = find.textContaining('Error').evaluate().isNotEmpty;
      final hasRateLimitMessage = find.textContaining('rate limit').evaluate().isNotEmpty;
      
      expect(hasQuoteText || hasErrorMessage || hasRateLimitMessage, isTrue);

      // Test audio button (should be visible)
      expect(find.byIcon(Icons.volume_up), findsOneWidget);

      // Test share button (should be visible)
      expect(find.byIcon(Icons.share), findsOneWidget);

      // Test settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Should show settings options
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);

      // Close menu by tapping elsewhere
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      // Try to get another quote
      await tester.tap(find.text('Get Quote'));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // App should still be responsive
      expect(find.text('Quote Me'), findsOneWidget);
    });

    testWidgets('Settings navigation flow', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Navigate to settings
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should be on settings screen
      expect(find.text('Settings'), findsOneWidget);

      // Should show audio controls
      expect(find.text('Audio Settings'), findsOneWidget);

      // Should show category selection
      expect(find.text('Quote Categories'), findsOneWidget);

      // Go back to main screen
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back on main screen
      expect(find.text('Get Quote'), findsOneWidget);
    });

    testWidgets('App handles network connectivity issues gracefully', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Try to get multiple quotes rapidly (might trigger rate limiting)
      for (int i = 0; i < 3; i++) {
        await tester.tap(find.text('Get Quote'));
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Wait for all requests to complete
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // App should still be responsive and show appropriate messages
      expect(find.text('Quote Me'), findsOneWidget);
      
      // Should either show a quote, error, or rate limit message
      final hasContent = find.byType(Text).evaluate().length > 2;
      expect(hasContent, isTrue);
    });

    testWidgets('Authentication flow (without actual login)', (WidgetTester tester) async {
      // Launch the app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Open settings menu
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Navigate to login
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Should be on login screen
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Go back without logging in
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back on main screen
      expect(find.text('Get Quote'), findsOneWidget);
    });
  });
}