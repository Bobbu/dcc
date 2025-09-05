import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/logger_service.dart';
import '../services/auth_service.dart';

// Conditional imports for web
import 'oauth_callback_web.dart' if (dart.library.io) 'oauth_callback_stub.dart' as platform;

class OAuthCallbackScreen extends StatefulWidget {
  final String? code;
  final String? error;

  const OAuthCallbackScreen({
    super.key,
    this.code,
    this.error,
  });

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  bool _isProcessing = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _handleOAuthCallback();
  }

  Future<void> _handleOAuthCallback() async {
    try {
      LoggerService.info('📱 OAuth callback received');
      LoggerService.info('Code: ${widget.code}');
      LoggerService.info('Error: ${widget.error}');

      if (widget.error != null) {
        setState(() {
          _errorMessage = 'OAuth error: ${widget.error}';
          _isProcessing = false;
        });
        return;
      }

      if (widget.code == null) {
        setState(() {
          _errorMessage = 'No authorization code received';
          _isProcessing = false;
        });
        return;
      }

      // Exchange the authorization code for tokens
      final tokenUrl = 'https://dcc-demo-sam-app-auth.auth.us-east-1.amazoncognito.com/oauth2/token';
      final clientId = '2idvhvlhgbheglr0hptel5j55';
      final redirectUri = 'https://quote-me.anystupididea.com/auth/callback';

      LoggerService.info('🔄 Exchanging code for tokens...');
      
      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': widget.code!,
          'redirect_uri': redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final tokens = json.decode(response.body);
        LoggerService.info('✅ Token exchange successful');
        LoggerService.info('Tokens received: ${tokens.keys.toList()}');
        
        // Extract tokens
        final accessToken = tokens['access_token'];
        final idToken = tokens['id_token'];
        final refreshToken = tokens['refresh_token'];
        
        if (accessToken != null && idToken != null) {
          // Store the OAuth success in AuthService
          await AuthService.handleOAuthTokens(accessToken, idToken, refreshToken);
          LoggerService.info('✅ OAuth success flag stored');
          
          if (mounted) {
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Successfully logged in with Google! Reloading page...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            
            // Wait a moment for the snackbar to show, then force complete page reload
            await Future.delayed(Duration(milliseconds: 1500));
            
            if (!mounted) return;
            
            // Force complete page reload to restart the app fresh
            LoggerService.info('🔄 Forcing complete page reload...');
            if (kIsWeb) {
              // Use JavaScript to reload the entire page
              // This will restart the Flutter app completely
              context.go('/?force_reload=true');
              
              // After navigation, trigger a hard refresh
              Future.delayed(Duration(milliseconds: 100), () {
                if (kIsWeb) {
                  // Use platform-specific reload
                  platform.reloadPage();
                }
              });
            } else {
              // On mobile, just navigate normally
              context.go('/');
            }
          }
        } else {
          LoggerService.error('❌ Missing required tokens in response');
          setState(() {
            _errorMessage = 'Invalid token response - missing required tokens';
            _isProcessing = false;
          });
        }
      } else {
        LoggerService.error('Token exchange failed: ${response.statusCode} - ${response.body}');
        setState(() {
          _errorMessage = 'Failed to complete sign-in';
          _isProcessing = false;
        });
      }
    } catch (e) {
      LoggerService.error('OAuth callback error: $e', error: e);
      setState(() {
        _errorMessage = 'An error occurred during sign-in';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isProcessing) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Completing sign-in...',
                  style: theme.textTheme.titleLarge,
                ),
              ] else if (_errorMessage != null) ...[
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  _errorMessage!,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Home'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}