import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../services/share_service.dart';
import '../themes.dart';
import 'admin_dashboard_screen.dart';
import 'user_profile_screen.dart';
import 'propose_quote_screen.dart';


class QuoteScreen extends StatefulWidget {
  const QuoteScreen({super.key});

  @override
  State<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends State<QuoteScreen> {
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

  static final String apiEndpoint = dotenv.env['API_ENDPOINT'] ?? '';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadSettings();
    _checkAuthStatus();
  }
  
  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }
  
  Future<void> _checkAuthStatus() async {
    final isSignedIn = await AuthService.isSignedIn();
    if (isSignedIn) {
      final isAdmin = await AuthService.isUserInAdminGroup();
      final userName = await AuthService.getUserName();
      setState(() {
        _isSignedIn = true;
        _isAdmin = isAdmin;
        _userName = userName;
      });
    } else {
      // Clear state when not signed in
      setState(() {
        _isSignedIn = false;
        _isAdmin = false;
        _userName = null;
      });
    }
  }

  Future<void> _handleLogout() async {
    await AuthService.signOut();
    if (mounted) {
      setState(() {
        _isSignedIn = false;
        _isAdmin = false;
        _userName = null;
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
                        '© 2025 Quote Me App\nAll rights reserved.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 179),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Quote Me is your daily source of inspiration and motivation. '
                        'Discover wisdom from great thinkers, leaders, and authors throughout history.',
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
                          '• Filter by categories and tags\n'
                          '• Text-to-speech with customizable voices\n'
                          '• Share quotes with friends\n'
                          '• Propose your favorite quotes\n'
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 179),
                        ),
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

  @override
  void dispose() {
    try {
      flutterTts.stop();
    } catch (e) {
      LoggerService.debug('Error stopping TTS in dispose: $e');
    }
    super.dispose();
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
          onSettingsChanged: (audioEnabled, categories, voice, speechRate, pitch, quoteRetrievalLimit) {
            setState(() {
              _audioEnabled = audioEnabled;
              _selectedCategories = categories;
              _selectedVoice = voice;
              _speechRate = speechRate;
              _pitch = pitch;
              _quoteRetrievalLimit = quoteRetrievalLimit;
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
    // Check if user is already signed in as admin
    final isSignedIn = await AuthService.isSignedIn();
    if (isSignedIn && await AuthService.isUserInAdminGroup()) {
      // Already signed in as admin, go directly to dashboard
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AdminDashboardScreen(),
          ),
        );
      }
    } else {
      // Not signed in or not admin, show login screen
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LoginScreen(),
          ),
        );
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
        url += '?' + queryParams.join('&');
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
          IconButton(
            icon: Icon(
              (!kIsWeb && Platform.isAndroid) 
                ? Icons.share 
                : CupertinoIcons.share,
            ),
            onPressed: _shareQuote,
            tooltip: 'Share Quote',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: 'Settings',
          ),
          PopupMenuButton<String>(
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
                case 'about':
                  _showAboutDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (_isSignedIn) ...[
                if (_userName != null)
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
                if (_userName != null)
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
                  value: 'propose',
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 8),
                      Text('Propose a Quote'),
                    ],
                  ),
                ),
                if (_isAdmin)
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
                const PopupMenuDivider(),
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
              ] else ...[
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
                ElevatedButton.icon(
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