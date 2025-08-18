import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quote_me/services/api_service.dart';
import 'package:quote_me/services/logger_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';

void main() {
  group('ApiService Tests', () {
    late ApiService apiService;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: ".env");
      LoggerService.initialize();
    });

    setUp(() {
      apiService = ApiService();
    });

    test('getRandomQuote returns quote with all tags when no categories selected', () async {
      // Mock HTTP client
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('/quote'));
        expect(request.headers['x-api-key'], isNotNull);
        
        return http.Response(
          json.encode({
            'quote': 'Test quote',
            'author': 'Test Author',
            'tags': ['Motivation', 'Success'],
            'id': 'test-id-123'
          }),
          200,
        );
      });

      // Test with mocked client
      final quote = await apiService.getRandomQuoteWithClient(mockClient, []);
      
      expect(quote, isNotNull);
      expect(quote!['quote'], 'Test quote');
      expect(quote['author'], 'Test Author');
      expect(quote['tags'], ['Motivation', 'Success']);
      expect(quote['id'], 'test-id-123');
    });

    test('getRandomQuote handles 500 error with retry', () async {
      int callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount < 3) {
          return http.Response('Server Error', 500);
        }
        return http.Response(
          json.encode({
            'quote': 'Success after retry',
            'author': 'Retry Author',
            'tags': ['Persistence'],
            'id': 'retry-id'
          }),
          200,
        );
      });

      final quote = await apiService.getRandomQuoteWithClient(mockClient, [], retryCount: 0);
      
      expect(quote, isNotNull);
      expect(quote!['quote'], 'Success after retry');
      expect(callCount, 3);
    });

    test('getRandomQuote handles 429 rate limit error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Rate limit exceeded', 429);
      });

      final quote = await apiService.getRandomQuoteWithClient(mockClient, []);
      
      expect(quote, isNull);
    });

    test('getRandomQuote with specific categories sends correct query params', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.queryParameters['tags'], 'Business,Leadership');
        
        return http.Response(
          json.encode({
            'quote': 'Business quote',
            'author': 'Business Author',
            'tags': ['Business', 'Leadership'],
            'id': 'business-id'
          }),
          200,
        );
      });

      final quote = await apiService.getRandomQuoteWithClient(
        mockClient, 
        ['Business', 'Leadership']
      );
      
      expect(quote, isNotNull);
      expect(quote!['tags'], contains('Business'));
      expect(quote['tags'], contains('Leadership'));
    });

    test('getAvailableTags returns list of tags', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('/tags'));
        
        return http.Response(
          json.encode({
            'tags': ['All', 'Business', 'Leadership', 'Motivation'],
            'count': 4
          }),
          200,
        );
      });

      final tags = await apiService.getAvailableTagsWithClient(mockClient);
      
      expect(tags, isNotNull);
      expect(tags.length, 4);
      expect(tags, contains('All'));
      expect(tags, contains('Business'));
    });

    test('getQuoteById returns specific quote', () async {
      final testId = 'test-quote-123';
      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('/quote/$testId'));
        
        return http.Response(
          json.encode({
            'quote': 'Specific quote',
            'author': 'Specific Author',
            'tags': ['Test'],
            'id': testId
          }),
          200,
        );
      });

      final quote = await apiService.getQuoteByIdWithClient(mockClient, testId);
      
      expect(quote, isNotNull);
      expect(quote!['id'], testId);
      expect(quote['quote'], 'Specific quote');
    });

    test('getQuoteById handles 404 not found', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Requested quote was not found.', 404);
      });

      final quote = await apiService.getQuoteByIdWithClient(mockClient, 'non-existent');
      
      expect(quote, isNull);
    });
  });
}