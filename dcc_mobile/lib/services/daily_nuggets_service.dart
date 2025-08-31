import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'auth_service.dart';
import 'logger_service.dart';


class DailyNuggetsSubscription {
  final String email;
  final bool isSubscribed;
  final String deliveryMethod;
  final String timezone;
  final DateTime createdAt;
  final DateTime updatedAt;

  DailyNuggetsSubscription({
    required this.email,
    required this.isSubscribed,
    required this.deliveryMethod,
    required this.timezone,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DailyNuggetsSubscription.fromJson(Map<String, dynamic> json) {
    return DailyNuggetsSubscription(
      email: json['email'] ?? '',
      isSubscribed: json['is_subscribed'] ?? false,
      deliveryMethod: json['delivery_method'] ?? 'email',
      timezone: json['timezone'] ?? 'America/New_York',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'is_subscribed': isSubscribed,
      'delivery_method': deliveryMethod,
      'timezone': timezone,
    };
  }
}

class DailyNuggetsService {
  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
  
  static Future<Map<String, String>> _getHeaders() async {
    final token = await AuthService.getIdToken();
    if (token == null) {
      throw Exception('Please sign in to use Daily Nuggets');
    }
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Get the user's current subscription status
  static Future<DailyNuggetsSubscription?> getSubscription() async {
    try {
      LoggerService.info('📧 Getting Daily Nuggets subscription...');
      final headers = await _getHeaders();
      final url = '$_baseUrl/subscriptions';
      
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      LoggerService.info('📧 Subscription response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DailyNuggetsSubscription.fromJson(data);
      } else if (response.statusCode == 404) {
        // No subscription found - this is normal for new users
        return null;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign out and sign in again.');
      } else {
        throw Exception('Failed to get subscription: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('❌ Error getting subscription: $e', error: e);
      rethrow;
    }
  }

  /// Update or create the user's subscription
  static Future<DailyNuggetsSubscription> updateSubscription({
    required bool isSubscribed,
    required String deliveryMethod,
    required String timezone,
  }) async {
    try {
      LoggerService.info('📧 Updating Daily Nuggets subscription...');
      LoggerService.info('   Subscribed: $isSubscribed');
      LoggerService.info('   Method: $deliveryMethod');
      LoggerService.info('   Timezone: $timezone');
      
      final headers = await _getHeaders();
      final url = '$_baseUrl/subscriptions';
      
      final body = json.encode({
        'is_subscribed': isSubscribed,
        'delivery_method': deliveryMethod,
        'timezone': timezone,
      });

      final response = await http.put(
        Uri.parse(url),
        headers: headers,
        body: body,
      );

      LoggerService.info('📧 Update response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final subscription = DailyNuggetsSubscription.fromJson(data['subscription']);
        LoggerService.info('✅ Subscription updated successfully');
        return subscription;
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign out and sign in again.');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to update subscription');
      }
    } catch (e) {
      LoggerService.error('❌ Error updating subscription: $e', error: e);
      rethrow;
    }
  }

  /// Delete the user's subscription
  static Future<void> deleteSubscription() async {
    try {
      LoggerService.info('📧 Deleting Daily Nuggets subscription...');
      final headers = await _getHeaders();
      final url = '$_baseUrl/subscriptions';
      
      final response = await http.delete(
        Uri.parse(url),
        headers: headers,
      );

      LoggerService.info('📧 Delete response: ${response.statusCode}');

      if (response.statusCode == 200) {
        LoggerService.info('✅ Subscription deleted successfully');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign out and sign in again.');
      } else {
        throw Exception('Failed to delete subscription: ${response.body}');
      }
    } catch (e) {
      LoggerService.error('❌ Error deleting subscription: $e', error: e);
      rethrow;
    }
  }

  /// Send a test email immediately (for testing purposes)
  static Future<void> sendTestEmail() async {
    try {
      LoggerService.info('📧 Sending test Daily Nugget email...');
      final headers = await _getHeaders();
      final url = '$_baseUrl/subscriptions/test';
      
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
      );

      LoggerService.info('📧 Test email response: ${response.statusCode}');

      if (response.statusCode == 200) {
        LoggerService.info('✅ Test email sent successfully');
      } else if (response.statusCode == 401) {
        throw Exception('Authentication failed. Please sign out and sign in again.');
      } else if (response.statusCode == 404) {
        throw Exception('No quotes available for test email');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send test email');
      }
    } catch (e) {
      LoggerService.error('❌ Error sending test email: $e', error: e);
      rethrow;
    }
  }
}