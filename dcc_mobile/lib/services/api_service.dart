import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logger_service.dart';

class ApiService {
  static final String baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  // Testable methods that accept HTTP client for dependency injection
  Future<Map<String, dynamic>?> getRandomQuoteWithClient(
    http.Client client, 
    List<String> tags, 
    {int retryCount = 0}
  ) async {
    try {
      String url = '$baseUrl/quote';
      if (tags.isNotEmpty && !tags.contains('All')) {
        final tagsParam = tags.join(',');
        url += '?tags=$tagsParam';
      }
      
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 500 && retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return getRandomQuoteWithClient(client, tags, retryCount: retryCount + 1);
      } else if (response.statusCode == 429) {
        return null; // Rate limited
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      if (retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return getRandomQuoteWithClient(client, tags, retryCount: retryCount + 1);
      }
      LoggerService.error('Error fetching quote', error: e);
      return null;
    }
  }

  Future<List<String>> getAvailableTagsWithClient(http.Client client) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/tags'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<String>.from(data['tags'] ?? []);
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error fetching tags', error: e);
      return [];
    }
  }

  Future<Map<String, dynamic>?> getQuoteByIdWithClient(http.Client client, String id) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/quote/$id'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return null; // Quote not found
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error fetching quote by ID', error: e);
      return null;
    }
  }

  static Future<List<String>> getTags() async {
    try {
      LoggerService.debug('📡 Fetching tags from public API...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/tags'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      LoggerService.debug('📡 Tags response status: ${response.statusCode}');
      LoggerService.debug('📡 Tags response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tags = List<String>.from(data['tags'] ?? []);
        LoggerService.info('✅ Successfully loaded ${tags.length} tags from public API');
        return tags;
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching tags: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRandomQuote({List<String>? tags}) async {
    try {
      LoggerService.debug('📡 Fetching quote from API...');
      
      String url = '$baseUrl/quote';
      if (tags != null && tags.isNotEmpty && !tags.contains('All')) {
        final tagsParam = tags.join(',');
        url += '?tags=$tagsParam';
      }
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Successfully loaded quote from API');
        return data;
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quote: $e', error: e);
      rethrow;
    }
  }
}