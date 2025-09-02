import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/quote_screen.dart';
import 'screens/user_profile_screen.dart';
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

class QuoteMeApp extends StatefulWidget {
  const QuoteMeApp({super.key});

  @override
  State<QuoteMeApp> createState() => _QuoteMeAppState();
  
  // Static method to access theme update
  static void updateTheme(ThemeMode themeMode) {
    _QuoteMeAppState.updateTheme(themeMode);
  }
}

class _QuoteMeAppState extends State<QuoteMeApp> {
  ThemeMode _themeMode = ThemeMode.system;
  
  // Static reference for global access
  static _QuoteMeAppState? _instance;
  
  @override
  void initState() {
    super.initState();
    _instance = this;
    _loadThemePreference();
  }
  
  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }
  
  // Static method to access theme update from anywhere
  static void updateTheme(ThemeMode themeMode) {
    _instance?.updateThemeMode(themeMode);
  }
  
  void _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('theme_mode') ?? 'system';
    setState(() {
      _themeMode = _getThemeModeFromString(themeString);
    });
  }
  
  ThemeMode _getThemeModeFromString(String themeString) {
    switch (themeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
  
  void updateThemeMode(ThemeMode themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = themeMode.toString().split('.').last;
    await prefs.setString('theme_mode', themeString);
    
    setState(() {
      _themeMode = themeMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Quote Me',
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: _themeMode,
      routerConfig: _router,
    );
  }
}

// GoRouter configuration
final GoRouter _router = GoRouter(
  initialLocation: '/',
  debugLogDiagnostics: true,
  redirect: (BuildContext context, GoRouterState state) {
    // Handle custom scheme deep links
    final uri = state.uri;
    LoggerService.debug('🔗 Incoming URI: ${uri.toString()}');
    LoggerService.debug('   - scheme: ${uri.scheme}');
    LoggerService.debug('   - host: ${uri.host}');
    LoggerService.debug('   - path: ${uri.path}');
    
    // Check if it's a custom scheme deep link
    if (uri.scheme == 'quoteme') {
      String newPath;
      
      if (uri.path.isNotEmpty && uri.path != '/') {
        // quoteme:///profile -> path = "/profile"
        newPath = uri.path;
      } else if (uri.host.isNotEmpty) {
        // quoteme://profile -> host = "profile", path = ""
        newPath = '/${uri.host}';
      } else {
        // fallback to home
        newPath = '/';
      }
      
      LoggerService.debug('🔄 Redirecting from ${uri.toString()} to $newPath');
      return newPath;
    }
    
    // No redirect needed for regular navigation
    return null;
  },
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
    GoRoute(
      path: '/profile',
      builder: (BuildContext context, GoRouterState state) {
        LoggerService.debug('👤 Navigating to user profile screen via deep link');
        return const UserProfileScreen(fromDeepLink: true);
      },
    ),
  ],
);

