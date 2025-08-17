import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      print('✅ Amplify configured successfully');
    } catch (e) {
      print('❌ Failed to configure Amplify: $e');
      rethrow;
    }
  }

  static Future<bool> isSignedIn() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession();
      return session.isSignedIn;
    } catch (e) {
      print('Error checking sign-in status: $e');
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
      print('Error getting current user: $e');
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
      print('Error getting ID token: $e');
      return null;
    }
  }

  static Future<Map<String, String>?> getUserAttributes() async {
    try {
      final attributes = await Amplify.Auth.fetchUserAttributes();
      return Map.fromEntries(
        attributes.map((attr) => MapEntry(attr.userAttributeKey.key, attr.value))
      );
    } catch (e) {
      print('Error fetching user attributes: $e');
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
      print('Error checking admin group membership: $e');
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
      
      // No longer checking for admin group here - 
      // let the calling code decide what to do based on user role
      
      return result;
    } catch (e) {
      print('Sign in error: $e');
      rethrow;
    }
  }

  static Future<void> signOut() async {
    try {
      await Amplify.Auth.signOut();
      print('✅ Signed out successfully');
    } catch (e) {
      print('Sign out error: $e');
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
      print('Error checking users group membership: $e');
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
      print('Error getting user groups: $e');
      return [];
    }
  }

  static Future<String?> getUserEmail() async {
    try {
      final attributes = await getUserAttributes();
      return attributes?['email'];
    } catch (e) {
      print('Error getting user email: $e');
      return null;
    }
  }

  static Future<String?> getUserName() async {
    try {
      final attributes = await getUserAttributes();
      return attributes?['name'] ?? attributes?['email']?.split('@').first;
    } catch (e) {
      print('Error getting user name: $e');
      return null;
    }
  }
}