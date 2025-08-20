import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'logger_service.dart';
import '../models/tag.dart';

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
        
        // Handle new format where tags are objects with 'name' field
        final tagsList = data['tags'] as List<dynamic>? ?? [];
        final tags = tagsList.map((tagObj) {
          if (tagObj is Map<String, dynamic> && tagObj.containsKey('name')) {
            return tagObj['name'] as String;
          } else if (tagObj is String) {
            return tagObj; // Support old format too
          }
          return tagObj.toString(); // Fallback
        }).toList();
        
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

  static Future<List<Tag>> getTagsWithMetadata() async {
    try {
      LoggerService.debug('📡 Fetching full tag objects from admin API...');
      
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/admin/tags'),
        headers: headers,
      );

      LoggerService.debug('📡 Tags metadata response status: ${response.statusCode}');
      LoggerService.debug('📡 Tags metadata response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final tagsList = data['tags'] as List<dynamic>? ?? [];
        final tags = tagsList.map((tagObj) {
          if (tagObj is Map<String, dynamic>) {
            return Tag.fromJson(tagObj);
          } else if (tagObj is String) {
            // Fallback for simple string format
            return Tag(name: tagObj);
          }
          return Tag(name: tagObj.toString());
        }).toList();
        
        LoggerService.info('✅ Successfully loaded ${tags.length} tag objects with metadata from API');
        return tags;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to load tag metadata: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching tag metadata: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getQuotesWithPagination({
    int limit = 50,
    String? lastKey,
    String sortBy = 'created_at',
    String sortOrder = 'desc',
  }) async {
    try {
      LoggerService.debug('📡 Fetching quotes from admin API (sort: $sortBy $sortOrder, limit: $limit)...');
      
      // Build query parameters
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      };
      
      if (lastKey != null && lastKey.isNotEmpty) {
        queryParams['last_key'] = lastKey;
      }
      
      final headers = await _getAuthHeaders();
      final uri = Uri.parse('$baseUrl/admin/quotes').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Successfully loaded ${quotes.length} quotes from API');
        
        return {
          'quotes': quotes,
          'total_count': data['total_count'] ?? 0,
          'last_key': data['last_key'],
          'has_more': data['last_key'] != null,
        };
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

  // Backward compatibility method - returns just the quotes list
  static Future<List<Map<String, dynamic>>> getQuotes() async {
    final result = await getQuotesWithPagination();
    return result['quotes'] as List<Map<String, dynamic>>;
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

  static Future<List<Map<String, dynamic>>> searchQuotes({
    required String query,
    int limit = 20,
    String? lastKey,
  }) async {
    try {
      LoggerService.debug('📡 Searching quotes: "$query" (limit: $limit)');
      
      final headers = await _getAuthHeaders();
      
      // Build query parameters
      final queryParams = <String, String>{
        'q': query,
        'limit': limit.toString(),
      };
      
      if (lastKey != null && lastKey.isNotEmpty) {
        queryParams['last_key'] = lastKey;
      }
      
      final uri = Uri.parse('$baseUrl/admin/search').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      LoggerService.debug('📡 Search response status: ${response.statusCode}');
      final bodyPreview = response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
      LoggerService.debug('📡 Search response body: $bodyPreview');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Search found ${quotes.length} quotes for "$query"');
        return quotes;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error searching quotes: $e', error: e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getQuotesByAuthor({
    required String author,
    int limit = 20,
    String? lastKey,
  }) async {
    try {
      LoggerService.debug('📡 Getting quotes by author: "$author" (limit: $limit)');
      
      final headers = await _getAuthHeaders();
      
      // Build query parameters
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      
      if (lastKey != null && lastKey.isNotEmpty) {
        queryParams['last_key'] = lastKey;
      }
      
      // URL encode the author name
      final encodedAuthor = Uri.encodeComponent(author);
      final uri = Uri.parse('$baseUrl/admin/quotes/author/$encodedAuthor').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      LoggerService.debug('📡 Author quotes response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Found ${quotes.length} quotes by "$author"');
        return quotes;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to get quotes by author: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error getting quotes by author: $e', error: e);
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getQuotesByTag({
    required String tag,
    int limit = 20,
    String? lastKey,
  }) async {
    try {
      LoggerService.debug('📡 Getting quotes by tag: "$tag" (limit: $limit)');
      
      final headers = await _getAuthHeaders();
      
      // Build query parameters
      final queryParams = <String, String>{
        'limit': limit.toString(),
      };
      
      if (lastKey != null && lastKey.isNotEmpty) {
        queryParams['last_key'] = lastKey;
      }
      
      // URL encode the tag name
      final encodedTag = Uri.encodeComponent(tag);
      final uri = Uri.parse('$baseUrl/admin/quotes/tag/$encodedTag').replace(queryParameters: queryParams);
      final response = await http.get(uri, headers: headers);

      LoggerService.debug('📡 Tag quotes response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        LoggerService.info('✅ Found ${quotes.length} quotes tagged "$tag"');
        return quotes;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication required or expired');
      } else if (response.statusCode == 403) {
        throw Exception('Admin access required');
      } else {
        throw Exception('Failed to get quotes by tag: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('❌ Error getting quotes by tag: $e', error: e);
      rethrow;
    }
  }
}