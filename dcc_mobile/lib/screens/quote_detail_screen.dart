import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Rect;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:share_plus/share_plus.dart';
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

  static final String baseApiUrl = dotenv.env['API_URL'] ?? 'https://dcc.anystupididea.com';
  static final String apiKey = dotenv.env['API_KEY'] ?? '';

  @override
  void initState() {
    super.initState();
    _fetchQuote();
  }

  Future<void> _fetchQuote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      print('🔍 Fetching quote with ID: ${widget.quoteId}');
      
      final response = await http.get(
        Uri.parse('$baseApiUrl/quote/${widget.quoteId}'),
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      );

      print('📡 Quote detail response: ${response.statusCode}');

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
      print('❌ Error fetching quote: $e');
      setState(() {
        _error = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _shareQuote() async {
    if (_quote == null || _author == null) return;
    
    print('🔄 Starting share process...');
    print('  Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}');
    if (!kIsWeb) {
      print('  Platform version: ${Platform.operatingSystemVersion}');
    }
    
    final shareText = StringBuffer();
    
    shareText.writeln('"$_quote"');
    shareText.writeln('- $_author');
    
    if (_tags.isNotEmpty) {
      shareText.writeln('Tags: ${_tags.join(", ")}');
    }
    
    shareText.writeln();
    shareText.writeln('View this quote: https://quote-me.anystupididea.com/quote/${widget.quoteId}');
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
        title: const Text(
          'Quote Me',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8EAF6), // Light indigo background
              Color(0xFFF3E5F5), // Light purple background
            ],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading quote...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF3F51B5),
                        ),
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
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3F51B5),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This quote may have been removed or the link is invalid.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: _fetchQuote,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3F51B5),
                                    foregroundColor: Colors.white,
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
                                    side: const BorderSide(color: Color(0xFF3F51B5)),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text(
                                    'Browse Quotes',
                                    style: TextStyle(color: Color(0xFF3F51B5)),
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
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Quote text
                                  Text(
                                    '"$_quote"',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF2C2C2C),
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  
                                  const SizedBox(height: 20),
                                  
                                  // Author
                                  Text(
                                    '— $_author',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF3F51B5),
                                    ),
                                  ),
                                  
                                  // Tags if available
                                  if (_tags.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: _tags.map((tag) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF3F51B5).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: const Color(0xFF3F51B5).withOpacity(0.3),
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF3F51B5),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 32),
                            
                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _shareQuote,
                                  icon: Icon(
                                    (!kIsWeb && Platform.isAndroid) 
                                      ? Icons.share 
                                      : CupertinoIcons.share,
                                  ),
                                  label: const Text('Share'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF3F51B5),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  onPressed: _navigateToMainApp,
                                  icon: const Icon(Icons.explore),
                                  label: const Text('On to home page for fun'),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF3F51B5)),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // App promotion
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3F51B5).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF3F51B5).withOpacity(0.3),
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    color: Color(0xFF3F51B5),
                                    size: 24,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'You like-a the quotes?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3F51B5),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'You will be able to soon get the full Quote Me app for daily inspiration and more features',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF3F51B5),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
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