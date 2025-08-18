import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'screens/quote_screen.dart';
import 'screens/quote_detail_screen.dart';
import 'services/auth_service.dart';
import 'services/logger_service.dart';
import 'themes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize logger
  LoggerService.initialize();
  
  // Configure URL strategy for web
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  await dotenv.load(fileName: ".env");
  
  try {
    await AuthService.configure();
  } catch (e) {
    LoggerService.error('Failed to configure auth service', error: e);
  }
  
  runApp(const QuoteMeApp());
}

class QuoteMeApp extends StatelessWidget {
  const QuoteMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quote Me',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: ThemeMode.system, // Automatically follow system theme
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
        LoggerService.debug('🏠 Navigating to home screen');
        return const QuoteScreen();
      },
    ),
    GoRoute(
      path: '/quote/:id',
      builder: (BuildContext context, GoRouterState state) {
        final quoteId = state.pathParameters['id']!;
        LoggerService.debug('📖 Navigating to quote detail screen with ID: $quoteId');
        return QuoteDetailScreen(quoteId: quoteId);
      },
    ),
  ],
);

