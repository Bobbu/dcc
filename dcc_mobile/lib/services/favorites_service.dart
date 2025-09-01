import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'logger_service.dart';
import '../models/favorite.dart';

class FavoritesService {
  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  
  // Cache for favorite quote IDs - stored as a Set for O(1) lookup
  static Set<String> _cachedFavoriteIds = <String>{};
  static bool _cacheInitialized = false;
  
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

  /// Preload all favorites into cache for efficient lookups
  static Future<void> preloadFavorites() async {
    try {
      LoggerService.info('Preloading favorites cache...');
      final favorites = await _getFavoritesFromApi();
      
      // Update cache with quote IDs
      _cachedFavoriteIds = favorites.map((fav) => fav.quoteId).toSet();
      _cacheInitialized = true;
      
      LoggerService.info('✅ Favorites cache initialized with ${_cachedFavoriteIds.length} items');
    } catch (e) {
      LoggerService.error('❌ Failed to preload favorites cache', error: e);
      // Don't rethrow - we can fallback to individual API calls if needed
    }
  }

  /// Clear the favorites cache (e.g., on logout)
  static void clearCache() {
    _cachedFavoriteIds.clear();
    _cacheInitialized = false;
    LoggerService.info('Favorites cache cleared');
  }

  /// Internal method to fetch favorites from API without caching logic
  static Future<List<Favorite>> _getFavoritesFromApi() async {
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
      LoggerService.error('Error getting favorites from API', error: e);
      rethrow;
    }
  }

  static Future<List<Favorite>> getFavorites() async {
    // Always fetch fresh data from API for the favorites list
    return await _getFavoritesFromApi();
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
        // Update cache if initialized
        if (_cacheInitialized) {
          _cachedFavoriteIds.add(quoteId);
          LoggerService.debug('Added $quoteId to favorites cache');
        }
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
        // Update cache if initialized
        if (_cacheInitialized) {
          _cachedFavoriteIds.remove(quoteId);
          LoggerService.debug('Removed $quoteId from favorites cache');
        }
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
    // If cache is initialized, use it for O(1) lookup
    if (_cacheInitialized) {
      final isFav = _cachedFavoriteIds.contains(quoteId);
      LoggerService.debug('Cache hit for isFavorite($quoteId): $isFav');
      return isFav;
    }
    
    // Fallback to API call if cache not initialized
    LoggerService.debug('Cache not initialized, falling back to API for isFavorite($quoteId)');
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