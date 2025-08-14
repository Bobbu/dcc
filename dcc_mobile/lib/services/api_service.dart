import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static final String baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  static Future<List<String>> getTags() async {
    try {
      print('📡 Fetching tags from public API...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/tags'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': apiKey,
        },
      );

      print('📡 Tags response status: ${response.statusCode}');
      print('📡 Tags response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tags = List<String>.from(data['tags'] ?? []);
        print('✅ Successfully loaded ${tags.length} tags from public API');
        return tags;
      } else {
        throw Exception('Failed to load tags: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching tags: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getRandomQuote({List<String>? tags}) async {
    try {
      print('📡 Fetching quote from API...');
      
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
        print('✅ Successfully loaded quote from API');
        return data;
      } else {
        throw Exception('Failed to load quote: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching quote: $e');
      rethrow;
    }
  }
}