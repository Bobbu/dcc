import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/openai_quote_finder_service.dart';
import '../services/admin_api_service.dart';
import '../services/logger_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CandidateQuotesScreen extends StatefulWidget {
  const CandidateQuotesScreen({Key? key}) : super(key: key);

  @override
  _CandidateQuotesScreenState createState() => _CandidateQuotesScreenState();
}

class _CandidateQuotesScreenState extends State<CandidateQuotesScreen> {
  final TextEditingController _authorController = TextEditingController();
  bool _isLoading = false;
  bool _isAdding = false;
  List<Map<String, dynamic>> _candidateQuotes = [];
  List<bool> _selectedQuotes = [];
  String _searchedAuthor = '';

  Future<void> _fetchCandidateQuotes() async {
    final author = _authorController.text.trim();
    if (author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an author name')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _candidateQuotes = [];
      _selectedQuotes = [];
      _searchedAuthor = author;
    });

    try {
      final result = await OpenAIQuoteFinderService.fetchCandidateQuotes(author);
      
      setState(() {
        _candidateQuotes = List<Map<String, dynamic>>.from(result['quotes'] ?? []);
        _selectedQuotes = List<bool>.generate(_candidateQuotes.length, (_) => false, growable: true);
        _isLoading = false;
      });

      if (_candidateQuotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No quotes found for $author')),
        );
      }
    } catch (e) {
      LoggerService.error('Error fetching candidate quotes: $e', error: e);
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch quotes: ${e.toString()}')),
      );
    }
  }

  Future<void> _addSelectedQuotes() async {
    final selectedIndices = <int>[];
    for (int i = 0; i < _selectedQuotes.length; i++) {
      if (_selectedQuotes[i]) {
        selectedIndices.add(i);
      }
    }

    if (selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one quote to add')),
      );
      return;
    }

    setState(() {
      _isAdding = true;
    });

    int successCount = 0;
    int failCount = 0;
    List<int> successfulIndices = [];

    try {
      for (final index in selectedIndices) {
        final quote = _candidateQuotes[index];
        
        try {
          // Use AdminApiService.createQuote() method
          await AdminApiService.createQuote(
            quote: quote['quote'] ?? '',
            author: quote['author'] ?? '',
            tags: [], // Leave untagged for "Generate tags for the tagless" to process
          );
          
          successCount++;
          successfulIndices.add(index);
          final quoteText = quote['quote'] ?? '';
          final truncated = quoteText.length > 50 ? quoteText.substring(0, 50) + '...' : quoteText;
          LoggerService.info('✅ Successfully added quote: "$truncated"');
        } catch (e) {
          failCount++;
          LoggerService.error('❌ Failed to add quote: $e', error: e);
        }

        // Add a small delay to prevent overwhelming the API
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _isAdding = false;
        
        // Remove successfully added quotes (sort in descending order first to maintain indices)
        successfulIndices.sort((a, b) => b.compareTo(a));
        for (final indexToRemove in successfulIndices) {
          _candidateQuotes.removeAt(indexToRemove);
          _selectedQuotes.removeAt(indexToRemove);
        }
      });

      // Show results to user
      String message = '';
      if (successCount > 0) {
        message = 'Successfully added $successCount quote${successCount > 1 ? 's' : ''}';
      }
      if (failCount > 0) {
        message += '${message.isNotEmpty ? ', ' : ''}Failed to add $failCount quote${failCount > 1 ? 's' : ''}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      setState(() {
        _isAdding = false;
      });
      
      LoggerService.error('❌ Error in _addSelectedQuotes: $e', error: e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add quotes: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildQuoteCard(Map<String, dynamic> quote, int index) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: CheckboxListTile(
        value: _selectedQuotes[index],
        onChanged: (bool? value) {
          setState(() {
            _selectedQuotes[index] = value ?? false;
          });
        },
        title: Text(
          '"${quote['quote']}"',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontStyle: FontStyle.italic,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              '— ${quote['author']}',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (quote['source'] != null)
              Text(
                'Source: ${quote['source']}',
                style: theme.textTheme.bodyMedium,
              ),
            if (quote['year'] != null)
              Text(
                'Year: ${quote['year']}',
                style: theme.textTheme.bodyMedium,
              ),
            if (quote['confidence'] != null)
              Chip(
                label: Text(
                  quote['confidence'].toString().toUpperCase(),
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: _getConfidenceColor(quote['confidence'], theme),
                labelStyle: const TextStyle(color: Colors.white),
              ),
          ],
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  IconData _getConfidenceIcon(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return Icons.verified;
      case 'medium':
        return Icons.help_outline;
      case 'low':
        return Icons.warning_amber;
      default:
        return Icons.help_outline;
    }
  }

  Color _getConfidenceColor(String confidence, ThemeData theme) {
    switch (confidence.toLowerCase()) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.red;
      default:
        return theme.colorScheme.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedCount = _selectedQuotes.where((selected) => selected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Find New Quotes'),
      ),
      floatingActionButton: (_candidateQuotes.isNotEmpty && selectedCount > 0)
          ? FloatingActionButton.extended(
              onPressed: (_isLoading || _isAdding) ? null : _addSelectedQuotes,
              icon: const Icon(Icons.add),
              label: Text('Add $selectedCount Quote${selectedCount > 1 ? 's' : ''}'),
            )
          : null,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _authorController,
                    decoration: InputDecoration(
                      labelText: 'Author Name',
                      hintText: 'e.g., Albert Einstein',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: Icon(Icons.person, color: theme.colorScheme.primary),
                    ),
                    onSubmitted: (_) => _fetchCandidateQuotes(),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _fetchCandidateQuotes,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoading || _isAdding)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_isAdding ? 'Adding selected quotes...' : 'Searching for quotes...'),
                  ],
                ),
              ),
            )
          else if (_candidateQuotes.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  Text(
                    'Found ${_candidateQuotes.length} quote${_candidateQuotes.length > 1 ? 's' : ''} by $_searchedAuthor',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  if (selectedCount > 0)
                    Text(
                      '$selectedCount selected',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _candidateQuotes.length,
                itemBuilder: (context, index) {
                  return _buildQuoteCard(_candidateQuotes[index], index);
                },
              ),
            ),
          ] else if (_searchedAuthor.isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: theme.colorScheme.primary.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No quotes found for "$_searchedAuthor"',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for a different author',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Discover New Quotes',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter an author name to find authentic quotes',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'How it works',
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '1. Enter an author\'s name\n'
                              '2. AI searches for authentic quotes\n'
                              '3. Review quotes with sources and context\n'
                              '4. Select the ones you want to add\n'
                              '5. Quotes are added to your collection',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _authorController.dispose();
    super.dispose();
  }
}