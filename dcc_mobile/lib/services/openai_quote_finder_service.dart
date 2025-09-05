import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import 'logger_service.dart';

/// Service for finding candidate quotes from authors using our secure AWS proxy endpoint
/// This keeps the OpenAI API key on the server side only
class OpenAIQuoteFinderService {
  static String get _baseUrl => dotenv.env['API_URL'] ?? 'https://dcc.anystupididea.com';
  
  /// Fetch candidate quotes for a specific author using our AWS proxy
  /// Returns up to 5 authentic quotes with source information (or the specified limit)
  static Future<Map<String, dynamic>> fetchCandidateQuotes(String author, {int limit = 5}) async {
    try {
      // Get auth token for admin API
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      // Call our secure proxy endpoint
      final url = Uri.parse('$_baseUrl/admin/candidate-quotes?author=${Uri.encodeComponent(author)}&limit=$limit');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Successfully fetched ${data['count']} candidate quotes for $author');
        return data;
      } else if (response.statusCode == 429) {
        // Rate limit hit
        throw Exception('Rate limit exceeded. Please wait a moment and try again.');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign in again.');
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Invalid request');
      } else {
        throw Exception('Failed to fetch candidate quotes: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching candidate quotes via proxy: $e', error: e);
      rethrow;
    }
  }
  
  /// Fetch candidate quotes for a specific topic using our AWS proxy
  /// Returns up to 5 relevant quotes from various authors with source information (or the specified limit)
  static Future<Map<String, dynamic>> fetchCandidateQuotesByTopic(String topic, {int limit = 5}) async {
    try {
      // Get auth token for admin API
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      // Call our secure proxy endpoint for topic-based search
      final url = Uri.parse('$_baseUrl/admin/candidate-quotes-by-topic?topic=${Uri.encodeComponent(topic)}&limit=$limit');
      
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        LoggerService.info('✅ Successfully fetched ${data['count']} candidate quotes for topic: $topic');
        return data;
      } else if (response.statusCode == 429) {
        // Rate limit hit
        throw Exception('Rate limit exceeded. Please wait a moment and try again.');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign in again.');
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Invalid request');
      } else {
        throw Exception('Failed to fetch candidate quotes by topic: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching candidate quotes by topic via proxy: $e', error: e);
      rethrow;
    }
  }
}