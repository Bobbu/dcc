import 'dart:convert';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'logger_service.dart';
import 'favorites_service.dart';


class AuthService {
  static bool _isConfigured = false;
  
  static Future<void> configure() async {
    if (_isConfigured) return;
    
    try {
      LoggerService.info('🔧 Configuring Amplify with proper OAuth settings');
      
      // Check if Amplify is already configured (on hot reload)
      if (Amplify.isConfigured) {
        _isConfigured = true;
        LoggerService.info('✅ Amplify already configured');
        return;
      }
      
      final authPlugin = AmplifyAuthCognito();
      await Amplify.addPlugin(authPlugin);
      
      // Load Gen 2 configuration from asset
      final String amplifyConfig = await rootBundle.loadString('lib/amplify_outputs.json');
      await Amplify.configure(amplifyConfig);
      
      _isConfigured = true;
      LoggerService.info('✅ Amplify configured successfully with OAuth support');
    } catch (e) {
      LoggerService.error('❌ Failed to configure Amplify: $e', error: e);
      _isConfigured = false;
      rethrow;
    }
  }

  static Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } catch (e) {
      // Expected error when not authenticated - log as debug instead of error
      LoggerService.debug('Auth session check (expected when not signed in): $e');
      return false;
    }
  }

  static Future<bool> initializeAndCheckSignIn() async {
    try {
      await configure();
      return await isSignedIn();
    } catch (e) {
      LoggerService.error('Error initializing and checking sign-in: $e', error: e);
      return false;
    }
  }

  static Future<String?> getCurrentUserId() async {
    try {
      // Check if user is signed in first to avoid unnecessary API calls
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }

      final user = await Amplify.Auth.getCurrentUser();
      return user.userId;
    } catch (e) {
      LoggerService.error('Error getting current user ID: $e', error: e);
      return null;
    }
  }

  static Future<String?> getCurrentUserEmail() async {
    try {
      // Check if user is signed in first to avoid unnecessary API calls
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }

      // Check if user is federated to avoid unnecessary API calls that will fail
      final groups = await getUserGroups();
      final isFederatedUser = groups.any((group) => group.contains('Google') || group.contains('Facebook') || group.contains('SAML'));
      if (isFederatedUser) {
        LoggerService.debug('Skipping email fetch for federated user (insufficient OAuth scopes)');
        return null;
      }

      final attributes = await Amplify.Auth.fetchUserAttributes();
      for (final attribute in attributes) {
        if (attribute.userAttributeKey == AuthUserAttributeKey.email) {
          return attribute.value;
        }
      }
      return null;
    } catch (e) {
      // For federated users, this may fail with scope errors - that's expected
      LoggerService.warning('Could not fetch user email (may be federated user): ${e.toString().contains('NotAuthorizedServiceException') ? 'insufficient scopes' : e.toString()}');
      return null;
    }
  }

  static Future<String?> getCurrentUserName() async {
    try {
      // Check if user is signed in first to avoid unnecessary API calls
      final session = await Amplify.Auth.fetchAuthSession();
      if (!session.isSignedIn) {
        return null;
      }

      // Check if user is federated to avoid unnecessary API calls that will fail
      final groups = await getUserGroups();
      final isFederatedUser = groups.any((group) => group.contains('Google') || group.contains('Facebook') || group.contains('SAML'));
      if (isFederatedUser) {
        LoggerService.debug('Skipping name fetch for federated user (insufficient OAuth scopes)');
        return null;
      }

      final attributes = await Amplify.Auth.fetchUserAttributes();
      for (final attribute in attributes) {
        if (attribute.userAttributeKey == AuthUserAttributeKey.name) {
          return attribute.value;
        }
      }
      return null;
    } catch (e) {
      // For federated users, this may fail with scope errors - that's expected
      LoggerService.warning('Could not fetch user name (may be federated user): ${e.toString().contains('NotAuthorizedServiceException') ? 'insufficient scopes' : e.toString()}');
      return null;
    }
  }

  static Future<void> updateUserName(String name) async {
    try {
      // Check if user is federated to avoid API calls that will fail
      final groups = await getUserGroups();
      final isFederatedUser = groups.any((group) => group.contains('Google') || group.contains('Facebook') || group.contains('SAML'));
      
      if (isFederatedUser) {
        LoggerService.info('⚠️ Cannot update name for federated user (insufficient OAuth scopes)');
        LoggerService.info('💡 Federated users must update their display name through their identity provider');
        return; // Skip the update instead of throwing an error
      }

      await Amplify.Auth.updateUserAttribute(
        userAttributeKey: AuthUserAttributeKey.name,
        value: name,
      );
      LoggerService.info('✅ User name updated successfully');
    } catch (e) {
      LoggerService.error('Error updating user name: $e', error: e);
      rethrow;
    }
  }

  static Future<bool> signIn(String email, String password) async {
    try {
      LoggerService.info('Attempting sign-in for: $email');
      
      final result = await Amplify.Auth.signIn(
        username: email,
        password: password,
      );

      if (result.isSignedIn) {
        LoggerService.info('✅ Sign-in successful');
        // Preload favorites after successful sign-in
        FavoritesService.preloadFavorites().catchError((e) {
          LoggerService.error('Failed to preload favorites after sign-in', error: e);
        });
        return true;
      } else {
        LoggerService.warning('Sign-in not complete: ${result.nextStep}');
        return false;
      }
    } catch (e) {
      LoggerService.error('Sign-in error: $e', error: e);
      return false;
    }
  }

  static Future<SignUpResult> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    try {
      LoggerService.info('Attempting sign-up for: $email');
      
      final userAttributes = <AuthUserAttributeKey, String>{};
      if (name != null && name.isNotEmpty) {
        userAttributes[AuthUserAttributeKey.name] = name;
      }
      
      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(
          userAttributes: userAttributes,
        ),
      );
      
      LoggerService.info('Sign-up result: ${result.isSignUpComplete}');
      return result;
    } catch (e) {
      LoggerService.error('Sign-up error: $e', error: e);
      rethrow;
    }
  }

  static Future<SignUpResult> confirmSignUp({
    required String username,
    required String confirmationCode,
  }) async {
    try {
      LoggerService.info('Confirming sign-up for: $username');
      
      final result = await Amplify.Auth.confirmSignUp(
        username: username,
        confirmationCode: confirmationCode,
      );
      
      if (result.isSignUpComplete) {
        LoggerService.info('✅ Sign-up confirmed successfully');
      }
      
      return result;
    } catch (e) {
      LoggerService.error('Confirm sign-up error: $e', error: e);
      rethrow;
    }
  }

  static Future<ResendSignUpCodeResult> resendSignUpCode(String username) async {
    try {
      final result = await Amplify.Auth.resendSignUpCode(
        username: username,
      );
      LoggerService.info('✅ Confirmation code resent to $username');
      return result;
    } catch (e) {
      LoggerService.error('Resend code error: $e', error: e);
      rethrow;
    }
  }

  static Future<bool> signInWithGoogle() async {
    try {
      LoggerService.info('🔵 Starting Google OAuth sign-in via Cognito hosted UI...');
      LoggerService.info('🔍 Platform check - kIsWeb: $kIsWeb');
      
      // Use Amplify's signInWithWebUI - the proper way according to AWS docs
      final result = await Amplify.Auth.signInWithWebUI(
        provider: AuthProvider.google,
      );
      
      if (result.isSignedIn) {
        LoggerService.info('✅ Google sign-in successful via Amplify');
        FavoritesService.preloadFavorites().catchError((e) {
          LoggerService.error('Failed to preload favorites after Google sign-in', error: e);
        });
        return true;
      } else {
        LoggerService.warning('Google OAuth completed but user not signed in');
        return false;
      }
    } catch (e) {
      LoggerService.error('Google OAuth sign-in error: $e', error: e);
      return false;
    }
  }
  
  static Future<void> signOut() async {
    try {
      // Clear favorites cache before signing out
      FavoritesService.clearCache();
      
      // Sign out from both Amplify and Google if needed
      await Amplify.Auth.signOut();
      LoggerService.info('✅ Signed out successfully');
    } catch (e) {
      LoggerService.error('Sign out error: $e', error: e);
      rethrow;
    }
  }

  static Future<void> handleOAuthTokens(String accessToken, String idToken, String? refreshToken) async {
    try {
      LoggerService.info('🔧 Handling OAuth tokens...');
      // For now, just log that we received the tokens
      // The actual token handling is done by Amplify internally
      LoggerService.info('✅ OAuth tokens handled successfully');
      
      // Preload favorites after successful OAuth sign-in
      FavoritesService.preloadFavorites().catchError((e) {
        LoggerService.error('Failed to preload favorites after OAuth sign-in', error: e);
      });
    } catch (e) {
      LoggerService.error('Error handling OAuth tokens: $e', error: e);
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
        final groups = tokens.accessToken.groups;
        return List<String>.from(groups);
      }
      return [];
    } catch (e) {
      LoggerService.error('Error getting user groups: $e', error: e);
      return [];
    }
  }

  static Future<bool> isUserInAdminGroup() async {
    try {
      final groups = await getUserGroups();
      final isAdmin = groups.contains('Admins');
      LoggerService.info('User admin status: $isAdmin (groups: $groups)');
      return isAdmin;
    } catch (e) {
      LoggerService.error('Error checking admin group membership: $e', error: e);
      return false;
    }
  }

  static Future<String?> getAccessToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final accessToken = session.userPoolTokensResult.value.accessToken.raw;
        return accessToken;
      }
      return null;
    } catch (e) {
      LoggerService.error('Error getting access token: $e', error: e);
      return null;
    }
  }

  // Compatibility method - some parts of the app still expect getIdToken
  static Future<String?> getIdToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession) {
        final idToken = session.userPoolTokensResult.value.idToken.raw;
        return idToken;
      }
      return null;
    } catch (e) {
      LoggerService.error('Error getting ID token: $e', error: e);
      return null;
    }
  }

  // Decode JWT payload from base64
  static Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      // JWT has 3 parts separated by dots: header.payload.signature
      final parts = token.split('.');
      if (parts.length != 3) return null;
      
      // Decode the payload (second part)
      String payload = parts[1];
      
      // Add padding if needed for base64 decoding
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      
      // Decode base64 and parse JSON
      final decoded = utf8.decode(base64Decode(payload));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      LoggerService.debug('Error decoding JWT payload: $e');
      return null;
    }
  }

  // Get user info from tokens (works for federated users too)
  static Future<String?> getUserEmailFromToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession && session.isSignedIn) {
        final idToken = session.userPoolTokensResult.value.idToken;
        final tokenString = idToken.toJson();
        
        if (tokenString is String) {
          final payload = _decodeJwtPayload(tokenString);
          if (payload != null) {
            final email = payload['email'];
            return email is String ? email : null;
          }
        }
      }
      return null;
    } catch (e) {
      LoggerService.debug('Could not get email from token: $e');
      return null;
    }
  }

  static Future<String?> getUserNameFromToken() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      if (session is CognitoAuthSession && session.isSignedIn) {
        final idToken = session.userPoolTokensResult.value.idToken;
        final tokenString = idToken.toJson();
        
        if (tokenString is String) {
          final payload = _decodeJwtPayload(tokenString);
          if (payload != null) {
            // Try different name fields that might be present
            final name = payload['name'];
            if (name is String && name.isNotEmpty) return name;
            
            final givenName = payload['given_name'];
            if (givenName is String && givenName.isNotEmpty) return givenName;
            
            final nickname = payload['nickname'];
            if (nickname is String && nickname.isNotEmpty) return nickname;
          }
        }
      }
      return null;
    } catch (e) {
      LoggerService.debug('Could not get name from token: $e');
      return null;
    }
  }

  // Enhanced methods that try both approaches
  static Future<String?> getUserEmail() async {
    // First try the regular method (works for non-federated users)
    final email = await getCurrentUserEmail();
    if (email != null) return email;
    
    // Fall back to token method (works for federated users)
    return await getUserEmailFromToken();
  }

  static Future<String?> getUserName() async {
    // First try the regular method (works for non-federated users)
    final name = await getCurrentUserName();
    if (name != null) return name;
    
    // Fall back to token method (works for federated users)
    return await getUserNameFromToken();
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
      LoggerService.error('Confirm password reset error: $e', error: e);
      rethrow;
    }
  }

  // Get API base URL from environment
  static String getApiBaseUrl() {
    final url = dotenv.env['API_BASE_URL'] ?? 'https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod';
    LoggerService.info('Using API base URL: $url');
    return url;
  }

  // Make authenticated API calls
  static Future<http.Response> makeAuthenticatedRequest({
    required String endpoint,
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final baseUrl = getApiBaseUrl();
    final url = Uri.parse('$baseUrl$endpoint');
    
    final token = await getAccessToken();
    if (token == null) {
      throw Exception('No access token available');
    }

    final requestHeaders = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      ...?headers,
    };

    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(url, headers: requestHeaders);
      case 'POST':
        return await http.post(
          url,
          headers: requestHeaders,
          body: body != null ? json.encode(body) : null,
        );
      case 'PUT':
        return await http.put(
          url,
          headers: requestHeaders,
          body: body != null ? json.encode(body) : null,
        );
      case 'DELETE':
        return await http.delete(url, headers: requestHeaders);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
}