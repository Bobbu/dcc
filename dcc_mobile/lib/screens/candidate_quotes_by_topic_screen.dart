import 'package:flutter/material.dart';
import '../services/openai_quote_finder_service.dart';
import '../services/admin_api_service.dart';
import '../services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CandidateQuotesByTopicScreen extends StatefulWidget {
  const CandidateQuotesByTopicScreen({super.key});

  @override
  State<CandidateQuotesByTopicScreen> createState() => _CandidateQuotesByTopicScreenState();
}

class _CandidateQuotesByTopicScreenState extends State<CandidateQuotesByTopicScreen> {
  final TextEditingController _topicController = TextEditingController();
  bool _isLoading = false;
  bool _isAdding = false;
  List<Map<String, dynamic>> _candidateQuotes = [];
  List<bool> _selectedQuotes = [];
  String _searchedTopic = '';
  int _maxReturnedQuotes = 5;
  
  @override
  void initState() {
    super.initState();
    _loadMaxReturnedQuotes();
  }
  
  Future<void> _loadMaxReturnedQuotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final limit = prefs.getInt('max_returned_quotes') ?? 5;
      setState(() {
        _maxReturnedQuotes = limit;
      });
    } catch (e) {
      LoggerService.error('Failed to load max returned quotes limit: $e');
    }
  }

  Future<void> _fetchCandidateQuotes() async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a topic')),
      );
      return;
    }

    // Extract ScaffoldMessenger before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() {
      _isLoading = true;
      _candidateQuotes = [];
      _selectedQuotes = [];
      _searchedTopic = topic;
    });

    try {
      final result = await OpenAIQuoteFinderService.fetchCandidateQuotesByTopic(topic, limit: _maxReturnedQuotes);
      
      if (!mounted) return;
      
      setState(() {
        _candidateQuotes = List<Map<String, dynamic>>.from(result['quotes'] ?? []);
        _selectedQuotes = List<bool>.generate(_candidateQuotes.length, (_) => false, growable: true);
        _isLoading = false;
      });

      if (_candidateQuotes.isEmpty) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('No quotes found for topic: $topic')),
        );
      }
    } catch (e) {
      LoggerService.error('Error fetching candidate quotes by topic: $e', error: e);
      
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      
      scaffoldMessenger.showSnackBar(
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

    // Extract ScaffoldMessenger before async operations
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    setState(() {
      _isAdding = true;
    });

    int successCount = 0;
    int failCount = 0;
    List<int> successfulIndices = [];

    try {
      for (final index in selectedIndices) {
        final quote = _candidateQuotes[index];
        final quoteText = quote['quote'] ?? '';
        final authorText = quote['author'] ?? '';
        
        try {
          // Server-side duplicate checking is now handled in the create quote endpoint
          final result = await AdminApiService.createQuote(
            quote: quoteText,
            author: authorText,
            tags: [], // Leave untagged for "Generate tags for the tagless" to process
          );
          
          // Check if this was a duplicate detection
          if (result['isDuplicate'] == true) {
            // Skip duplicate quotes automatically in batch operations
            failCount++;
            final truncated = quoteText.length > 50 ? quoteText.substring(0, 50) + '...' : quoteText;
            LoggerService.info('⏭️ Skipped duplicate quote: "$truncated"');
          } else {
            // Normal successful creation
            successCount++;
            successfulIndices.add(index);
            final truncated = quoteText.length > 50 ? quoteText.substring(0, 50) + '...' : quoteText;
            LoggerService.info('✅ Successfully added quote: "$truncated"');
          }
        } catch (e) {
          failCount++;
          LoggerService.error('❌ Failed to add quote: $e', error: e);
        }

        // Add a small delay to prevent overwhelming the API
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (!mounted) return;
      
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

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: successCount > 0 ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isAdding = false;
      });
      
      LoggerService.error('❌ Error in _addSelectedQuotes: $e', error: e);
      scaffoldMessenger.showSnackBar(
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
        title: const Text('Find New Quotes by Topic'),
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
                    controller: _topicController,
                    decoration: InputDecoration(
                      labelText: 'Topic',
                      hintText: 'e.g., leadership, success, happiness',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: Icon(Icons.topic, color: theme.colorScheme.primary),
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
                    'Found ${_candidateQuotes.length} quote${_candidateQuotes.length > 1 ? 's' : ''} about $_searchedTopic',
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
          ] else if (_searchedTopic.isNotEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No quotes found for topic "$_searchedTopic"',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching for a different topic',
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
                      'Discover Quotes by Topic',
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter a topic to find relevant quotes',
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
                              '1. Enter a topic or theme\n'
                              '2. AI searches for relevant quotes from various authors\n'
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
    _topicController.dispose();
    super.dispose();
  }
}