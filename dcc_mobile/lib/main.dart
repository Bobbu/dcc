import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/quote_screen.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  runApp(const DccApp());
}

class DccApp extends StatelessWidget {
  const DccApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DCC Quote App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF800000), // Maroon
          primary: const Color(0xFF800000), // Maroon
          secondary: const Color(0xFFFFD700), // Gold
          surface: const Color(0xFFFFF8DC), // Cream background
          onPrimary: Colors.white,
          onSecondary: const Color(0xFF800000), // Maroon text on gold
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF800000), // Maroon app bar
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF800000), // Maroon button
            foregroundColor: Colors.white,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8DC), // Cream background
        useMaterial3: true,
      ),
      home: const QuoteScreen(),
    );
  }
}

