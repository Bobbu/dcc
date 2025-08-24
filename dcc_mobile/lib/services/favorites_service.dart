import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'logger_service.dart';
import '../models/favorite.dart';

class FavoritesService {
  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  
  static Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.getIdToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<List<Favorite>> getFavorites() async {
    try {
      LoggerService.info('FavoritesService using base URL: $_baseUrl');
      final headers = await _getHeaders();
      final url = '$_baseUrl/favorites';
      LoggerService.info('Making GET request to: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      LoggerService.info('Get favorites response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final favoritesJson = data['favorites'] as List;
        return favoritesJson.map((json) => Favorite.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - please sign in');
      } else {
        throw Exception('Failed to load favorites: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('Error getting favorites', error: e);
      rethrow;
    }
  }

  static Future<bool> addFavorite(String quoteId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/favorites/$quoteId'),
        headers: headers,
      );

      LoggerService.info('Add favorite response: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - please sign in');
      } else if (response.statusCode == 404) {
        throw Exception('Quote not found');
      } else {
        throw Exception('Failed to add favorite: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('Error adding favorite', error: e);
      rethrow;
    }
  }

  static Future<bool> removeFavorite(String quoteId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/favorites/$quoteId'),
        headers: headers,
      );

      LoggerService.info('Remove favorite response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - please sign in');
      } else {
        throw Exception('Failed to remove favorite: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('Error removing favorite', error: e);
      rethrow;
    }
  }

  static Future<bool> isFavorite(String quoteId) async {
    try {
      final headers = await _getHeaders();
      final url = '$_baseUrl/favorites/$quoteId/check';
      LoggerService.info('Making GET request to: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      LoggerService.info('Check favorite response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['is_favorite'] ?? false;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - please sign in');
      } else {
        throw Exception('Failed to check favorite status: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('Error checking favorite status', error: e);
      rethrow;
    }
  }

  static Future<bool> toggleFavorite(String quoteId) async {
    try {
      final isFav = await isFavorite(quoteId);
      if (isFav) {
        await removeFavorite(quoteId);
        return false;
      } else {
        await addFavorite(quoteId);
        return true;
      }
    } catch (e) {
      LoggerService.error('Error toggling favorite', error: e);
      rethrow;
    }
  }
}