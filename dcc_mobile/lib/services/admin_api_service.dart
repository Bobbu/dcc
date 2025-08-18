import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'logger_service.dart';

class AdminApiService {
  static final String baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await AuthService.getIdToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<String>> getTags() async {
    try {
      LoggerService.debug('📡 Fetching tags from admin API...');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/tags'),
        headers: headers,
      );

      LoggerService.debug('📡 Tags response status: ${response.statusCode}');
      LoggerService.debug('📡 Tags response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tags = List<String>.from(data['tags'] ?? []);
        LoggerService.info('✅ Successfully loaded ${tags.length} tags from API');
        return tags;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching tags: $e', error: e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getQuotes() async {
    try {
      LoggerService.debug('📡 Fetching quotes from admin API...');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/quotes'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Successfully loaded ${quotes.length} quotes from API');
        return quotes;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to load quotes: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quotes: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createQuote({
    required String quote,
    required String author,
    required List<String> tags,
  }) async {
    try {
      LoggerService.debug('📡 Creating new quote via admin API...');
      
      final headers = await _getAuthHeaders();
      final body = json.encode({
        'quote': quote,
        'author': author,
        'tags': tags,
      });

      final response = await http.post(
        Uri.parse('$baseUrl/admin/quotes'),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Quote created successfully');
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to create quote');
      }
    } catch (e) {
      LoggerService.error('❌ Error creating quote: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateQuote({
    required String id,
    required String quote,
    required String author,
    required List<String> tags,
  }) async {
    try {
      LoggerService.debug('📡 Updating quote via admin API...');
      
      final headers = await _getAuthHeaders();
      final body = json.encode({
        'quote': quote,
        'author': author,
        'tags': tags,
      });

      final response = await http.put(
        Uri.parse('$baseUrl/admin/quotes/$id'),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Quote updated successfully');
        return data;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Quote not found');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to update quote');
      }
    } catch (e) {
      LoggerService.error('❌ Error updating quote: $e', error: e);
      rethrow;
    }
  }

  static Future<void> deleteQuote(String id) async {
    try {
      LoggerService.debug('📡 Deleting quote via admin API...');
      
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/quotes/$id'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        LoggerService.info('✅ Quote deleted successfully');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else if (response.statusCode == 404) {
        throw Exception('Quote not found');
      } else {
        throw Exception('Failed to delete quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error deleting quote: $e', error: e);
      rethrow;
    }
  }
}