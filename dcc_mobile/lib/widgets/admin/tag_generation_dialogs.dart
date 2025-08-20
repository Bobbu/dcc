import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../../models/quote.dart';
import '../../services/auth_service.dart';
import '../../services/openai_proxy_service.dart';
import '../../services/logger_service.dart';
import '../../themes.dart';

class GenerateTagsDialog extends StatelessWidget {
  final VoidCallback onGenerate;

  const GenerateTagsDialog({
    super.key,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.purple),
          SizedBox(width: 8),
          Text('Generate Tags for Tagless Quotes'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will use AI to automatically generate up to 5 relevant tags for quotes that currently have no tags.',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 12),
          Text(
            'Features:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 4),
          Text('• Analyzes quote content and author'),
          Text('• Generates 1-5 relevant tags per quote'),
          Text('• Prefers existing tags when applicable'),
          Text('• Uses professional tag formatting'),
          SizedBox(height: 12),
          Text(
            'Note: This requires an OpenAI API key to be configured.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            onGenerate();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
          ),
          child: const Text('Generate Tags'),
        ),
      ],
    );
  }
}

class GenerateTagsProgressDialog extends StatefulWidget {
  final List<Quote> quotes;
  final List<String> existingTags;
  final Function(Map<String, dynamic>) onComplete;

  const GenerateTagsProgressDialog({
    super.key,
    required this.quotes,
    required this.existingTags,
    required this.onComplete,
  });

  @override
  State<GenerateTagsProgressDialog> createState() => _GenerateTagsProgressDialogState();
}

class _GenerateTagsProgressDialogState extends State<GenerateTagsProgressDialog> {
  int _currentIndex = 0;
  int _successful = 0;
  int _failed = 0;
  final List<String> _errors = [];
  List<String> _recentTags = [];
  bool _isProcessing = true;
  String _currentStatus = 'Initializing...';
  String _lastQuote = '';
  String _lastAuthor = '';
  List<String> _lastGeneratedTags = [];

  @override
  void initState() {
    super.initState();
    _startTagGeneration();
  }

  Future<void> _startTagGeneration() async {
    const batchSize = 5; // Process 5 quotes at a time
    
    int startIndex = 0;
    
    while (startIndex < widget.quotes.length && mounted) {
      final endIndex = (startIndex + batchSize).clamp(0, widget.quotes.length);
      final currentBatch = widget.quotes.sublist(startIndex, endIndex);
      
      // Process current batch
      for (int i = 0; i < currentBatch.length && mounted; i++) {
        final quote = currentBatch[i];
        final globalIndex = startIndex + i;
        
        setState(() {
          _currentIndex = globalIndex;
          _currentStatus = 'Generating tags for quote ${globalIndex + 1} of ${widget.quotes.length}...';
        });

        try {
          // Generate tags using our secure AWS proxy
          final tags = await OpenAIProxyService.generateTagsForQuote(
            quote: quote.quote,
            author: quote.author,
            existingTags: widget.existingTags,
          );

          if (tags.isNotEmpty) {
            // Update the quote with generated tags
            await _updateQuoteWithTags(quote, tags);
            setState(() {
              _successful++;
              _recentTags.addAll(tags);
              // Keep only last 15 tags to show recent examples
              if (_recentTags.length > 15) {
                _recentTags = _recentTags.sublist(_recentTags.length - 15);
              }
              // Store the last processed quote details for display during delay
              _lastQuote = quote.quote;
              _lastAuthor = quote.author;
              _lastGeneratedTags = tags;
            });
          } else {
            setState(() {
              _failed++;
              _errors.add('No tags generated for: "${quote.quote.substring(0, 50)}..."');
            });
          }
        } catch (e) {
          setState(() {
            _failed++;
            _errors.add('Error for "${quote.quote.substring(0, 50)}...": ${e.toString()}');
          });
          LoggerService.error('Error generating tags for quote ${quote.id}', error: e);
        }

        // Add delay between requests to avoid rate limiting
        if (i < currentBatch.length - 1 && mounted) {
          for (int countdown = 5; countdown > 0 && mounted; countdown--) {
            setState(() {
              _currentStatus = 'Waiting ${countdown}s before next quote to avoid rate limits...';
            });
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
      
      // Move to next batch
      startIndex = endIndex;
      
      // If there are more quotes to process, pause and ask for confirmation
      if (startIndex < widget.quotes.length && mounted) {
        setState(() {
          _isProcessing = false;
          _currentStatus = 'Batch complete! Processed $endIndex of ${widget.quotes.length} quotes.';
        });
        
        // Wait for user input before continuing
        final shouldContinue = await _showContinueDialog();
        if (!shouldContinue || !mounted) {
          break;
        }
        
        setState(() {
          _isProcessing = true;
          _currentStatus = 'Resuming tag generation...';
        });
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _currentStatus = 'Complete!';
      });

      // Show the last processed quote and its tags for 5 seconds before dismissing
      if (_lastQuote.isNotEmpty && _lastGeneratedTags.isNotEmpty) {
        for (int countdown = 5; countdown > 0 && mounted; countdown--) {
          setState(() {
            _currentStatus = 'Complete! Closing in ${countdown}s...';
          });
          await Future.delayed(const Duration(seconds: 1));
        }
      } else {
        // If no quotes were processed, just wait briefly
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (mounted) {
        widget.onComplete({
          'successful': _successful,
          'failed': _failed,
          'errors': _errors,
        });
      }
    }
  }

  Future<bool> _showContinueDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('Batch Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Processed batch successfully!'),
            const SizedBox(height: 8),
            Text('✅ Successful: $_successful'),
            Text('❌ Failed: $_failed'),
            const SizedBox(height: 8),
            Text('${widget.quotes.length - (_currentIndex + 1)} quotes remaining.'),
            if (_recentTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Recent tags generated:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _recentTags.toSet().toList().join(', '),
                  style: const TextStyle(fontSize: 11, color: Colors.purple),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text('Continue with next batch of 5 quotes?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stop Here'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<void> _updateQuoteWithTags(Quote quote, List<String> tags) async {
    try {
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${await AuthService.getIdToken()}',
      };

      final baseUrl = dotenv.env['API_URL'] ?? 'https://dcc.anystupididea.com';
      final response = await http.put(
        Uri.parse('$baseUrl/admin/quotes/${quote.id}'),
        headers: headers,
        body: json.encode({
          'quote': quote.quote,
          'author': quote.author,
          'tags': tags,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update quote: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.error('Error updating quote with tags', error: e);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.quotes.isEmpty ? 1.0 : (_currentIndex + 1) / widget.quotes.length;
    
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.auto_awesome, color: Colors.purple),
          SizedBox(width: 8),
          Text('Generating Tags'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_currentStatus),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade300,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.purple),
            ),
            const SizedBox(height: 8),
            Text(
              'Progress: ${_currentIndex + (_isProcessing ? 0 : 1)} of ${widget.quotes.length}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text('Successful: $_successful'),
                const SizedBox(width: 16),
                const Icon(Icons.error, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text('Failed: $_failed'),
              ],
            ),
            if (_lastQuote.isNotEmpty && _lastGeneratedTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  border: Border.all(color: Colors.purple.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last processed:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '"${_lastQuote.length > 80 ? '${_lastQuote.substring(0, 80)}...' : _lastQuote}"',
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '— $_lastAuthor',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: _lastGeneratedTags.map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.purple.shade300),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.purple.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ],
            if (_errors.isNotEmpty && _errors.length <= 3) ...[
              const SizedBox(height: 8),
              Text(
                'Recent errors:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              ..._errors.take(3).map((error) => Text(
                '• $error',
                style: AppThemes.errorText(context).copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isProcessing)
          TextButton(
            onPressed: () {
              widget.onComplete({
                'successful': _successful,
                'failed': _failed,
                'errors': _errors,
              });
            },
            child: const Text('Close'),
          )
        else
          const TextButton(
            onPressed: null,
            child: Text('Processing...'),
          ),
      ],
    );
  }
}