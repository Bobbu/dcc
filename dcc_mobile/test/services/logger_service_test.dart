import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:quote_me/services/logger_service.dart';

void main() {
  group('LoggerService Tests', () {
    tearDown(() {
      // Reset logger service state between tests
      LoggerService.reset();
    });

    test('LoggerService initializes with default settings', () {
      LoggerService.initialize();
      
      expect(LoggerService.instance, isA<Logger>());
    });

    test('LoggerService can be initialized with custom level', () {
      LoggerService.initialize(level: Level.error);
      
      expect(LoggerService.instance, isA<Logger>());
    });

    test('LoggerService debug method works', () {
      LoggerService.initialize();
      
      // Should not throw
      expect(() => LoggerService.debug('Test debug message'), returnsNormally);
    });

    test('LoggerService info method works', () {
      LoggerService.initialize();
      
      // Should not throw
      expect(() => LoggerService.info('Test info message'), returnsNormally);
    });

    test('LoggerService warning method works', () {
      LoggerService.initialize();
      
      // Should not throw
      expect(() => LoggerService.warning('Test warning message'), returnsNormally);
    });

    test('LoggerService error method works', () {
      LoggerService.initialize();
      
      // Should not throw
      expect(() => LoggerService.error('Test error message'), returnsNormally);
    });

    test('LoggerService error method works with error object', () {
      LoggerService.initialize();
      
      final testError = Exception('Test exception');
      
      // Should not throw
      expect(() => LoggerService.error('Test error message', error: testError), returnsNormally);
    });

    test('LoggerService wtf method works', () {
      LoggerService.initialize();
      
      // Should not throw
      expect(() => LoggerService.wtf('Test wtf message'), returnsNormally);
    });

    test('LoggerService singleton behavior', () {
      LoggerService.initialize();
      final logger1 = LoggerService.instance;
      final logger2 = LoggerService.instance;
      
      expect(logger1, same(logger2));
    });

    test('LoggerService prevents multiple initialization', () {
      LoggerService.initialize(level: Level.debug);
      final logger1 = LoggerService.instance;
      
      // Try to initialize again with different level
      LoggerService.initialize(level: Level.error);
      final logger2 = LoggerService.instance;
      
      // Should be the same instance
      expect(logger1, same(logger2));
    });
  });
}