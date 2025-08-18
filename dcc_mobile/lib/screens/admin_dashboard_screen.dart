import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../helpers/download_helper_stub.dart'
    if (dart.library.html) '../helpers/download_helper_web.dart';
import '../services/auth_service.dart';
import '../services/openai_proxy_service.dart';
import 'tags_editor_screen.dart';

class Quote {
  final String id;
  final String quote;
  final String author;
  final List<String> tags;
  final String createdAt;
  final String updatedAt;
  final String? createdBy;

  Quote({
    required this.id,
    required this.quote,
    required this.author,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    return Quote(
      id: json['id'] ?? '',
      quote: json['quote'] ?? '',
      author: json['author'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quote': quote,
      'author': author,
      'tags': tags,
    };
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum SortField { quote, author, createdAt }

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Quote> _quotes = [];
  bool _isLoading = true;
  String? _error;
  String? _userEmail;
  SortField _sortField = SortField.createdAt;
  bool _sortAscending = false;
  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;
  String _importStatus = '';
  String _selectedTagFilter = 'All';
  List<String> _availableTags = ['All'];

  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _loadUserInfo();
    _loadQuotes();
  }

  Future<void> _checkAdminAccess() async {
    // Verify user has admin privileges
    final isAdmin = await AuthService.isUserInAdminGroup();
    if (!isAdmin && mounted) {
      // Redirect to login if not admin
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin access required'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadUserInfo() async {
    final email = await AuthService.getUserEmail();
    final name = await AuthService.getUserName();
    
    setState(() {
      _userEmail = name ?? email ?? 'Unknown';
    });
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final idToken = await AuthService.getIdToken();
    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
  }

  void _sortQuotes() {
    _quotes.sort((a, b) {
      int comparison;
      switch (_sortField) {
        case SortField.quote:
          comparison = a.quote.toLowerCase().compareTo(b.quote.toLowerCase());
          break;
        case SortField.author:
          comparison = a.author.toLowerCase().compareTo(b.author.toLowerCase());
          break;
        case SortField.createdAt:
          comparison = a.createdAt.compareTo(b.createdAt);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });
  }

  void _updateAvailableTags() {
    Set<String> tagsSet = {};
    for (Quote quote in _quotes) {
      tagsSet.addAll(quote.tags);
    }
    List<String> sortedTags = tagsSet.toList()..sort();
    
    // Check if the selected filter still exists in the new tags list
    // If not, reset to 'All'
    if (_selectedTagFilter != 'All' && !tagsSet.contains(_selectedTagFilter)) {
      _selectedTagFilter = 'All';
    }
    
    setState(() {
      _availableTags = ['All', ...sortedTags];
    });
  }

  List<Quote> get _filteredQuotes {
    if (_selectedTagFilter == 'All') {
      return _quotes;
    }
    return _quotes.where((quote) => quote.tags.contains(_selectedTagFilter)).toList();
  }

  void _setSortField(SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortAscending = !_sortAscending;
      } else {
        _sortField = field;
        _sortAscending = true;
      }
      _sortQuotes();
    });
  }

  Widget _buildImportProgress() {
    final progress = _importTotal > 0 ? _importProgress / _importTotal : 0.0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_upload,
              size: 64,
              color: Color(0xFF3F51B5),
            ),
            const SizedBox(height: 24),
            const Text(
              'Importing Quotes',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3F51B5),
              ),
            ),
            const SizedBox(height: 16),
            
            // Progress bar
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 300),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_importProgress of $_importTotal quotes',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Status message
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF5C6BC0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF5C6BC0).withOpacity(0.3),
                ),
              ),
              child: Text(
                _importStatus,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Cancel button (optional - though canceling mid-import could be complex)
            const Text(
              'Please wait while quotes are being imported...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  List<List<Quote>> _findDuplicateGroups() {
    Map<String, List<Quote>> duplicateMap = {};
    
    for (Quote quote in _quotes) {
      String key = '${quote.quote.trim().toLowerCase()}|${quote.author.trim().toLowerCase()}';
      if (duplicateMap.containsKey(key)) {
        duplicateMap[key]!.add(quote);
      } else {
        duplicateMap[key] = [quote];
      }
    }
    
    // Return only groups with more than one quote (actual duplicates)
    return duplicateMap.values.where((group) => group.length > 1).toList();
  }

  Future<void> _loadQuotes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/quotes'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotes = (data['quotes'] as List)
            .map((item) => Quote.fromJson(item))
            .toList();
        
        setState(() {
          _quotes = quotes;
          _sortQuotes();
          _updateAvailableTags();
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        await _signOut();
      } else {
        setState(() {
          _error = 'Failed to load quotes (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createQuote(Quote quote) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/quotes'),
        headers: headers,
        body: json.encode(quote.toJson()),
      );

      if (response.statusCode == 201) {
        _loadQuotes(); // Refresh the list
        _showMessage('Quote created successfully!', isError: false);
      } else {
        _showMessage('Failed to create quote (${response.statusCode})', isError: true);
      }
    } catch (e) {
      _showMessage('Error creating quote: $e', isError: true);
    }
  }

  Future<void> _updateQuote(Quote quote) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl/admin/quotes/${quote.id}'),
        headers: headers,
        body: json.encode(quote.toJson()),
      );

      if (response.statusCode == 200) {
        _loadQuotes(); // Refresh the list
        _showMessage('Quote updated successfully!', isError: false);
      } else {
        _showMessage('Failed to update quote (${response.statusCode})', isError: true);
      }
    } catch (e) {
      _showMessage('Error updating quote: $e', isError: true);
    }
  }

  Future<void> _deleteQuote(String quoteId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/quotes/$quoteId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        _loadQuotes(); // Refresh the list
        _showMessage('Quote deleted successfully!', isError: false);
      } else {
        _showMessage('Failed to delete quote (${response.statusCode})', isError: true);
      }
    } catch (e) {
      _showMessage('Error deleting quote: $e', isError: true);
    }
  }

  Future<void> _cleanupUnusedTags() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/tags/unused'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final removedCount = data['count_removed'] ?? 0;
        final removedTags = data['removed_tags'] ?? [];
        
        if (removedCount == 0) {
          _showMessage('No unused tags found to clean up', isError: false);
        } else {
          _showMessage('Successfully removed $removedCount unused tags: ${removedTags.join(', ')}', isError: false);
        }
        
        _loadQuotes(); // Refresh to show updated data
      } else {
        _showMessage('Failed to cleanup unused tags (${response.statusCode})', isError: true);
      }
    } catch (e) {
      _showMessage('Error cleaning up unused tags: $e', isError: true);
    }
  }

  Future<void> _cleanupDuplicateQuotes(List<String> quoteIdsToDelete) async {
    if (quoteIdsToDelete.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    int deletedCount = 0;
    List<String> errors = [];

    try {
      final headers = await _getAuthHeaders();

      for (String quoteId in quoteIdsToDelete) {
        try {
          final response = await http.delete(
            Uri.parse('$_baseUrl/admin/quotes/$quoteId'),
            headers: headers,
          );

          if (response.statusCode == 200) {
            deletedCount++;
          } else {
            errors.add('Failed to delete quote $quoteId (${response.statusCode})');
          }

          // Add small delay between deletions to prevent rate limiting
          if (quoteId != quoteIdsToDelete.last) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          errors.add('Error deleting quote $quoteId: $e');
        }
      }

      // Reload quotes to show updated data
      await _loadQuotes();

      if (mounted) {
        if (deletedCount > 0) {
          _showMessage('Successfully deleted $deletedCount duplicate quotes', isError: false);
        }
        if (errors.isNotEmpty) {
          _showMessage('Some deletions failed: ${errors.take(3).join(', ')}${errors.length > 3 ? '...' : ''}', isError: true);
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Cleanup failed: $e';
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await AuthService.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      _showMessage('Error signing out: $e', isError: true);
    }
  }

  void _showCleanupTagsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services, color: Colors.orange),
            SizedBox(width: 8),
            Text('Clean Unused Tags'),
          ],
        ),
        content: const Text(
          'This will remove all tags that are not currently used by any quotes. This action cannot be undone.\n\nAre you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cleanupUnusedTags();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );
  }

  void _showCleanupDuplicatesDialog() {
    final duplicateGroups = _findDuplicateGroups();
    
    if (duplicateGroups.isEmpty) {
      _showMessage('No duplicate quotes found!', isError: false);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _DuplicateCleanupDialog(
        duplicateGroups: duplicateGroups,
        onCleanup: (quoteIdsToDelete) {
          Navigator.of(context).pop();
          _cleanupDuplicateQuotes(quoteIdsToDelete);
        },
      ),
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => _ImportDialog(
        onImport: (quotes) {
          _importQuotes(quotes);
        },
      ),
    );
  }

  Future<void> _importQuotes(List<Quote> quotes) async {
    if (quotes.isEmpty) return;

    setState(() {
      _isImporting = true;
      _isLoading = false; // Don't show general loading, show progress instead
      _importProgress = 0;
      _importTotal = quotes.length;
      _importStatus = 'Starting import...';
    });

    List<Quote> successfulQuotes = [];
    List<Map<String, dynamic>> failedQuotes = [];
    const int batchSize = 5;

    try {
      final headers = await _getAuthHeaders();

      // Process quotes in batches of 5
      for (int batchStart = 0; batchStart < quotes.length; batchStart += batchSize) {
        final batchEnd = (batchStart + batchSize < quotes.length) 
            ? batchStart + batchSize 
            : quotes.length;
        
        final batch = quotes.sublist(batchStart, batchEnd);
        
        setState(() {
          _importStatus = 'Processing batch ${(batchStart ~/ batchSize) + 1} of ${(quotes.length / batchSize).ceil()}...';
        });

        // Process each quote in the current batch
        for (int i = 0; i < batch.length; i++) {
          final globalIndex = batchStart + i;
          final quote = batch[i];
          
          setState(() {
            _importProgress = globalIndex + 1;
            _importStatus = 'Importing ${globalIndex + 1} of ${quotes.length}...';
          });
          
          try {
            final response = await http.post(
              Uri.parse('$_baseUrl/admin/quotes'),
              headers: headers,
              body: json.encode(quote.toJson()),
            );

            if (response.statusCode == 201) {
              successfulQuotes.add(quote);
            } else {
              String errorMsg = 'Unknown error';
              try {
                final errorData = json.decode(response.body);
                errorMsg = errorData['error'] ?? errorData['message'] ?? 'Error ${response.statusCode}';
              } catch (_) {
                errorMsg = 'Error ${response.statusCode}';
              }
              
              failedQuotes.add({
                'quote': quote,
                'error': errorMsg,
                'index': globalIndex + 1,
              });
            }
          } catch (e) {
            failedQuotes.add({
              'quote': quote,
              'error': 'Network error: ${e.toString()}',
              'index': globalIndex + 1,
            });
          }

          // Add delay between requests to prevent rate limiting
          // Skip delay after the last request
          if (globalIndex < quotes.length - 1) {
            await Future.delayed(const Duration(milliseconds: 1100)); // 1.1 second delay
          }
        }

        // Small pause between batches for UI updates
        if (batchEnd < quotes.length) {
          setState(() {
            _importStatus = 'Completed batch ${(batchStart ~/ batchSize) + 1}. Starting next batch...';
          });
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      setState(() {
        _importStatus = 'Finalizing import...';
      });

      // Reload quotes to show imported ones
      await _loadQuotes();

      setState(() {
        _isImporting = false;
        _importProgress = 0;
        _importTotal = 0;
        _importStatus = '';
      });

      if (mounted) {
        // Show detailed results dialog
        _showImportResultsDialog(successfulQuotes, failedQuotes);
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
        _importProgress = 0;
        _importTotal = 0;
        _importStatus = '';
        _error = 'Import failed: $e';
        _isLoading = false;
      });
    }
  }

  void _showImportResultsDialog(List<Quote> successful, List<Map<String, dynamic>> failed) {
    showDialog(
      context: context,
      builder: (context) => _ImportResultsDialog(
        successfulQuotes: successful,
        failedQuotes: failed,
        onRetry: (quotesToRetry) {
          Navigator.of(context).pop();
          _importQuotes(quotesToRetry);
        },
      ),
    );
  }

  Future<void> _exportTags() async {
    try {
      // Fetch all available tags from the API
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/tags'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<String> tags = List<String>.from(data['tags'] ?? []);
        
        // Remove 'All' if it exists (it's not a real tag)
        tags.removeWhere((tag) => tag == 'All');
        
        // Sort tags alphabetically
        tags.sort();
        
        // Create the JSON structure
        final jsonData = {
          'tags': tags,
        };
        
        // Convert to pretty formatted JSON
        final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
        
        if (kIsWeb) {
          // Web platform: trigger file download
          downloadFile(jsonString, 'quote-me-tags.json');
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Downloaded quote-me-tags.json with ${tags.length} tags'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          // Mobile platform: copy to clipboard with option to share
          await Clipboard.setData(ClipboardData(text: jsonString));
          
          // Show dialog with preview and instructions
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.download, color: Color(0xFF3F51B5)),
                    SizedBox(width: 8),
                    Text('Tags Exported'),
                  ],
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${tags.length} tags exported and copied to clipboard.'),
                      const SizedBox(height: 8),
                      const Text(
                        'To save as a file:\n'
                        '1. Open a text editor or notes app\n'
                        '2. Paste the content\n'
                        '3. Save as "quote-me-tags.json"',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: SizedBox(
                          height: 150,
                          child: SingleChildScrollView(
                            child: Text(
                              jsonString,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        _showMessage('Failed to fetch tags: ${response.statusCode}', isError: true);
      }
    } catch (e) {
      print('❌ Error exporting tags: $e');
      _showMessage('Error exporting tags: $e', isError: true);
    }
  }

  void _showGenerateTagsDialog() {
    showDialog(
      context: context,
      builder: (context) => _GenerateTagsDialog(
        onGenerate: _generateTagsForTagless,
      ),
    );
  }

  Future<void> _generateTagsForTagless() async {
    // Find quotes without any tags
    final taglessQuotes = _filteredQuotes.where((quote) => quote.tags.isEmpty).toList();
    
    if (taglessQuotes.isEmpty) {
      _showMessage('No quotes found without tags!', isError: false);
      return;
    }

    // Get all existing tags from the system for context
    final existingTags = await _getAllTags();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _GenerateTagsProgressDialog(
        quotes: taglessQuotes,
        existingTags: existingTags,
        onComplete: (results) {
          Navigator.of(context).pop(); // Close progress dialog
          _showGenerateTagsResults(results);
          _loadQuotes(); // Refresh the quotes list
        },
      ),
    );
  }

  Future<List<String>> _getAllTags() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/tags'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<String> tags = List<String>.from(data['tags'] ?? []);
        tags.removeWhere((tag) => tag == 'All');
        return tags;
      }
    } catch (e) {
      print('❌ Error fetching existing tags: $e');
    }
    return [];
  }

  void _showGenerateTagsResults(Map<String, dynamic> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.purple),
            SizedBox(width: 8),
            Text('Tag Generation Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Successfully generated tags for ${results['successful']} quotes'),
            if (results['failed'] > 0)
              Text('Failed to generate tags for ${results['failed']} quotes'),
            if (results['errors'] != null && results['errors'].isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...results['errors'].map<Widget>((error) => Text(
                '• $error',
                style: const TextStyle(fontSize: 12, color: Colors.red),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showQuoteDialog({Quote? quote}) {
    final isEditing = quote != null;
    final quoteController = TextEditingController(text: quote?.quote ?? '');
    final authorController = TextEditingController(text: quote?.author ?? '');
    
    showDialog(
      context: context,
      builder: (context) => _QuoteEditDialog(
        isEditing: isEditing,
        quoteController: quoteController,
        authorController: authorController,
        initialTags: quote?.tags ?? [],
        onSave: (selectedTags) {
          final newQuote = Quote(
            id: quote?.id ?? '',
            quote: quoteController.text.trim(),
            author: authorController.text.trim(),
            tags: selectedTags,
            createdAt: quote?.createdAt ?? '',
            updatedAt: quote?.updatedAt ?? '',
            createdBy: quote?.createdBy,
          );

          if (isEditing) {
            _updateQuote(newQuote);
          } else {
            _createQuote(newQuote);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          // Sorting buttons
          IconButton(
            onPressed: () => _setSortField(SortField.quote),
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.format_quote, size: 16),
                Icon(
                  _sortField == SortField.quote 
                    ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.unfold_more,
                  size: 12,
                ),
              ],
            ),
            tooltip: 'Sort by Quote ${_sortField == SortField.quote ? (_sortAscending ? '(A-Z)' : '(Z-A)') : ''}',
          ),
          IconButton(
            onPressed: () => _setSortField(SortField.author),
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, size: 16),
                Icon(
                  _sortField == SortField.author 
                    ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.unfold_more,
                  size: 12,
                ),
              ],
            ),
            tooltip: 'Sort by Author ${_sortField == SortField.author ? (_sortAscending ? '(A-Z)' : '(Z-A)') : ''}',
          ),
          IconButton(
            onPressed: () => _setSortField(SortField.createdAt),
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 16),
                Icon(
                  _sortField == SortField.createdAt 
                    ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.unfold_more,
                  size: 12,
                ),
              ],
            ),
            tooltip: 'Sort by Date ${_sortField == SortField.createdAt ? (_sortAscending ? '(Old-New)' : '(New-Old)') : ''}',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'refresh') {
                _loadQuotes();
              } else if (value == 'import_quotes') {
                _showImportDialog();
              } else if (value == 'tags_editor') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const TagsEditorScreen(),
                  ),
                );
              } else if (value == 'cleanup_tags') {
                _showCleanupTagsDialog();
              } else if (value == 'cleanup_duplicates') {
                _showCleanupDuplicatesDialog();
              } else if (value == 'export_tags') {
                _exportTags();
              } else if (value == 'generate_tags') {
                _showGenerateTagsDialog();
              } else if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import_quotes',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, color: Color(0xFF3F51B5)),
                    SizedBox(width: 8),
                    Text('Import Quotes'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'tags_editor',
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: Color(0xFF3F51B5)),
                    SizedBox(width: 8),
                    Text('Manage Tags'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup_tags',
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Clean Unused Tags'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup_duplicates',
                child: Row(
                  children: [
                    Icon(Icons.content_copy, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Clean Duplicate Quotes'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_tags',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Color(0xFF3F51B5)),
                    SizedBox(width: 8),
                    Text('Export Tags'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'generate_tags',
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.purple),
                    SizedBox(width: 8),
                    Text('Generate Tags for Tagless'),
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
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuoteDialog(),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // User Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF5C6BC0).withOpacity(0.1),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings,
                      color: Color(0xFF3F51B5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Signed in as: ${_userEmail ?? 'Loading...'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF3F51B5),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_filteredQuotes.length} ${_selectedTagFilter != 'All' ? 'filtered' : 'total'} quotes',
                      style: const TextStyle(
                        color: Color(0xFF3F51B5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      color: Color(0xFF3F51B5),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Filter by tag:',
                      style: TextStyle(
                        color: Color(0xFF3F51B5),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF3F51B5).withOpacity(0.3),
                          ),
                        ),
                        child: DropdownButton<String>(
                          value: _availableTags.contains(_selectedTagFilter) ? _selectedTagFilter : 'All',
                          isExpanded: true,
                          underline: const SizedBox(),
                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF3F51B5)),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedTagFilter = newValue;
                              });
                            }
                          },
                          items: _availableTags.map<DropdownMenuItem<String>>((String tag) {
                            return DropdownMenuItem<String>(
                              value: tag,
                              child: Row(
                                children: [
                                  if (tag != 'All') ...[
                                    Icon(
                                      Icons.local_offer,
                                      size: 16,
                                      color: const Color(0xFF3F51B5).withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      color: const Color(0xFF3F51B5),
                                      fontWeight: tag == _selectedTagFilter ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  if (tag != 'All' && _selectedTagFilter != tag) ...[
                                    const Spacer(),
                                    Text(
                                      '(${_quotes.where((q) => q.tags.contains(tag)).length})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (_selectedTagFilter != 'All') ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _selectedTagFilter = 'All';
                          });
                        },
                        icon: const Icon(Icons.clear, color: Color(0xFF3F51B5)),
                        tooltip: 'Clear filter',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                    ),
                  )
                : _isImporting
                    ? _buildImportProgress()
                    : _error != null
                    ? Center(
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
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadQuotes,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredQuotes.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.format_quote,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedTagFilter != 'All' 
                                    ? 'No quotes found with tag "$_selectedTagFilter"'
                                    : 'No quotes found',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedTagFilter != 'All'
                                    ? 'Try selecting a different tag or clear the filter'
                                    : 'Tap the + button to add your first quote',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _filteredQuotes.length,
                            itemBuilder: (context, index) {
                              final quote = _filteredQuotes[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  title: Text(
                                    quote.quote,
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        '— ${quote.author}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF3F51B5),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        children: quote.tags
                                            .map((tag) => Chip(
                                                  label: Text(
                                                    tag,
                                                    style: const TextStyle(fontSize: 10),
                                                  ),
                                                  backgroundColor: const Color(0xFF5C6BC0)
                                                      .withOpacity(0.3),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize.shrinkWrap,
                                                ))
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showQuoteDialog(quote: quote);
                                      } else if (value == 'delete') {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Delete Quote'),
                                            content: const Text(
                                              'Are you sure you want to delete this quote?',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  _deleteQuote(quote.id);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _QuoteEditDialog extends StatefulWidget {
  final bool isEditing;
  final TextEditingController quoteController;
  final TextEditingController authorController;
  final List<String> initialTags;
  final Function(List<String>) onSave;

  const _QuoteEditDialog({
    required this.isEditing,
    required this.quoteController,
    required this.authorController,
    required this.initialTags,
    required this.onSave,
  });

  @override
  State<_QuoteEditDialog> createState() => _QuoteEditDialogState();
}

class _QuoteEditDialogState extends State<_QuoteEditDialog> {
  List<String> _availableTags = [];
  Set<String> _selectedTags = {};
  bool _isLoadingTags = true;
  final TextEditingController _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.initialTags);
    _loadAvailableTags();
  }

  Future<void> _loadAvailableTags() async {
    try {
      final idToken = await AuthService.getIdToken();
      final headers = {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      };
      
      final baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final response = await http.get(
        Uri.parse('$baseUrl/admin/tags'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _availableTags = List<String>.from(data['tags'] ?? []);
          _isLoadingTags = false;
        });
      } else {
        setState(() {
          _isLoadingTags = false;
        });
      }
    } catch (e) {
      print('Error loading tags: $e');
      setState(() {
        _isLoadingTags = false;
      });
    }
  }

  void _addNewTag() {
    final newTag = _newTagController.text.trim();
    if (newTag.isNotEmpty && !_availableTags.contains(newTag)) {
      setState(() {
        _availableTags.add(newTag);
        _selectedTags.add(newTag);
        _newTagController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEditing ? 'Edit Quote' : 'Add New Quote'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.quoteController,
              decoration: const InputDecoration(
                labelText: 'Quote Text',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: widget.authorController,
              decoration: const InputDecoration(
                labelText: 'Author',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tags',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            
            // Selected tags display
            if (_selectedTags.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5C6BC0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF5C6BC0).withOpacity(0.3),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedTags.map((tag) {
                    return Chip(
                      label: Text(tag),
                      backgroundColor: const Color(0xFF3F51B5).withOpacity(0.1),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() {
                          _selectedTags.remove(tag);
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Add new tag field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(
                      labelText: 'Add new tag',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => _addNewTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addNewTag,
                  icon: const Icon(Icons.add_circle),
                  color: const Color(0xFF3F51B5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Available tags
            const Text(
              'Available Tags (tap to select)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoadingTags)
              const Center(child: CircularProgressIndicator())
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableTags.map((tag) {
                      final isSelected = _selectedTags.contains(tag);
                      return FilterChip(
                        label: Text(tag),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedTags.add(tag);
                            } else {
                              _selectedTags.remove(tag);
                            }
                          });
                        },
                        selectedColor: const Color(0xFF5C6BC0).withOpacity(0.3),
                        checkmarkColor: const Color(0xFF3F51B5),
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onSave(_selectedTags.toList());
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5),
            foregroundColor: Colors.white,
          ),
          child: Text(widget.isEditing ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }
}

class _ImportDialog extends StatefulWidget {
  final Function(List<Quote>) onImport;

  const _ImportDialog({
    required this.onImport,
  });

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _textController = TextEditingController();
  List<Quote> _parsedQuotes = [];
  String? _error;
  bool _showPreview = false;

  void _parseData() {
    setState(() {
      _error = null;
      _parsedQuotes = [];
      _showPreview = false;
    });

    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _error = 'Please paste your data first';
      });
      return;
    }

    try {
      final lines = text.split('\n');
      if (lines.isEmpty) {
        setState(() {
          _error = 'No data found';
        });
        return;
      }

      // Skip header row if it contains "Nugget" and "Source"
      int startIndex = 0;
      if (lines[0].toLowerCase().contains('nugget') && lines[0].toLowerCase().contains('source')) {
        startIndex = 1;
      }

      List<Quote> quotes = [];
      for (int i = startIndex; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        // Split by tab (TSV format from Google Sheets)
        final parts = line.split('\t');
        if (parts.length < 2) continue; // Need at least quote and author

        final quote = parts[0].trim();
        final author = parts[1].trim();
        
        if (quote.isEmpty || author.isEmpty) continue;

        // Collect tags from columns 2-6 (Tag1-Tag5)
        List<String> tags = [];
        for (int j = 2; j < parts.length && j < 7; j++) {
          final tag = parts[j].trim();
          if (tag.isNotEmpty) {
            tags.add(tag);
          }
        }

        quotes.add(Quote(
          id: '', // Will be generated by server
          quote: quote,
          author: author,
          tags: tags,
          createdAt: '',
          updatedAt: '',
        ));
      }

      setState(() {
        _parsedQuotes = quotes;
        _showPreview = quotes.isNotEmpty;
        if (quotes.isEmpty) {
          _error = 'No valid quotes found. Make sure your data has quote and author columns.';
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Error parsing data: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.file_upload, color: Color(0xFF3F51B5)),
          SizedBox(width: 8),
          Text('Import Quotes'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Instructions:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              '1. Select rows in your Google Sheet (including headers)\n'
              '2. Copy them (Cmd+C or Ctrl+C)\n'
              '3. Paste below and click "Parse Data"',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            const Text(
              'Paste your Google Sheets data here:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            
            Expanded(
              flex: _showPreview ? 1 : 2,
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Nugget\tSource\tTag1\tTag2...\nQuote text\tAuthor\tTag1\tTag2...',
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                ElevatedButton(
                  onPressed: _parseData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Parse Data'),
                ),
                if (_parsedQuotes.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${_parsedQuotes.length} quotes found',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
            
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            ],
            
            if (_showPreview) ...[
              const SizedBox(height: 12),
              const Text(
                'Preview (first 3 quotes):',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListView.builder(
                    itemCount: _parsedQuotes.take(3).length,
                    itemBuilder: (context, index) {
                      final quote = _parsedQuotes[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '"${quote.quote}"',
                              style: const TextStyle(fontStyle: FontStyle.italic),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '— ${quote.author}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            if (quote.tags.isNotEmpty)
                              Text(
                                'Tags: ${quote.tags.join(', ')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _parsedQuotes.isNotEmpty
              ? () {
                  Navigator.of(context).pop();
                  widget.onImport(_parsedQuotes);
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5),
            foregroundColor: Colors.white,
          ),
          child: Text('Import ${_parsedQuotes.length} Quotes'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}

class _ImportResultsDialog extends StatefulWidget {
  final List<Quote> successfulQuotes;
  final List<Map<String, dynamic>> failedQuotes;
  final Function(List<Quote>) onRetry;

  const _ImportResultsDialog({
    required this.successfulQuotes,
    required this.failedQuotes,
    required this.onRetry,
  });

  @override
  State<_ImportResultsDialog> createState() => _ImportResultsDialogState();
}

class _ImportResultsDialogState extends State<_ImportResultsDialog> {
  late List<Map<String, dynamic>> _editableFailedQuotes;
  
  @override
  void initState() {
    super.initState();
    // Create editable copies of failed quotes
    _editableFailedQuotes = widget.failedQuotes.map((item) {
      return {
        'quote': Quote(
          id: '',
          quote: item['quote'].quote,
          author: item['quote'].author,
          tags: List<String>.from(item['quote'].tags),
          createdAt: '',
          updatedAt: '',
        ),
        'error': item['error'],
        'index': item['index'],
        'selected': true, // By default, select all for retry
      };
    }).toList();
  }

  void _editFailedQuote(int index) {
    final item = _editableFailedQuotes[index];
    final quote = item['quote'] as Quote;
    
    // Use temporary variables for editing
    String tempQuoteText = quote.quote;
    String tempAuthor = quote.author;
    List<String> tempTags = List<String>.from(quote.tags);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Quote #${item['index']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show the error message
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Error: ${item['error']}',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Edit fields
                TextField(
                  controller: TextEditingController(text: tempQuoteText),
                  decoration: const InputDecoration(
                    labelText: 'Quote Text',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (value) {
                    tempQuoteText = value;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: tempAuthor),
                  decoration: const InputDecoration(
                    labelText: 'Author',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    tempAuthor = value;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: tempTags.join(', ')),
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma-separated)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    tempTags = value.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
                  },
                ),
              ],
            ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                // Create a new Quote object with the edited values
                _editableFailedQuotes[index]['quote'] = Quote(
                  id: '',
                  quote: tempQuoteText,
                  author: tempAuthor,
                  tags: tempTags,
                  createdAt: '',
                  updatedAt: '',
                );
              });
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F51B5),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFailures = widget.failedQuotes.isNotEmpty;
    final selectedCount = _editableFailedQuotes.where((item) => item['selected'] == true).length;
    
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasFailures ? Icons.warning : Icons.check_circle,
            color: hasFailures ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          const Text('Import Results'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.successfulQuotes.length}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const Text('Successful'),
                    ],
                  ),
                  if (hasFailures)
                    Column(
                      children: [
                        Icon(Icons.error, color: Colors.red, size: 32),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.failedQuotes.length}',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const Text('Failed'),
                      ],
                    ),
                ],
              ),
            ),
            
            if (hasFailures) ...[
              const SizedBox(height: 16),
              const Text(
                'Failed Quotes (tap to edit):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              
              // Failed quotes list
              Expanded(
                child: ListView.builder(
                  itemCount: _editableFailedQuotes.length,
                  itemBuilder: (context, index) {
                    final item = _editableFailedQuotes[index];
                    final quote = item['quote'] as Quote;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Checkbox(
                          value: item['selected'] ?? false,
                          onChanged: (value) {
                            setState(() {
                              item['selected'] = value;
                            });
                          },
                        ),
                        title: Text(
                          '"${quote.quote.length > 50 ? quote.quote.substring(0, 50) + '...' : quote.quote}"',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('— ${quote.author}', style: const TextStyle(fontWeight: FontWeight.w500)),
                            Text(
                              'Error: ${item['error']}',
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, color: Color(0xFF3F51B5)),
                          onPressed: () => _editFailedQuote(index),
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              if (selectedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$selectedCount selected for retry',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
            ],
            
            // Success list (if no failures or collapsed)
            if (!hasFailures && widget.successfulQuotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Successfully Imported:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.successfulQuotes.length,
                  itemBuilder: (context, index) {
                    final quote = widget.successfulQuotes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        title: Text(
                          '"${quote.quote.length > 50 ? quote.quote.substring(0, 50) + '...' : quote.quote}"',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text('— ${quote.author}'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (hasFailures && selectedCount > 0)
          ElevatedButton(
            onPressed: () {
              // Get selected quotes for retry
              final quotesToRetry = _editableFailedQuotes
                  .where((item) => item['selected'] == true)
                  .map((item) => item['quote'] as Quote)
                  .toList();
              
              if (quotesToRetry.isNotEmpty) {
                widget.onRetry(quotesToRetry);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3F51B5),
              foregroundColor: Colors.white,
            ),
            child: Text('Retry Selected ($selectedCount)'),
          ),
      ],
    );
  }
}

class _DuplicateCleanupDialog extends StatefulWidget {
  final List<List<Quote>> duplicateGroups;
  final Function(List<String>) onCleanup;

  const _DuplicateCleanupDialog({
    required this.duplicateGroups,
    required this.onCleanup,
  });

  @override
  State<_DuplicateCleanupDialog> createState() => _DuplicateCleanupDialogState();
}

class _DuplicateCleanupDialogState extends State<_DuplicateCleanupDialog> {
  late Map<String, bool> _selectedQuotesToDelete;
  
  @override
  void initState() {
    super.initState();
    _selectedQuotesToDelete = {};
    
    // Pre-select all duplicates except the first one in each group (keep the oldest)
    for (List<Quote> group in widget.duplicateGroups) {
      List<Quote> sortedGroup = List.from(group);
      sortedGroup.sort((a, b) => a.createdAt.compareTo(b.createdAt)); // Sort by creation date
      
      for (int i = 1; i < sortedGroup.length; i++) { // Skip first (oldest)
        _selectedQuotesToDelete[sortedGroup[i].id] = true;
      }
      
      // Mark the first (oldest) as not selected
      _selectedQuotesToDelete[sortedGroup[0].id] = false;
    }
  }

  int get _totalDuplicates {
    return widget.duplicateGroups.fold(0, (sum, group) => sum + group.length);
  }

  int get _selectedCount {
    return _selectedQuotesToDelete.values.where((selected) => selected).length;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.content_copy, color: Colors.red),
          const SizedBox(width: 8),
          Text('Clean Duplicate Quotes (${widget.duplicateGroups.length} groups found)'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Found $_totalDuplicates total quotes in ${widget.duplicateGroups.length} duplicate groups',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_selectedCount quotes selected for deletion',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'By default, the oldest quote in each group is kept (unchecked). You can change the selection below.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Duplicate Groups (select quotes to delete):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.duplicateGroups.length,
                itemBuilder: (context, groupIndex) {
                  final group = widget.duplicateGroups[groupIndex];
                  final sortedGroup = List<Quote>.from(group);
                  sortedGroup.sort((a, b) => a.createdAt.compareTo(b.createdAt));

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Group ${groupIndex + 1} (${group.length} duplicates)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '"${group.first.quote.length > 100 ? group.first.quote.substring(0, 100) + '...' : group.first.quote}"',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '— ${group.first.author}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...sortedGroup.map((quote) {
                            final isSelected = _selectedQuotesToDelete[quote.id] ?? false;
                            final isOldest = quote == sortedGroup.first;
                            
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Created: ${quote.createdAt}${isOldest ? ' (oldest)' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isOldest ? Colors.green.shade700 : null,
                                  fontWeight: isOldest ? FontWeight.w500 : null,
                                ),
                              ),
                              subtitle: quote.tags.isNotEmpty 
                                ? Text(
                                    'Tags: ${quote.tags.join(', ')}',
                                    style: const TextStyle(fontSize: 10),
                                  )
                                : null,
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  _selectedQuotesToDelete[quote.id] = value ?? false;
                                });
                              },
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedCount > 0 
            ? () {
                final quoteIdsToDelete = _selectedQuotesToDelete.entries
                    .where((entry) => entry.value)
                    .map((entry) => entry.key)
                    .toList();
                widget.onCleanup(quoteIdsToDelete);
              }
            : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text('Delete $_selectedCount Duplicates'),
        ),
      ],
    );
  }
}

// Dialog for confirming tag generation
class _GenerateTagsDialog extends StatelessWidget {
  final VoidCallback onGenerate;

  const _GenerateTagsDialog({
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

// Progress dialog for tag generation with real-time updates
class _GenerateTagsProgressDialog extends StatefulWidget {
  final List<Quote> quotes;
  final List<String> existingTags;
  final Function(Map<String, dynamic>) onComplete;

  const _GenerateTagsProgressDialog({
    required this.quotes,
    required this.existingTags,
    required this.onComplete,
  });

  @override
  State<_GenerateTagsProgressDialog> createState() => _GenerateTagsProgressDialogState();
}

class _GenerateTagsProgressDialogState extends State<_GenerateTagsProgressDialog> {
  int _currentIndex = 0;
  int _successful = 0;
  int _failed = 0;
  List<String> _errors = [];
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
    const batchDelay = Duration(seconds: 5); // 5 second delay to avoid rate limits
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
          print('❌ Error generating tags for quote ${quote.id}: $e');
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
          _currentStatus = 'Batch complete! Processed ${endIndex} of ${widget.quotes.length} quotes.';
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

      // Wait a moment then return results
      await Future.delayed(const Duration(milliseconds: 500));
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
            Text('Processed batch successfully!'),
            const SizedBox(height: 8),
            Text('✅ Successful: $_successful'),
            Text('❌ Failed: $_failed'),
            const SizedBox(height: 8),
            Text('${widget.quotes.length - (_currentIndex + 1)} quotes remaining.'),
            if (_recentTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Recent tags generated:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
      final authService = AuthService();
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
      print('❌ Error updating quote with tags: $e');
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
                Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text('Successful: $_successful'),
                const SizedBox(width: 16),
                Icon(Icons.error, color: Colors.red, size: 16),
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
                style: const TextStyle(fontSize: 10, color: Colors.red),
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