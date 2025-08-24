import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
import '../services/logger_service.dart';
import '../services/share_service.dart';
import '../themes.dart';
import '../widgets/favorite_heart_button.dart';
import 'quote_screen.dart';


class QuoteDetailScreen extends StatefulWidget {
  final String quoteId;

  const QuoteDetailScreen({
    super.key,
    required this.quoteId,
  });

  @override
  State<QuoteDetailScreen> createState() => _QuoteDetailScreenState();
}

class _QuoteDetailScreenState extends State<QuoteDetailScreen> {
  String? _quote;
  String? _author;
  List<String> _tags = [];
  bool _isLoading = true;
  String? _error;
  Timer? _redirectTimer;
  int _secondsRemaining = 30;

  static final String baseApiUrl = dotenv.env['API_URL'] ?? 'https://dcc.anystupididea.com';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _fetchQuote();
    _startRedirectTimer();
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  void _startRedirectTimer() {
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsRemaining--;
        });
        
        if (_secondsRemaining <= 0) {
          timer.cancel();
          _navigateToMainApp();
        }
      }
    });
  }

  Future<void> _fetchQuote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      LoggerService.debug('🔍 Fetching quote with ID: ${widget.quoteId}');
      
      final response = await http.get(
        Uri.parse('$baseApiUrl/quote/${widget.quoteId}'),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      );

      LoggerService.debug('📡 Quote detail response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _quote = data['quote'];
          _author = data['author'];
          _tags = List<String>.from(data['tags'] ?? []);
          _isLoading = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _error = 'Quote not found';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load quote';
          _isLoading = false;
        });
      }
    } catch (e) {
      LoggerService.error('❌ Error fetching quote', error: e);
      setState(() {
        _error = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _shareQuote() async {
    if (_quote == null || _author == null) return;
    
    await ShareService.shareQuote(
      context: context,
      quote: _quote!,
      author: _author!,
      quoteId: widget.quoteId,
      tags: _tags,
    );
  }

  void _navigateToMainApp() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const QuoteScreen(),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quote Me'),
        centerTitle: true,
        actions: [
          if (!_isLoading && _quote != null)
            IconButton(
              icon: Icon(
                (!kIsWeb && Platform.isAndroid) 
                  ? Icons.share 
                  : CupertinoIcons.share,
              ),
              onPressed: _shareQuote,
              tooltip: 'Share Quote',
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
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Loading quote...',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This quote may have been removed or the link is invalid.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: _fetchQuote,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Retry'),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton(
                                  onPressed: _navigateToMainApp,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: Text(
                                    'Browse Quotes',
                                    style: AppThemes.linkText(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 32),
                            
                            // Quote Card
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                children: [
                                  // Quote text
                                  Text(
                                    '"$_quote"',
                                    style: Theme.of(context).textTheme.headlineLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Author
                                  Text(
                                    '— $_author',
                                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                  
                                  // Tags if available
                                  if (_tags.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _tags.map((tag) {
                                        return Chip(
                                          label: Text(tag),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 32),
                            
                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FavoriteHeartButton(
                                  quoteId: widget.quoteId,
                                  size: 28,
                                ),
                                const SizedBox(width: 16),
                                ElevatedButton.icon(
                                  onPressed: _shareQuote,
                                  icon: Icon(
                                    (!kIsWeb && Platform.isAndroid) 
                                      ? Icons.share 
                                      : CupertinoIcons.share,
                                  ),
                                  label: const Text('Share'),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    _redirectTimer?.cancel();
                                    _navigateToMainApp();
                                  },
                                  icon: const Icon(Icons.explore),
                                  label: Text('Go to home ($_secondsRemaining s)'),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Countdown message
                            Text(
                              'Redirecting to home in $_secondsRemaining seconds...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // App promotion
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.favorite,
                                      color: Theme.of(context).colorScheme.primary,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'You like-a the quotes?',
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'You will be able to soon get the full Quote Me app for daily inspiration and more features',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}