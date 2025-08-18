import 'package:flutter/material.dart';

class AppThemes {
  // Define brand colors
  static const Color _darkIndigo = Color(0xFF3F51B5);
  static const Color _lightIndigo = Color(0xFF5C6BC0);
  static const Color _lightIndigoBackground = Color(0xFFE8EAF6);
  
  // Define consistent chip colors
  static const Color _lightChipBackground = Color(0xFF5C6BC0); // Slightly lighter than selected chips
  static const Color _lightChipText = Colors.white;
  static const Color _darkChipBackground = Color(0xFFE0E0E0);
  static const Color _darkChipText = Color(0xFF212121);

  // Define custom text styles for common use cases
  static const TextStyle _errorTextStyle = TextStyle(
    color: Color(0xFFD32F2F),
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle _successTextStyle = TextStyle(
    color: Color(0xFF388E3C),
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle _linkTextStyle = TextStyle(
    color: _darkIndigo,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.underline,
  );

  static const TextStyle _buttonTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static const TextStyle _dateTextStyle = TextStyle(
    fontSize: 14,
    color: Color(0xFF424242), // Colors.grey.shade800
    fontWeight: FontWeight.w400,
  );

  static const Color _dateIconColor = Color(0xFF424242); // Colors.grey.shade800
  static const double _dateIconSize = 16;

  // Custom text theme for light mode
  static final TextTheme _lightTextTheme = TextTheme(
    // Main quote text (large, italic)
    headlineLarge: const TextStyle(
      fontSize: 24,
      fontStyle: FontStyle.italic,
      color: Color(0xFF2C2C2C),
      fontWeight: FontWeight.w400,
      height: 1.3,
    ),
    // Author names
    headlineMedium: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _darkIndigo,
    ),
    // Section headers
    headlineSmall: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _darkIndigo,
    ),
    // Button text
    labelLarge: _buttonTextStyle,
    // Normal body text
    bodyLarge: const TextStyle(
      fontSize: 16,
      color: Color(0xFF2C2C2C),
    ),
    // Secondary text
    bodyMedium: const TextStyle(
      fontSize: 14,
      color: Color(0xFF666666),
    ),
    // Small text (captions, etc)
    bodySmall: const TextStyle(
      fontSize: 12,
      color: Color(0xFF888888),
    ),
    // Tag text
    labelMedium: const TextStyle(
      fontSize: 12,
      color: _darkIndigo,
      fontWeight: FontWeight.w500,
    ),
    // Small labels
    labelSmall: const TextStyle(
      fontSize: 10,
      color: Color(0xFF888888),
      fontWeight: FontWeight.w400,
    ),
  );

  // Custom text theme for dark mode
  static final TextTheme _darkTextTheme = TextTheme(
    // Main quote text (large, italic)
    headlineLarge: const TextStyle(
      fontSize: 24,
      fontStyle: FontStyle.italic,
      color: Color(0xFFE0E0E0),
      fontWeight: FontWeight.w400,
      height: 1.3,
    ),
    // Author names
    headlineMedium: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: _lightIndigo,
    ),
    // Section headers
    headlineSmall: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _lightIndigo,
    ),
    // Button text
    labelLarge: _buttonTextStyle,
    // Normal body text
    bodyLarge: const TextStyle(
      fontSize: 16,
      color: Color(0xFFE0E0E0),
    ),
    // Secondary text
    bodyMedium: const TextStyle(
      fontSize: 14,
      color: Color(0xFFB0B0B0),
    ),
    // Small text (captions, etc)
    bodySmall: const TextStyle(
      fontSize: 12,
      color: Color(0xFF888888),
    ),
    // Tag text
    labelMedium: const TextStyle(
      fontSize: 12,
      color: _lightIndigo,
      fontWeight: FontWeight.w500,
    ),
    // Small labels
    labelSmall: const TextStyle(
      fontSize: 10,
      color: Color(0xFF888888),
      fontWeight: FontWeight.w400,
    ),
  );

  // Custom extension for app-specific text styles
  static TextStyle errorText(BuildContext context) => _errorTextStyle;
  static TextStyle successText(BuildContext context) => _successTextStyle;
  static TextStyle linkText(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _linkTextStyle.copyWith(
      color: isDark ? _lightIndigo : _darkIndigo,
    );
  }
  static TextStyle dateText(BuildContext context) => _dateTextStyle;
  static Color dateIconColor(BuildContext context) => _dateIconColor;
  static double dateIconSize(BuildContext context) => _dateIconSize;

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _darkIndigo,
      primary: _darkIndigo,
      secondary: _lightIndigo,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: _darkIndigo,
      brightness: Brightness.light,
    ),

    // Text theme
    textTheme: _lightTextTheme,
    
    // AppBar theme
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkIndigo,
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: true,
    ),
    
    // Elevated button theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _darkIndigo,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    // Chip theme for consistent tag styling
    chipTheme: ChipThemeData(
      backgroundColor: _lightChipBackground,
      selectedColor: _darkIndigo, // Match AppBar background color
      labelStyle: const TextStyle(
        color: Colors.white, // White text on all chips
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white, // White text on selected chips too
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
      deleteIconColor: Colors.white,
      checkmarkColor: Colors.white,
      secondarySelectedColor: _darkIndigo, // Match AppBar background color
      iconTheme: const IconThemeData(color: Colors.white), // Force icon colors to white
      disabledColor: Colors.grey[300],
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    
    // Scaffold background
    scaffoldBackgroundColor: _lightIndigoBackground,
    
    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _darkIndigo, width: 2),
      ),
    ),
    
    // Card theme
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _darkIndigo,
      primary: _lightIndigo,
      secondary: _darkIndigo,
      surface: const Color(0xFF121212),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
      brightness: Brightness.dark,
    ),

    // Text theme
    textTheme: _darkTextTheme,
    
    // AppBar theme
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 2,
      centerTitle: true,
    ),
    
    // Elevated button theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _lightIndigo,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    
    // Chip theme for consistent tag styling
    chipTheme: ChipThemeData(
      backgroundColor: _darkChipBackground,
      labelStyle: const TextStyle(
        color: _darkChipText,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      deleteIconColor: _darkChipText,
      selectedColor: _lightIndigo, // Brighter in dark mode for visibility
      checkmarkColor: Colors.white, // White checkmark for visibility
      disabledColor: Colors.grey[600],
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    
    // Scaffold background
    scaffoldBackgroundColor: const Color(0xFF121212),
    
    // Input decoration theme
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _lightIndigo, width: 2),
      ),
    ),
    
    // Card theme
    cardTheme: CardThemeData(
      elevation: 2,
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}