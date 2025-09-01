import 'package:shared_preferences/shared_preferences.dart';
import '../services/logger_service.dart';
import '../services/auth_service.dart';

/// Utility class to clean up old local profile storage
/// This ensures we use server as single source of truth
class CleanupLocalProfile {
  
  /// Removes all locally stored profile data for the current user
  /// Call this once to migrate users to server-only storage
  static Future<void> cleanupLocalProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await AuthService.getUserEmail();
      
      if (email == null) {
        LoggerService.info('🧹 No user logged in, skipping profile cleanup');
        return;
      }
      
      final userPrefix = '${email}_';
      
      // List of old profile keys to remove
      final keysToRemove = [
        '${userPrefix}subscribe_daily_nuggets',
        '${userPrefix}delivery_method',
        '${userPrefix}timezone',
        // Also clean up default keys if they exist
        'default_subscribe_daily_nuggets',
        'default_delivery_method',
        'default_timezone',
      ];
      
      int removedCount = 0;
      for (final key in keysToRemove) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          removedCount++;
          LoggerService.debug('🧹 Removed local profile key: $key');
        }
      }
      
      if (removedCount > 0) {
        LoggerService.info('🧹 Cleaned up $removedCount local profile preference(s)');
        LoggerService.info('📡 Profile data now stored on server only');
      } else {
        LoggerService.debug('🧹 No local profile data to clean up');
      }
    } catch (e) {
      LoggerService.error('🧹 Error cleaning up local profile data: $e', error: e);
      // Don't throw - this is a cleanup utility, not critical
    }
  }
  
  /// Check if any local profile data exists (for debugging)
  static Future<bool> hasLocalProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = await AuthService.getUserEmail();
      
      if (email == null) return false;
      
      final userPrefix = '${email}_';
      
      return prefs.containsKey('${userPrefix}subscribe_daily_nuggets') ||
             prefs.containsKey('${userPrefix}delivery_method') ||
             prefs.containsKey('${userPrefix}timezone') ||
             prefs.containsKey('default_subscribe_daily_nuggets') ||
             prefs.containsKey('default_delivery_method') ||
             prefs.containsKey('default_timezone');
    } catch (e) {
      LoggerService.error('🧹 Error checking for local profile data: $e', error: e);
      return false;
    }
  }
}