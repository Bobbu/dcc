import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/share_service.dart';
import '../themes.dart';
import '../utils/cleanup_local_profile.dart';
import 'admin_dashboard_screen.dart';
import 'user_profile_screen.dart';
import 'propose_quote_screen.dart';
import 'favorites_screen.dart';
import '../widgets/favorite_heart_button.dart';
import '../services/daily_nuggets_service.dart';

// Conditional imports for web-specific functionality
import '../helpers/storage_helper_web.dart' if (dart.library.io) '../helpers/storage_helper_stub.dart' as storage_helper;


class QuoteScreen extends StatefulWidget {  
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> with WidgetsBindingObserver {
  String? _quote;
  String? _author;
  String? _currentQuoteId;
  List<String> _currentTags = [];
  bool _isLoading = false;
  String? _error;
  bool _isSpeaking = false;
  late FlutterTts flutterTts;
  
  // Settings
  bool _audioEnabled = false;  // Changed default to false
  Set<String> _selectedCategories = {'All'};
  Map<String, String>? _selectedVoice;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  int _quoteRetrievalLimit = 50;
  
  // Auth state
  bool _isSignedIn = false;
  bool _isAdmin = false;
  String? _userName;
  bool _isSubscribedToDailyNuggets = false;
  bool _authCheckComplete = false;
  bool _initialAuthCheckDone = false;

  static final String apiEndpoint = dotenv.env['API_ENDPOINT'] ?? '';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initTts();
    _loadSettings();
    _checkAuthStatus().then((_) {
      // Mark initial auth check as complete
      _initialAuthCheckDone = true;
    });
    _handleAuthSuccessParameter();
  }
  
  void _handleAuthSuccessParameter() {
    if (kIsWeb) {
      // Check if we came from OAuth success redirect or force reload
      final uri = Uri.base;
      
      // Check for force reload parameter (after OAuth success)
      if (uri.queryParameters.containsKey('force_reload')) {
        LoggerService.info('🔄 Force reload detected - checking OAuth success...');
        _handleOAuthSuccessReload();
        return;
      }
      
      // Legacy check for auth success parameter
      if (uri.queryParameters.containsKey('auth') && 
          uri.queryParameters['auth'] == 'success') {
        LoggerService.info('🔄 OAuth success detected - refreshing auth status...');
        // Give a moment for localStorage to be processed, then refresh auth
        Future.delayed(Duration(milliseconds: 500), () {
          _checkAuthStatus();
        });
      }
    }
  }
  
  void _handleOAuthSuccessReload() {
    if (kIsWeb) {
      try {
        final oauthSuccess = storage_helper.getLocalStorageItem('oauth_success');
        final timestamp = storage_helper.getLocalStorageItem('oauth_timestamp');
        
        if (oauthSuccess == 'true' && timestamp != null) {
          final timestampMs = int.tryParse(timestamp) ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          
          // Check if OAuth success was recent (within 5 minutes)
          if ((now - timestampMs) < 5 * 60 * 1000) {
            LoggerService.info('✅ Recent OAuth success detected - BYPASSING AMPLIFY');
            
            // Clear the OAuth success flag
            storage_helper.removeLocalStorageItem('oauth_success');
            storage_helper.removeLocalStorageItem('oauth_timestamp');
            
            // Set a simple flag that this is an OAuth user (bypass Amplify)
            storage_helper.setLocalStorageItem('oauth_user_active', 'true');
            storage_helper.setLocalStorageItem('oauth_user_session', DateTime.now().millisecondsSinceEpoch.toString());
            
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎉 Successfully signed in with Google!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            
            // Force UI refresh to show signed-in state
            Future.delayed(Duration(milliseconds: 1000), () {
              setState(() {
                _isSignedIn = true; // Force signed-in state
              });
            });
            
          } else {
            LoggerService.info('⚠️ OAuth success flag is too old - ignoring');
            storage_helper.removeLocalStorageItem('oauth_success');
            storage_helper.removeLocalStorageItem('oauth_timestamp');
          }
        }
      } catch (e) {
        LoggerService.error('❌ Error checking OAuth success flag: $e');
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      flutterTts.stop();
    } catch (e) {
      LoggerService.debug('Error stopping TTS in dispose: $e');
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App came back into focus - this is especially important for OAuth
      // as users may have signed in via browser and returned to the app
      LoggerService.info('📱 App resumed - checking auth status for OAuth callback...');
      _checkAuthStatus();
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only check auth when returning to this screen, not on initial load
    if ((ModalRoute.of(context)?.isCurrent ?? false) && _initialAuthCheckDone) {
      // Reset auth check flag so buttons stay hidden until status is confirmed
      setState(() {
        _authCheckComplete = false;
      });
      _checkAuthStatus();
    }
  }
  
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
  
  Future<void> _checkAuthStatus() async {
    LoggerService.debug('🔄 Checking auth status in QuoteScreen...');
    
    // First check for OAuth user session (bypass Amplify)
    bool isOAuthUser = false;
    if (kIsWeb) {
      try {
        final oauthActive = storage_helper.getLocalStorageItem('oauth_user_active');
        final sessionTime = storage_helper.getLocalStorageItem('oauth_user_session');
        
        if (oauthActive == 'true' && sessionTime != null) {
          final sessionTimestamp = int.tryParse(sessionTime) ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          final sessionAge = now - sessionTimestamp;
          final maxAge = 24 * 60 * 60 * 1000; // 24 hours
          
          isOAuthUser = sessionAge < maxAge;
          LoggerService.debug('  OAuth user check: $isOAuthUser (age: ${sessionAge}ms)');
        }
      } catch (e) {
        LoggerService.error('Error checking OAuth session: $e');
      }
    }
    
    bool isSignedIn = isOAuthUser;
    
    // If not OAuth user, check Amplify sessions
    if (!isSignedIn) {
      try {
        isSignedIn = await AuthService.initializeAndCheckSignIn();
        LoggerService.debug('  Initial Amplify auth check - is signed in: $isSignedIn');
      } catch (e) {
        // Handle any Amplify configuration errors gracefully
        LoggerService.debug('  Amplify auth check failed (normal for unauthenticated): $e');
        isSignedIn = false;
      }
    }
    
    LoggerService.debug('  Final auth status: $isSignedIn');
    
    if (isSignedIn) {
      final isAdmin = await AuthService.isUserInAdminGroup();
      final userName = await AuthService.getUserName();
      LoggerService.debug('  Is admin: $isAdmin');
      LoggerService.debug('  User name: $userName');
      
      // Clean up any old local profile data (one-time migration)
      // This ensures we use server as single source of truth
      await CleanupLocalProfile.cleanupLocalProfileData();
      
      // Check Daily Nuggets subscription status
      bool isSubscribed = false;
      try {
        final subscription = await DailyNuggetsService.getSubscription();
        isSubscribed = subscription?.isSubscribed ?? false;
        LoggerService.debug('  Daily Nuggets subscribed: $isSubscribed');
      } catch (e) {
        LoggerService.debug('  Error checking Daily Nuggets subscription: $e');
        // Continue without subscription status
      }
      
      if (mounted) {
        setState(() {
          _isSignedIn = true;
          _isAdmin = isAdmin;
          _userName = userName;
          _isSubscribedToDailyNuggets = isSubscribed;
          _authCheckComplete = true;
        });
        LoggerService.debug('✅ Auth state updated: signedIn=$_isSignedIn, admin=$_isAdmin, dailyNuggets=$_isSubscribedToDailyNuggets');
      }
    } else {
      // Clear state when not signed in
      LoggerService.debug('  User not signed in, clearing state');
      if (mounted) {
        setState(() {
          _isSignedIn = false;
          _isAdmin = false;
          _userName = null;
          _isSubscribedToDailyNuggets = false;
          _authCheckComplete = true;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    // Clear OAuth session data if present
    if (kIsWeb) {
      try {
        storage_helper.removeLocalStorageItem('oauth_user_active');
        storage_helper.removeLocalStorageItem('oauth_user_session');
        LoggerService.info('🔄 Cleared OAuth session data');
      } catch (e) {
        LoggerService.error('Error clearing OAuth session: $e');
      }
    }
    
    await AuthService.signOut();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _isAdmin = false;
        _userName = null;
        _isSubscribedToDailyNuggets = false;
        _authCheckComplete = true;
        _quote = null;
        _author = null;
        _currentQuoteId = null;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isLargeScreen = screenWidth > 600;
        
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isLargeScreen ? 450 : 350,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.format_quote,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quote Me',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '1.0.0',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 179),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Quote Me is your daily source of inspiration and motivation. '
                        'Discover wisdom from great thinkers, leaders, and authors throughout history, and some comedians, too.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: isLargeScreen ? 14 : 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Features:',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '• Curated collection of inspirational quotes\n'
                          '• Filter by categories using tags\n'
                          '• Text-to-speech (pretty goofy) with customizable voices\n'
                          '• Share quotes with friends\n'
                          '• Subscribe to receive daily nuggets\n'
                          '• Favorite quotes that you love\n'
                          '• Propose new quotes\n'
                          '• Dark and light theme support',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: isLargeScreen ? 14 : 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Built with Flutter and powered by AWS serverless technology.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Copyright © 2025 Catalyst Technology LLC\nAll rights reserved.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: () {
                        showLicensePage(
                          context: context,
                          applicationName: 'Quote Me',
                          applicationVersion: '1.0.0',
                          applicationIcon: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.format_quote,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: 28,
                            ),
                          ),
                          applicationLegalese: '© 2025 Quote Me App',
                        );
                      },
                      child: Text('View licenses'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _initTts() {
    flutterTts = FlutterTts();
    
    flutterTts.setStartHandler(() {
      LoggerService.debug('🔊 TTS Start Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
    });

    flutterTts.setCompletionHandler(() {
      LoggerService.debug('✅ TTS Completion Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setErrorHandler((msg) {
      LoggerService.debug('❌ TTS Error Handler triggered: $msg');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setCancelHandler(() {
      LoggerService.debug('🛑 TTS Cancel Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setPauseHandler(() {
      LoggerService.debug('⏸️ TTS Pause Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setContinueHandler(() {
      LoggerService.debug('▶️ TTS Continue Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
    });

    // Configure TTS settings
    _setTtsSettings();
  }

  void _setTtsSettings() async {
    await flutterTts.setSpeechRate(_speechRate);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(_pitch);
    
    // Apply voice if one is selected
    if (_selectedVoice != null) {
      await flutterTts.setVoice(_selectedVoice!);
    }
  }

  void _speakQuote() async {
    LoggerService.debug('🔊 _speakQuote() called - _audioEnabled=$_audioEnabled, _quote=${_quote != null}, _author=${_author != null}');
    
    if (_audioEnabled && _quote != null && _author != null) {
      String textToSpeak = '$_quote, ... $_author';
      final previewLength = textToSpeak.length > 50 ? 50 : textToSpeak.length;
      LoggerService.debug('🎤 About to speak: "${textToSpeak.substring(0, previewLength)}..."');
      
      // Manually set speaking state (in case TTS handlers don't fire in simulator)
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
      
      try {
        await flutterTts.speak(textToSpeak);
        LoggerService.debug('✅ TTS speak() called successfully');
        
        // For simulator compatibility: auto-reset speaking state after estimated time
        // Calculate rough duration: assume 150 words per minute
        final wordCount = textToSpeak.split(' ').length;
        final estimatedDurationMs = (wordCount / 150 * 60 * 1000).round();
        final maxDurationMs = estimatedDurationMs + 2000; // Add 2 second buffer
        
        Timer(Duration(milliseconds: maxDurationMs), () {
          if (mounted && _isSpeaking) {
            LoggerService.debug('⏰ Auto-resetting speaking state after timeout');
            setState(() {
              _isSpeaking = false;
            });
          }
        });
        
      } catch (e) {
        LoggerService.debug('❌ Error in _speakQuote: $e');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      }
    } else {
      LoggerService.debug('⏹️ Not speaking because: audioEnabled=$_audioEnabled, quote=${_quote != null}, author=${_author != null}');
    }
  }

  void _stopSpeaking() async {
    LoggerService.debug('🛑 _stopSpeaking() called - current _isSpeaking=$_isSpeaking');
    
    try {
      await flutterTts.stop();
      LoggerService.debug('✅ TTS stop() called successfully in _stopSpeaking');
      
      // Force state update in case handlers don't fire
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    } catch (e) {
      LoggerService.debug('❌ Error stopping TTS in _stopSpeaking: $e');
      // Still update state even if stop failed
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }


  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _audioEnabled = prefs.getBool('audio_enabled') ?? false;  // Changed default to false
      final categories = prefs.getStringList('selected_categories') ?? ['All'];
      _selectedCategories = Set<String>.from(categories);
      
      // Load quote retrieval limit
      _quoteRetrievalLimit = prefs.getInt('quote_retrieval_limit') ?? 50;
      
      // Load selected voice
      final voiceName = prefs.getString('selected_voice_name');
      final voiceLocale = prefs.getString('selected_voice_locale');
      if (voiceName != null && voiceLocale != null) {
        _selectedVoice = {'name': voiceName, 'locale': voiceLocale};
      }
      
      // Load TTS parameters
      _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      _pitch = prefs.getDouble('pitch') ?? 1.0;
    });
    
    // Apply all TTS settings
    _setTtsSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('audio_enabled', _audioEnabled);
    await prefs.setStringList('selected_categories', _selectedCategories.toList());
    await prefs.setInt('quote_retrieval_limit', _quoteRetrievalLimit);
    
    // Save selected voice
    if (_selectedVoice != null) {
      await prefs.setString('selected_voice_name', _selectedVoice!['name']!);
      await prefs.setString('selected_voice_locale', _selectedVoice!['locale']!);
    }
    
    // Save TTS parameters
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setDouble('pitch', _pitch);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          audioEnabled: _audioEnabled,
          selectedCategories: _selectedCategories,
          selectedVoice: _selectedVoice,
          speechRate: _speechRate,
          pitch: _pitch,
          quoteRetrievalLimit: _quoteRetrievalLimit,
          maxReturnedQuotes: 5, // Default value for non-admin users (this setting won't be shown)
          isAdmin: _isAdmin,
          onSettingsChanged: (audioEnabled, categories, voice, speechRate, pitch, quoteRetrievalLimit, maxReturnedQuotes) {
            setState(() {
              _audioEnabled = audioEnabled;
              _selectedCategories = categories;
              _selectedVoice = voice;
              _speechRate = speechRate;
              _pitch = pitch;
              _quoteRetrievalLimit = quoteRetrievalLimit;
              // Note: maxReturnedQuotes is not used in quote_screen as it's admin-only
            });
            _saveSettings();
            // Apply all TTS settings immediately
            _setTtsSettings();
          },
        ),
      ),
    );
  }

  Future<void> _openAdmin() async {
    LoggerService.debug('🚀 Opening admin from QuoteScreen...');
    
    // Check if user is already signed in as admin
    final isSignedIn = await AuthService.isSignedIn();
    final isAdmin = isSignedIn ? await AuthService.isUserInAdminGroup() : false;
    
    LoggerService.debug('  Current auth: signedIn=$isSignedIn, admin=$isAdmin');
    
    if (isSignedIn && isAdmin) {
      // Already signed in as admin, go directly to dashboard
      if (mounted) {
        LoggerService.debug('  Navigating to AdminDashboardScreen...');
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardScreen(),
          ),
        );
        // ALWAYS refresh auth status when returning from admin dashboard
        LoggerService.debug('  Returned from AdminDashboard, refreshing auth...');
        await _checkAuthStatus();
      }
    } else {
      // Not signed in or not admin, show login screen
      if (mounted) {
        LoggerService.debug('  Navigating to LoginScreen...');
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
        // Refresh auth status if login was successful
        if (result == true) {
          LoggerService.debug('  Login successful, refreshing auth...');
          await _checkAuthStatus();
        }
      }
    }
  }

  Future<void> _shareQuote() async {
    if (_quote == null || _author == null || _currentQuoteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No quote to share yet. Please wait for a quote to load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    await ShareService.shareQuote(
      context: context,
      quote: _quote!,
      author: _author!,
      quoteId: _currentQuoteId!,
      tags: _currentTags,
    );
  }

  Future<void> _getQuote({int retryCount = 0}) async {
    LoggerService.debug('🎯 _getQuote() called - Current state: _isLoading=$_isLoading, _isSpeaking=$_isSpeaking, retry=$retryCount');
    
    // Stop any currently playing audio - wrap in try-catch to handle interruption errors
    try {
      LoggerService.debug('🔇 Attempting to stop TTS...');
      await flutterTts.stop();
      LoggerService.debug('✅ TTS stop completed successfully');
    } catch (e) {
      LoggerService.debug('❌ Error stopping TTS: $e');
      // Continue anyway - the error shouldn't prevent getting a new quote
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
      _isSpeaking = false; // Reset speaking state
    });

    try {
      // Build URL with tag filtering and limit
      String url = apiEndpoint;
      List<String> queryParams = [];
      
      if (!_selectedCategories.contains('All') && _selectedCategories.isNotEmpty) {
        final tags = _selectedCategories.join(',');
        queryParams.add('tags=$tags');
      }
      
      // Add the quote retrieval limit
      queryParams.add('limit=$_quoteRetrievalLimit');
      
      if (queryParams.isNotEmpty) {
        url += '?${queryParams.join('&')}';
      }
      
      LoggerService.debug('🌐 Making API request to: $url');
      LoggerService.debug('📋 Selected categories: $_selectedCategories');
      LoggerService.debug('📊 Quote retrieval limit: $_quoteRetrievalLimit');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      );
      
      LoggerService.debug('📡 API Response: ${response.statusCode}');
      if (response.statusCode != 200) {
        LoggerService.debug('❌ API Error Body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quoteText = data['quote']?.toString() ?? 'null';
        final previewLength = quoteText.length > 50 ? 50 : quoteText.length;
        LoggerService.debug('✅ Quote received: "${quoteText.substring(0, previewLength)}..."');
        
        setState(() {
          _quote = data['quote'];
          _author = data['author'];
          _currentQuoteId = data['id'];
          _currentTags = List<String>.from(data['tags'] ?? []);
          _isLoading = false;
        });
        
        // Automatically speak the new quote
        LoggerService.debug('🔊 About to speak quote, _audioEnabled=$_audioEnabled');
        _speakQuote();
      } else if (response.statusCode == 500 && retryCount < 3) {
        // Retry for 500 errors with exponential backoff
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        LoggerService.debug('🔄 Got 500 error, retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/3)');
        
        setState(() {
          _error = 'Server issue, retrying...';
        });
        
        await Future.delayed(delay);
        
        // Recursive retry
        return _getQuote(retryCount: retryCount + 1);
      } else {
        String errorMessage;
        if (response.statusCode == 429) {
          errorMessage = 'Please wait a moment before requesting another quote. You\'ve reached the rate limit - try again in a few seconds! 😊';
        } else if (response.statusCode == 500) {
          errorMessage = 'Server is having issues. Please try again in a moment.';
        } else {
          errorMessage = 'Failed to load quote (${response.statusCode})';
        }
        
        LoggerService.debug('❌ Setting error: $errorMessage');
        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggerService.debug('❌ Network/Parse error in _getQuote: $e');
      LoggerService.debug('❌ Error type: ${e.runtimeType}');
      
      // Retry network errors if we haven't retried too many times
      if (retryCount < 3) {
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        LoggerService.debug('🔄 Network error, retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/3)');
        
        setState(() {
          _error = 'Connection issue, retrying...';
        });
        
        await Future.delayed(delay);
        return _getQuote(retryCount: retryCount + 1);
      }
      
      setState(() {
        _error = 'Network error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Quote Me',
        ),
        centerTitle: true,
        actions: [
          if (_quote != null && _author != null)
            IconButton(
              icon: Icon(
                (!kIsWeb && Platform.isAndroid) 
                  ? Icons.share 
                  : CupertinoIcons.share,
              ),
              onPressed: _shareQuote,
              tooltip: 'Share Quote',
            ),
          PopupMenuButton<String>(
            onOpened: () {
              // Refresh auth status when menu opens to ensure correct options
              _checkAuthStatus();
            },
            onSelected: (value) async {
              switch (value) {
                case 'profile':
                  if (mounted) {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const UserProfileScreen(),
                      ),
                    );
                    // Refresh auth status if profile was updated
                    if (result == true) {
                      _checkAuthStatus();
                    }
                  }
                  break;
                case 'propose':
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProposeQuoteScreen(),
                      ),
                    );
                  }
                  break;
                case 'favorites':
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FavoritesScreen(),
                      ),
                    );
                  }
                  break;
                case 'admin':
                  _openAdmin();
                  break;
                case 'login':
                  if (mounted) {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                    );
                    if (result == true) {
                      _checkAuthStatus();
                    }
                  }
                  break;
                case 'logout':
                  await _handleLogout();
                  break;
                case 'settings':
                  _openSettings();
                  break;
                case 'about':
                  _showAboutDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              // Greeting Section (Registered Users Only)
              if (_isSignedIn && _userName != null) ...[
                PopupMenuItem(
                  enabled: false,
                  child: Row(
                    children: [
                      Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Hi, ${_userName != null && _userName!.isNotEmpty ? _toTitleCase(_userName!) : _userName ?? ''}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
              ],
              
              // Any User Section
              PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 8),
                    Text('About'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 8),
                    Text('Settings'),
                  ],
                ),
              ),
              
              // Registered User Section
              if (_isSignedIn) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Text('Profile'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'favorites',
                  child: Row(
                    children: [
                      Icon(Icons.favorite, color: Colors.red),
                      SizedBox(width: 8),
                      Text('My Favorites'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'propose',
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Text('Propose a Quote'),
                    ],
                  ),
                ),
              ],
              
              // Admin User Section
              if (_isSignedIn && _isAdmin) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'admin',
                  child: Row(
                    children: [
                      Icon(Icons.admin_panel_settings, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Text('Admin Dashboard'),
                    ],
                  ),
                ),
              ],
              
              // Sign Out Section (Registered Users Only)
              if (_isSignedIn) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Sign Out'),
                    ],
                  ),
                ),
              ],
              
              // Anonymous User Section
              if (!_isSignedIn) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'login',
                  child: Row(
                    children: [
                      Icon(Icons.login, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Text('Sign In / Sign Up'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                if (_isLoading)
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  )
                else if (_error != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: AppThemes.errorText(context),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (_quote != null && _author != null)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Card(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.surface,
                              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            children: [
                              Icon(
                                Icons.format_quote,
                                color: Theme.of(context).colorScheme.secondary,
                                size: 32,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _quote!,
                                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(context).colorScheme.primary,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                '— $_author',
                                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_currentQuoteId != null)
                                    FavoriteHeartButton(
                                      quoteId: _currentQuoteId!,
                                      size: 28,
                                    ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: _audioEnabled 
                                      ? () {
                                          LoggerService.debug('🎛️ Audio button pressed - _isSpeaking=$_isSpeaking');
                                          if (_isSpeaking) {
                                            _stopSpeaking();
                                          } else {
                                            _speakQuote();
                                          }
                                        }
                                      : null,
                                    icon: Icon(
                                      _isSpeaking 
                                        ? Icons.stop 
                                        : _audioEnabled 
                                          ? Icons.volume_up 
                                          : Icons.volume_off,
                                      color: _audioEnabled 
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.primary.withValues(alpha: 77),
                                    ),
                                    tooltip: _audioEnabled
                                      ? (_isSpeaking ? 'Stop Reading' : 'Read Quote Aloud')
                                      : 'Audio disabled (enable in settings)',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 77),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Theme.of(context).colorScheme.secondary,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ready for inspiration?',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Press the button below to get a motivational quote!',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 280,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _getQuote,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: Text(
                      _isLoading ? 'Loading...' : 'Get Quote',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shadowColor: Theme.of(context).colorScheme.secondary,
                      elevation: 4,
                    ),
                  ),
                ),
                // Authentication buttons for non-logged-in users
                if (_authCheckComplete && !_isSignedIn) ...[
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      SizedBox(
                        width: 280,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            setState(() {
                              _authCheckComplete = false;
                            });
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(),
                              ),
                            );
                            if (result == true) {
                              await _checkAuthStatus();
                            } else {
                              // Re-enable buttons if login was cancelled
                              setState(() {
                                _authCheckComplete = true;
                              });
                            }
                          },
                          icon: const Icon(Icons.login, size: 20),
                          label: Text(
                            'Sign In',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 280,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            setState(() {
                              _authCheckComplete = false;
                            });
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const LoginScreen(initialMode: 'signup'),
                              ),
                            );
                            if (result == true) {
                              await _checkAuthStatus();
                            } else {
                              // Re-enable buttons if signup was cancelled
                              setState(() {
                                _authCheckComplete = true;
                              });
                            }
                          },
                          icon: const Icon(Icons.person_add, size: 20),
                          label: Text(
                            'Sign Up',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // Daily Nuggets subscription button for logged-in users who aren't subscribed
                if (_authCheckComplete && _isSignedIn && !_isSubscribedToDailyNuggets) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 280,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _authCheckComplete = false;
                        });
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const UserProfileScreen(),
                          ),
                        );
                        // Refresh auth status to check if they subscribed
                        if (result == true) {
                          await _checkAuthStatus();
                        } else {
                          // Re-enable buttons if profile was cancelled
                          setState(() {
                            _authCheckComplete = true;
                          });
                        }
                      },
                      icon: const Icon(Icons.email, size: 20),
                      label: Text(
                        'Subscribe to get daily nuggets delivered to you',
                        style: Theme.of(context).textTheme.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        backgroundColor: Theme.of(context).colorScheme.secondary,
                        foregroundColor: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ),
                ],
                        ],
                      ),
                    ),
                  ),
                )
              );
            },
          ),
        ),
      ),
    );
  }
}