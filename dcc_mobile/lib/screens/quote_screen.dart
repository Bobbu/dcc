import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Rect;
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
import 'settings_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import 'admin_dashboard_screen.dart';


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
  bool _audioEnabled = true;
  Set<String> _selectedCategories = {'All'};
  Map<String, String>? _selectedVoice;
  double _speechRate = 0.5;
  double _pitch = 1.0;
  
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
    }
  }

  void _initTts() {
    flutterTts = FlutterTts();
    
    flutterTts.setStartHandler(() {
      print('🔊 TTS Start Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
    });

    flutterTts.setCompletionHandler(() {
      print('✅ TTS Completion Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setErrorHandler((msg) {
      print('❌ TTS Error Handler triggered: $msg');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setCancelHandler(() {
      print('🛑 TTS Cancel Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setPauseHandler(() {
      print('⏸️ TTS Pause Handler triggered');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    });

    flutterTts.setContinueHandler(() {
      print('▶️ TTS Continue Handler triggered');
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
    print('🔊 _speakQuote() called - _audioEnabled=$_audioEnabled, _quote=${_quote != null}, _author=${_author != null}');
    
    if (_audioEnabled && _quote != null && _author != null) {
      String textToSpeak = '$_quote, by $_author';
      final previewLength = textToSpeak.length > 50 ? 50 : textToSpeak.length;
      print('🎤 About to speak: "${textToSpeak.substring(0, previewLength)}..."');
      
      // Manually set speaking state (in case TTS handlers don't fire in simulator)
      if (mounted) {
        setState(() {
          _isSpeaking = true;
        });
      }
      
      try {
        await flutterTts.speak(textToSpeak);
        print('✅ TTS speak() called successfully');
        
        // For simulator compatibility: auto-reset speaking state after estimated time
        // Calculate rough duration: assume 150 words per minute
        final wordCount = textToSpeak.split(' ').length;
        final estimatedDurationMs = (wordCount / 150 * 60 * 1000).round();
        final maxDurationMs = estimatedDurationMs + 2000; // Add 2 second buffer
        
        Timer(Duration(milliseconds: maxDurationMs), () {
          if (mounted && _isSpeaking) {
            print('⏰ Auto-resetting speaking state after timeout');
            setState(() {
              _isSpeaking = false;
            });
          }
        });
        
      } catch (e) {
        print('❌ Error in _speakQuote: $e');
        if (mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      }
    } else {
      print('⏹️ Not speaking because: audioEnabled=$_audioEnabled, quote=${_quote != null}, author=${_author != null}');
    }
  }

  void _stopSpeaking() async {
    print('🛑 _stopSpeaking() called - current _isSpeaking=$_isSpeaking');
    
    try {
      await flutterTts.stop();
      print('✅ TTS stop() called successfully in _stopSpeaking');
      
      // Force state update in case handlers don't fire
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    } catch (e) {
      print('❌ Error stopping TTS in _stopSpeaking: $e');
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
      print('Error stopping TTS in dispose: $e');
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _audioEnabled = prefs.getBool('audio_enabled') ?? true;
      final categories = prefs.getStringList('selected_categories') ?? ['All'];
      _selectedCategories = Set<String>.from(categories);
      
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
          onSettingsChanged: (audioEnabled, categories, voice, speechRate, pitch) {
            setState(() {
              _audioEnabled = audioEnabled;
              _selectedCategories = categories;
              _selectedVoice = voice;
              _speechRate = speechRate;
              _pitch = pitch;
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
    print('🔄 Starting share process...');
    print('  Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}');
    if (!kIsWeb) {
      print('  Platform version: ${Platform.operatingSystemVersion}');
    }
    
    if (_quote == null || _author == null || _currentQuoteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No quote to share yet. Please wait for a quote to load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final shareText = StringBuffer();
    
    // Build share text with Option B format
    shareText.writeln('"$_quote"');
    shareText.writeln('- $_author');
    
    // Add tags if available
    if (_currentTags.isNotEmpty) {
      shareText.writeln('Tags: ${_currentTags.join(", ")}');
    }
    
    shareText.writeln();
    shareText.writeln('View this quote: https://quote-me.anystupididea.com/quote/$_currentQuoteId');
    shareText.writeln();
    shareText.writeln('Shared from Quote Me');
    
    try {
      await Share.share(
        shareText.toString(),
        subject: 'Quote by $_author',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100), // Required for iPad popover positioning
      );
      print('✅ Share completed successfully');
    } catch (e) {
      print('❌ Share error details:');
      print('  Error type: ${e.runtimeType}');
      print('  Error message: $e');
      print('  Stack trace: ${StackTrace.current}');
      
      if (kIsWeb) {
        // Web fallback: try clipboard
        try {
          await Clipboard.setData(ClipboardData(text: shareText.toString()));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Quote copied to clipboard!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (clipboardError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to share quote. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Native device fallback: try clipboard then show error
        try {
          await Clipboard.setData(ClipboardData(text: shareText.toString()));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Share failed. Quote copied to clipboard instead.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } catch (clipboardError) {
          print('❌ Clipboard error: $clipboardError');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to share quote. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _getQuote({int retryCount = 0}) async {
    print('🎯 _getQuote() called - Current state: _isLoading=$_isLoading, _isSpeaking=$_isSpeaking, retry=$retryCount');
    
    // Stop any currently playing audio - wrap in try-catch to handle interruption errors
    try {
      print('🔇 Attempting to stop TTS...');
      await flutterTts.stop();
      print('✅ TTS stop completed successfully');
    } catch (e) {
      print('❌ Error stopping TTS: $e');
      // Continue anyway - the error shouldn't prevent getting a new quote
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
      _isSpeaking = false; // Reset speaking state
    });

    try {
      // Build URL with tag filtering
      String url = apiEndpoint;
      if (!_selectedCategories.contains('All') && _selectedCategories.isNotEmpty) {
        final tags = _selectedCategories.join(',');
        url += '?tags=$tags';
      }
      
      print('🌐 Making API request to: $url');
      print('📋 Selected categories: $_selectedCategories');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      );
      
      print('📡 API Response: ${response.statusCode}');
      if (response.statusCode != 200) {
        print('❌ API Error Body: ${response.body}');
      }
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quoteText = data['quote']?.toString() ?? 'null';
        final previewLength = quoteText.length > 50 ? 50 : quoteText.length;
        print('✅ Quote received: "${quoteText.substring(0, previewLength)}..."');
        
        setState(() {
          _quote = data['quote'];
          _author = data['author'];
          _currentQuoteId = data['id'];
          _currentTags = List<String>.from(data['tags'] ?? []);
          _isLoading = false;
        });
        
        // Automatically speak the new quote
        print('🔊 About to speak quote, _audioEnabled=$_audioEnabled');
        _speakQuote();
      } else if (response.statusCode == 500 && retryCount < 3) {
        // Retry for 500 errors with exponential backoff
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        print('🔄 Got 500 error, retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/3)');
        
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
        
        print('❌ Setting error: $errorMessage');
        setState(() {
          _error = errorMessage;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Network/Parse error in _getQuote: $e');
      print('❌ Error type: ${e.runtimeType}');
      
      // Retry network errors if we haven't retried too many times
      if (retryCount < 3) {
        final delay = Duration(milliseconds: 500 * (retryCount + 1));
        print('🔄 Network error, retrying in ${delay.inMilliseconds}ms (attempt ${retryCount + 1}/3)');
        
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).appBarTheme.foregroundColor,
          ),
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
                case 'admin':
                  _openAdmin();
                  break;
                case 'login':
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  );
                  if (result == true) {
                    _checkAuthStatus();
                  }
                  break;
                case 'logout':
                  await AuthService.signOut();
                  setState(() {
                    _isSignedIn = false;
                    _isAdmin = false;
                    _userName = null;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Signed out successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
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
                        Icon(Icons.person, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Hi, $_userName',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (_userName != null)
                  const PopupMenuDivider(),
                if (_isAdmin)
                  const PopupMenuItem(
                    value: 'admin',
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings),
                        SizedBox(width: 8),
                        Text('Admin Dashboard'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout),
                      SizedBox(width: 8),
                      Text('Sign Out'),
                    ],
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'login',
                  child: Row(
                    children: [
                      Icon(Icons.login),
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
              const Color(0xFFE8EAF6), // Light indigo
              const Color(0xFFE8EAF6), // Light indigo (consistent)
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
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
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
                              Colors.white,
                              const Color(0xFFE8EAF6).withOpacity(0.5),
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
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: const Color(0xFF3F51B5),
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondary.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '— $_author',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF3F51B5),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    onPressed: _audioEnabled 
                                      ? () {
                                          print('🎛️ Audio button pressed - _isSpeaking=$_isSpeaking');
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
                                        : Theme.of(context).colorScheme.primary.withOpacity(0.3),
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
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
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
                            color: const Color(0xFF3F51B5),
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Press the button below to get a motivational quote!',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFF3F51B5).withOpacity(0.8),
                          ),
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shadowColor: Theme.of(context).colorScheme.secondary.withOpacity(0.3),
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