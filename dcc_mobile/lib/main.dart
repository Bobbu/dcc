import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'screens/quote_screen.dart';
import 'screens/quote_detail_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure URL strategy for web
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  await dotenv.load(fileName: ".env");
  
  try {
    await AuthService.configure();
  } catch (e) {
    print('Failed to configure auth service: $e');
  }
  
  runApp(const QuoteMeApp());
}

class QuoteMeApp extends StatelessWidget {
  const QuoteMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quote Me',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5), // Dark Indigo
          primary: const Color(0xFF3F51B5), // Dark Indigo
          secondary: const Color(0xFF5C6BC0), // Lighter Indigo accent
          surface: Colors.white, // Clean white background
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: const Color(0xFF3F51B5), // Dark Indigo text
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3F51B5), // Dark Indigo app bar
          foregroundColor: Colors.white,
          elevation: 2,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5), // Dark Indigo button
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFFE8EAF6), // Light indigo background
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

// GoRouter configuration
final GoRouter _router = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        print('🏠 Navigating to home screen');
        return const QuoteScreen();
      },
    ),
    GoRoute(
      path: '/quote/:id',
      builder: (BuildContext context, GoRouterState state) {
        final quoteId = state.pathParameters['id']!;
        print('📖 Navigating to quote detail screen with ID: $quoteId');
        return QuoteDetailScreen(quoteId: quoteId);
      },
    ),
  ],
);

