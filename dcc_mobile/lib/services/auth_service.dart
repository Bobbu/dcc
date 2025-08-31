import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logger_service.dart';
import 'favorites_service.dart';

class AuthService {
  static bool _isConfigured = false;
  
  static Future<void> configure() async {
    if (_isConfigured) return;
    
    try {
      final userPoolId = dotenv.env['USER_POOL_ID']!;
      final userPoolClientId = dotenv.env['USER_POOL_CLIENT_ID']!;
      
      final authPlugin = AmplifyAuthCognito();
      await Amplify.addPlugin(authPlugin);
      
      await Amplify.configure('''
{
    "UserAgent": "aws-amplify/0.1.x",
    "Version": "0.1.0",
    "auth": {
        "plugins": {
            "awsCognitoAuthPlugin": {
                "UserAgent": "aws-amplify/0.1.x",
                "Version": "0.1.0",
                "CognitoUserPool": {
                    "Default": {
                        "PoolId": "$userPoolId",
                        "AppClientId": "$userPoolClientId",
                        "Region": "us-east-1"
                    }
                },
                "Auth": {
                    "Default": {
                        "authenticationFlowType": "USER_SRP_AUTH"
                    }
                }
            }
        }
    }
}
''');
      
      _isConfigured = true;
      LoggerService.info('✅ Amplify configured successfully');
    } catch (e) {
      LoggerService.error('❌ Failed to configure Amplify: $e', error: e);
      rethrow;
    }
  }

  static Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } catch (e) {
      LoggerService.error('Error checking sign-in status: $e', error: e);
      return false;
    }
  }

  /// Check if user is signed in and preload favorites if so
  /// This should be called when the app starts
  static Future<bool> initializeAndCheckSignIn() async {
    try {
      final isUserSignedIn = await isSignedIn();
      if (isUserSignedIn) {
        LoggerService.info('User already signed in, preloading favorites...');
        // Run in background to avoid blocking app initialization
        FavoritesService.preloadFavorites().catchError((e) {
          LoggerService.error('Failed to preload favorites during initialization', error: e);
        });
      }
      return isUserSignedIn;
    } catch (e) {
      LoggerService.error('Error during auth initialization: $e', error: e);
      return false;
    }
  }

  static Future<AuthUser?> getCurrentUser() async {
    try {
      if (await isSignedIn()) {
        return await Amplify.Auth.getCurrentUser();
      }
      return null;
    } catch (e) {
      LoggerService.error('Error getting current user: $e', error: e);
      return null;
    }
  }

  static Future<String?> getIdToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final tokens = session.userPoolTokensResult.value;
        return tokens.idToken.raw;
      }
      return null;
    } catch (e) {
      LoggerService.error('Error getting ID token: $e', error: e);
      return null;
    }
  }

  /// Refresh the current user session to get fresh tokens
  static Future<void> refreshCurrentSession() async {
    try {
      LoggerService.info('🔄 Attempting to refresh user session...');
      final session = await Amplify.Auth.fetchAuthSession(options: const FetchAuthSessionOptions(forceRefresh: true));
      if (session.isSignedIn) {
        LoggerService.info('✅ Session refreshed successfully');
      } else {
        throw Exception('Session refresh resulted in signed out state');
      }
    } catch (e) {
      LoggerService.error('❌ Failed to refresh session: $e', error: e);
      rethrow;
    }
  }

  static Future<Map<String, String>?> getUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return Map.fromEntries(
        attributes.map((attr) => MapEntry(attr.userAttributeKey.key, attr.value))
      );
    } catch (e) {
      LoggerService.error('Error fetching user attributes: $e', error: e);
      return null;
    }
  }

  static Future<bool> isUserInAdminGroup() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final tokens = session.userPoolTokensResult.value;
        final groups = tokens.accessToken.groups;
        return groups.contains('Admins');
      }
      return false;
    } catch (e) {
      LoggerService.error('Error checking admin group membership: $e', error: e);
      return false;
    }
  }

  static Future<SignInResult> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final result = await Amplify.Auth.signIn(
        username: username,
        password: password,
      );
      
      // If sign-in was successful, preload favorites for efficient lookups
      if (result.isSignedIn) {
        LoggerService.info('Sign-in successful, preloading favorites...');
        // Run in background to avoid blocking the sign-in process
        FavoritesService.preloadFavorites().catchError((e) {
          LoggerService.error('Failed to preload favorites after sign-in', error: e);
        });
      }
      
      return result;
    } catch (e) {
      LoggerService.error('Sign in error: $e', error: e);
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      // Clear favorites cache before signing out
      FavoritesService.clearCache();
      
      await Amplify.Auth.signOut();
      LoggerService.info('✅ Signed out successfully');
    } catch (e) {
      LoggerService.error('Sign out error: $e', error: e);
      rethrow;
    }
  }

  static Future<bool> isUserInUsersGroup() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final tokens = session.userPoolTokensResult.value;
        final groups = tokens.accessToken.groups;
        return groups.contains('Users');
      }
      return false;
    } catch (e) {
      LoggerService.error('Error checking users group membership: $e', error: e);
      return false;
    }
  }

  static Future<List<String>> getUserGroups() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final tokens = session.userPoolTokensResult.value;
        return tokens.accessToken.groups;
      }
      return [];
    } catch (e) {
      LoggerService.error('Error getting user groups: $e', error: e);
      return [];
    }
  }

  static Future<String?> getUserEmail() async {
    try {
      final attributes = await getUserAttributes();
      return attributes?['email'];
    } catch (e) {
      LoggerService.error('Error getting user email: $e', error: e);
      return null;
    }
  }

  static Future<String?> getUserName() async {
    try {
      final attributes = await getUserAttributes();
      return attributes?['name'] ?? attributes?['email']?.split('@').first;
    } catch (e) {
      LoggerService.error('Error getting user name: $e', error: e);
      return null;
    }
  }

  static Future<ResetPasswordResult> resetPassword({
    required String username,
  }) async {
    try {
      final result = await Amplify.Auth.resetPassword(
        username: username,
      );
      LoggerService.info('✅ Password reset code sent to $username');
      return result;
    } catch (e) {
      LoggerService.error('Password reset error: $e', error: e);
      rethrow;
    }
  }

  static Future<ResetPasswordResult> confirmPasswordReset({
    required String username,
    required String newPassword,
    required String confirmationCode,
  }) async {
    try {
      final result = await Amplify.Auth.confirmResetPassword(
        username: username,
        newPassword: newPassword,
        confirmationCode: confirmationCode,
      );
      LoggerService.info('✅ Password reset confirmed for $username');
      return result;
    } catch (e) {
      LoggerService.error('Password reset confirmation error: $e', error: e);
      rethrow;
    }
  }

  static Future<void> updateUserName(String name) async {
    try {
      await Amplify.Auth.updateUserAttributes(
        attributes: [
          AuthUserAttribute(
            userAttributeKey: AuthUserAttributeKey.name,
            value: name,
          ),
        ],
      );
      
      LoggerService.info('✅ User name updated successfully to: $name');
    } catch (e) {
      LoggerService.error('Error updating user name: $e', error: e);
      rethrow;
    }
  }
}