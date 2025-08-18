import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';

/// Service for generating tags using our secure AWS proxy endpoint
/// This keeps the OpenAI API key on the server side only
class OpenAIProxyService {
  static String get _baseUrl => dotenv.env['API_URL'] ?? 'https://dcc.anystupididea.com';
  
  /// Generate up to 5 relevant tags for a quote using our AWS proxy
  static Future<List<String>> generateTagsForQuote({
    required String quote,
    required String author,
    List<String> existingTags = const [],
  }) async {
    try {
      // Get auth token for admin API
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      // Call our secure proxy endpoint
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/generate-tags'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: json.encode({
          'quote': quote,
          'author': author,
          'existingTags': existingTags,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> tags = data['tags'] ?? [];
        
        // Convert to list of strings
        return tags.map((tag) => tag.toString()).toList();
      } else if (response.statusCode == 429) {
        // Rate limit hit
        throw Exception('Rate limit exceeded. Please wait a moment and try again.');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign in again.');
      } else {
        throw Exception('Failed to generate tags: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error generating tags via proxy: $e');
      rethrow;
    }
  }
}