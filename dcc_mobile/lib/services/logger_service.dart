import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode, kIsWeb;

class LoggerService {
  static late Logger _logger;
  static bool _initialized = false;

  static void initialize({
    Level? level,
    bool? useColors,
  }) {
    if (_initialized) return;

    // Determine log level based on build mode if not explicitly provided
    final logLevel = level ?? _getDefaultLogLevel();
    
    // Determine color usage based on platform and build mode if not provided
    final shouldUseColors = useColors ?? _shouldUseColors();

    _logger = Logger(
      printer: _getPrinter(shouldUseColors),
      level: logLevel,
      filter: _getFilter(),
    );
    _initialized = true;
  }

  static Level _getDefaultLogLevel() {
    if (kReleaseMode) {
      // In release mode, only log warnings and errors
      return Level.warning;
    } else if (kDebugMode) {
      // In debug mode, log everything
      return Level.trace;
    } else {
      // Profile mode or other modes
      return Level.info;
    }
  }

  static bool _shouldUseColors() {
    // Use colors in debug mode, but not on web (browser console doesn't handle ANSI colors well)
    return kDebugMode && !kIsWeb;
  }

  static LogPrinter _getPrinter(bool useColors) {
    if (kReleaseMode) {
      // Simple output in release mode
      return SimplePrinter(
        printTime: true,
        colors: false,
      );
    } else {
      // Pretty printer for development
      return PrettyPrinter(
        methodCount: kDebugMode ? 2 : 0,
        errorMethodCount: 5,
        lineLength: 120,
        colors: useColors,
        printEmojis: !kIsWeb, // Emojis might not render well in browser console
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      );
    }
  }

  static LogFilter _getFilter() {
    if (kDebugMode) {
      // In debug mode, always log everything
      return DevelopmentFilter();
    } else {
      // In other modes, use production filter
      return ProductionFilter();
    }
  }

  static Logger get instance {
    if (!_initialized) {
      initialize();
    }
    return _logger;
  }

  static void debug(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    instance.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    instance.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    instance.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    instance.e(message, error: error, stackTrace: stackTrace);
  }

  static void wtf(dynamic message, {dynamic error, StackTrace? stackTrace}) {
    instance.f(message, error: error, stackTrace: stackTrace);
  }

  // Test helper method to reset logger state
  static void reset() {
    _initialized = false;
  }
}

class ProductionFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    return true;
  }
}