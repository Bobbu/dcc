import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import '../helpers/download_helper_stub.dart'
    if (dart.library.html) '../helpers/download_helper_web.dart';
import '../services/auth_service.dart';
import '../services/admin_api_service.dart';
import '../services/openai_proxy_service.dart';
import '../services/logger_service.dart';
import 'tags_editor_screen.dart';
import '../themes.dart';
import '../models/quote.dart';
import '../widgets/admin/import_quotes_dialog.dart';
import '../widgets/admin/import_results_dialog.dart';
import '../widgets/admin/duplicate_cleanup_dialog.dart';
import '../widgets/admin/tag_generation_dialogs.dart';
import '../widgets/admin/edit_quote_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum SortField { quote, author, createdAt, updatedAt }

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Quote> _quotes = [];
  List<Quote> _searchResults = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isPreparingSearch = false;
  bool _isSorting = false;
  bool _isLoadingMore = false;
  bool _hasMoreQuotes = true;
  String? _lastKey;
  String? _error;
  String? _userEmail;
  SortField _sortField = SortField.createdAt;
  bool _sortAscending = false;
  bool _isImporting = false;
  bool _isLoadingTags = false;
  int _importProgress = 0;
  int _importTotal = 0;
  String _importStatus = '';
  // Tag filter removed - using search functionality instead
  List<String> _availableTags = []; // Keep for compatibility but not used
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
    _loadUserInfo();
    _loadQuotes();
    
    // Clear any residual search state
    _searchController.clear();
    _searchQuery = '';
    _searchResults = [];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final formatter = DateFormat("MMM d, yyyy 'at' h:mm a");
      return formatter.format(date);
    } catch (e) {
      return dateString; // Return original if parsing fails
    }
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


  List<Quote> get _filteredQuotes {
    // Show search results when searching, otherwise show all quotes
    List<Quote> filtered;
    
    if (_searchQuery.isNotEmpty) {
      // We're in search mode - only show search results
      filtered = _searchResults;
    } else {
      // No search query - show all quotes
      filtered = _quotes;
    }
    
    LoggerService.debug('🔍 _filteredQuotes: searchQuery="$_searchQuery", quotes=${_quotes.length}, searchResults=${_searchResults.length}, isPreparingSearch=$_isPreparingSearch, isSearching=$_isSearching');
    LoggerService.debug('🔍 _filteredQuotes returning: ${filtered.length} quotes');
    return filtered;
  }

  void _setSortField(SortField field) {
    // Update sort state
    bool newSortAscending;
    if (_sortField == field) {
      newSortAscending = !_sortAscending;
    } else {
      newSortAscending = true;
    }
    
    setState(() {
      _sortField = field;
      _sortAscending = newSortAscending;
      _isSorting = true;
    });
    
    // Trigger server-side sorting
    _loadQuotesWithSort();
  }

  void _onSearchChanged(String value) {
    // Cancel any existing timer
    _debounceTimer?.cancel();
    
    // Show "Preparing search..." immediately if user is typing something
    if (value.trim().isNotEmpty) {
      setState(() {
        _isPreparingSearch = true;
      });
    } else {
      setState(() {
        _isPreparingSearch = false;
      });
    }
    
    // Set up a new timer to execute search after 500ms of no typing
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    query = query.trim();
    
    if (query.isEmpty) {
      // Clear search
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _isPreparingSearch = false;
      });
      return;
    }
    
    // Only skip if query is the same AND we already have search results
    if (query == _searchQuery && _searchResults.isNotEmpty && !_isSearching) {
      // Same query with existing results, no need to search again
      setState(() {
        _isPreparingSearch = false;
      });
      return;
    }
    
    setState(() {
      _searchQuery = query;
      _isSearching = true;
      _isPreparingSearch = false;  // Stop preparing, start actual search
      _searchResults = [];
    });
    
    try {
      // Use the new AdminApiService search method
      final searchResults = await AdminApiService.searchQuotes(
        query: query,
        limit: 1000,
      );
      
      final searchQuotes = searchResults
          .map((item) => Quote.fromJson(item))
          .toList();
      
      setState(() {
        _searchResults = searchQuotes;
        _isSearching = false;
      });
      
      LoggerService.info('✅ Found ${searchQuotes.length} quotes matching "$query"');
    } catch (e) {
      setState(() {
        _isSearching = false;
        _error = 'Search error: $e';
      });
    }
  }

  Widget _buildImportProgress() {
    final progress = _importTotal > 0 ? _importProgress / _importTotal : 0.0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_upload,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Importing Quotes',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
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
                color: Theme.of(context).colorScheme.secondary.withValues(alpha: 51),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 153),
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
      _lastKey = null;
      _hasMoreQuotes = true;
    });

    try {
      LoggerService.info('Loading quotes using AdminApiService...');
      
      // Convert sort field to backend format
      String sortBy = _getSortFieldString(_sortField);
      String sortOrder = _sortAscending ? 'asc' : 'desc';
      
      // Use the new AdminApiService method with sorting
      final response = await AdminApiService.getQuotesWithPagination(
        limit: 50,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );
      
      final quotesData = response['quotes'] as List<Map<String, dynamic>>;
      LoggerService.debug('📊 Raw quotes data received: ${quotesData.length} items');
      if (quotesData.isNotEmpty) {
        LoggerService.debug('📊 First quote sample: ${quotesData.first}');
      }
      
      final quotes = quotesData.map((item) => Quote.fromJson(item)).toList();
      
      setState(() {
        _quotes = quotes;
        _isLoading = false;
        _isSorting = false;
        _lastKey = response['last_key'];
        _hasMoreQuotes = response['has_more'] ?? false;
      });
      
      LoggerService.info('✅ Successfully loaded ${quotes.length} quotes (total: ${response['total_count']})');
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
        _isSorting = false;
      });
    }
  }

  Future<void> _loadQuotesWithSort() async {
    // This is called when only sorting changes, not the initial load
    setState(() {
      _error = null;
    });

    try {
      LoggerService.info('Loading quotes with new sort order...');
      
      // Convert sort field to backend format
      String sortBy = _getSortFieldString(_sortField);
      String sortOrder = _sortAscending ? 'asc' : 'desc';
      
      // Use the new AdminApiService method with sorting
      final response = await AdminApiService.getQuotesWithPagination(
        limit: 50,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );
      
      final quotesData = response['quotes'] as List<Map<String, dynamic>>;
      final quotes = quotesData.map((item) => Quote.fromJson(item)).toList();
      
      setState(() {
        _quotes = quotes;
        _isSorting = false;
        _lastKey = response['last_key'];
        _hasMoreQuotes = response['has_more'] ?? false;
      });
      
      LoggerService.info('✅ Successfully loaded ${quotes.length} quotes with new sort order');
    } catch (e) {
      setState(() {
        _error = 'Sort error: $e';
        _isSorting = false;
      });
    }
  }

  String _getSortFieldString(SortField field) {
    switch (field) {
      case SortField.quote:
        return 'quote';
      case SortField.author:
        return 'author';
      case SortField.createdAt:
        return 'created_at';
      case SortField.updatedAt:
        return 'updated_at';
    }
  }
  
  Future<void> _loadMoreQuotes() async {
    if (_isLoadingMore || !_hasMoreQuotes || _lastKey == null) return;
    
    setState(() {
      _isLoadingMore = true;
    });
    
    try {
      LoggerService.info('Loading more quotes with pagination...');
      
      // Convert sort field to backend format
      String sortBy = _getSortFieldString(_sortField);
      String sortOrder = _sortAscending ? 'asc' : 'desc';
      
      // Use pagination with current sort order
      final response = await AdminApiService.getQuotesWithPagination(
        limit: 50,
        lastKey: _lastKey,
        sortBy: sortBy,
        sortOrder: sortOrder,
      );
      
      final quotesData = response['quotes'] as List<Map<String, dynamic>>;
      final newQuotes = quotesData.map((item) => Quote.fromJson(item)).toList();
      
      setState(() {
        // Add new quotes to existing ones
        _quotes.addAll(newQuotes);
        _isLoadingMore = false;
        _lastKey = response['last_key'];
        _hasMoreQuotes = response['has_more'] ?? false;
      });
      
      LoggerService.info('✅ Loaded ${newQuotes.length} more quotes');
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
        _error = 'Error loading more quotes: $e';
      });
      _showMessage('Failed to load more quotes', isError: true);
    }
  }

  Future<void> _createQuote(Quote quote) async {
    try {
      await AdminApiService.createQuote(
        quote: quote.quote,
        author: quote.author,
        tags: quote.tags,
      );
      
      if (mounted) {
        _showMessage('Quote created successfully!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error creating quote: $e', isError: true);
      }
      rethrow; // Re-throw to prevent dialog from closing on error
    }
  }

  Future<void> _updateQuote(Quote quote) async {
    try {
      await AdminApiService.updateQuote(
        id: quote.id,
        quote: quote.quote,
        author: quote.author,
        tags: quote.tags,
      );
      
      if (mounted) {
        _showMessage('Quote updated successfully!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error updating quote: $e', isError: true);
      }
      rethrow; // Re-throw to prevent dialog from closing on error
    }
  }

  Future<void> _deleteQuote(String quoteId) async {
    try {
      await AdminApiService.deleteQuote(quoteId);
      
      // Wait for backend success, then refresh
      await _loadQuotes();
      
      if (mounted) {
        _showMessage('Quote deleted successfully!', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error deleting quote: $e', isError: true);
      }
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
        title: Row(
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
      builder: (context) => DuplicateCleanupDialog(
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
      builder: (context) => ImportQuotesDialog(
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
      builder: (context) => ImportResultsDialog(
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
      // Fetch all available tags with full metadata from the API
      final tags = await AdminApiService.getTagsWithMetadata();
        
      // Remove 'All' if it exists (it's not a real tag)
      final filteredTags = tags.where((tag) => tag.name != 'All').toList();
      
      // Sort tags alphabetically by name
      filteredTags.sort((a, b) => a.name.compareTo(b.name));
      
      // Create the JSON structure with full Tag objects
      final jsonData = {
        'export_metadata': {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'total_tags': filteredTags.length,
          'format': 'tag_objects',
          'version': '2.0',
        },
        'tags': filteredTags.map((tag) => tag.toJson()).toList(),
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
                content: Text('Downloaded quote-me-tags.json with ${filteredTags.length} tag objects'),
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
                title: Row(
                  children: [
                    Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
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
                      Text('${filteredTags.length} tag objects exported and copied to clipboard.'),
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
    } catch (e) {
      LoggerService.error('Error exporting tags', error: e);
      _showMessage('Error exporting tags: $e', isError: true);
    }
  }

  void _showGenerateTagsDialog() {
    showDialog(
      context: context,
      builder: (context) => GenerateTagsDialog(
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
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenerateTagsProgressDialog(
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
      final tags = await AdminApiService.getTags();
      tags.removeWhere((tag) => tag == 'All');
      return tags;
    } catch (e) {
      LoggerService.error('Error fetching existing tags', error: e);
      return [];
    }
  }

  void _showGenerateTagsResults(Map<String, dynamic> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
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
      builder: (context) => EditQuoteDialog(
        isEditing: isEditing,
        quoteController: quoteController,
        authorController: authorController,
        initialTags: quote?.tags ?? [],
        onSave: (selectedTags) async {
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
            await _updateQuote(newQuote);
          } else {
            await _createQuote(newQuote);
          }
        },
      ),
    ).then((_) {
      // Force refresh when dialog closes (whether cancelled or saved)
      LoggerService.info('🔄 Dialog closed, forcing refresh of quotes...');
      
      // Clear any search state that might interfere with showing updated quotes
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _isSearching = false;
        _isPreparingSearch = false;
      });
      
      // Now load fresh quotes
      _loadQuotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
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
                ).then((_) {
                  // Refresh quotes when returning from Tags Editor in case tags were changed
                  _loadQuotes();
                });
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
               PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 8),
                    Text('Refresh'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'import_quotes',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, color: Theme.of(context).colorScheme.primary),
                    SizedBox(width: 8),
                    Text('Import Quotes'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'tags_editor',
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: Theme.of(context).colorScheme.primary),
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
              PopupMenuItem(
                value: 'export_tags',
                child: Row(
                  children: [
                    Icon(Icons.download, color: Theme.of(context).colorScheme.primary),
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
                    Icon(Icons.logout, color: Colors.red),
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
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // User Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 51),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: Theme.of(context).colorScheme.onSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Signed in as: ${_userEmail ?? 'Loading...'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_filteredQuotes.length} ${_searchQuery.isNotEmpty ? 'search results' : 'loaded'} ${_filteredQuotes.length == 1 ? 'quote' : 'quotes'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Search field
                Row(
                  children: [
                    Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.onSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Search:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search quotes or authors...',
                            hintStyle: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            suffixIcon: _searchQuery.isNotEmpty || _isSearching
                              ? IconButton(
                                  icon: _isSearching 
                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.clear, size: 18),
                                  onPressed: _isSearching ? null : () {
                                    _debounceTimer?.cancel();
                                    _searchController.clear();
                                    _performSearch('');
                                  },
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                )
                              : null,
                          ),
                          onChanged: _onSearchChanged,
                          onSubmitted: (value) {
                            // Handle Enter key - cancel debouncer and search immediately
                            _debounceTimer?.cancel();
                            _performSearch(value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                // Search status indicator
                if (_isSearching)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Searching...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Sort buttons section
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.sort,
                          color: Theme.of(context).colorScheme.onSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Sort by:',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Quote sort button
                        ElevatedButton.icon(
                          onPressed: () => _setSortField(SortField.quote),
                          icon: Icon(
                            _sortField == SortField.quote 
                              ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                              : Icons.format_quote,
                            size: 16,
                          ),
                          label: const Text('Quote'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sortField == SortField.quote 
                              ? Theme.of(context).colorScheme.primary 
                              : Theme.of(context).colorScheme.secondary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                        // Author sort button
                        ElevatedButton.icon(
                          onPressed: () => _setSortField(SortField.author),
                          icon: Icon(
                            _sortField == SortField.author 
                              ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                              : Icons.person,
                            size: 16,
                          ),
                          label: const Text('Author'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sortField == SortField.author 
                              ? Theme.of(context).colorScheme.primary 
                              : Theme.of(context).colorScheme.secondary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                        // Created date sort button
                        ElevatedButton.icon(
                          onPressed: () => _setSortField(SortField.createdAt),
                          icon: Icon(
                            _sortField == SortField.createdAt 
                              ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                              : Icons.add_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Created'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sortField == SortField.createdAt 
                              ? Theme.of(context).colorScheme.primary 
                              : Theme.of(context).colorScheme.secondary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                        // Updated date sort button
                        ElevatedButton.icon(
                          onPressed: () => _setSortField(SortField.updatedAt),
                          icon: Icon(
                            _sortField == SortField.updatedAt 
                              ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
                              : Icons.edit_calendar,
                            size: 16,
                          ),
                          label: const Text('Updated'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _sortField == SortField.updatedAt 
                              ? Theme.of(context).colorScheme.primary 
                              : Theme.of(context).colorScheme.secondary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                    ),
                  )
                : _isImporting
                    ? _buildImportProgress()
                    : _isPreparingSearch
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search,
                                  size: 64,
                                  color: Colors.indigo.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Preparing search...',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.indigo.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _isSorting
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade600),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Sorting quotes...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.indigo.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _isSearching
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo.shade600),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Searching for "$_searchQuery"...',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.indigo.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
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
                                  _searchQuery.isNotEmpty
                                    ? 'No quotes found for "$_searchQuery"'
                                    : 'No quotes found',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                    ? 'Try different search terms or clear the search'
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
                            itemCount: _filteredQuotes.length + (_hasMoreQuotes && _searchQuery.isEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Show Load More button at the end
                              if (index == _filteredQuotes.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: _isLoadingMore
                                      ? const CircularProgressIndicator()
                                      : ElevatedButton.icon(
                                          onPressed: _loadMoreQuotes,
                                          icon: const Icon(Icons.expand_more),
                                          label: const Text('Load More Quotes'),
                                        ),
                                  ),
                                );
                              }
                              
                              final quote = _filteredQuotes[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  title: Text(
                                    quote.quote,
                                    style: Theme.of(context).textTheme.headlineLarge,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 8),
                                      Text(
                                        '— ${quote.author}',
                                        style: Theme.of(context).textTheme.headlineMedium,
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 4,
                                        children: quote.tags
                                            .map((tag) => Chip(
                                                  label: Text(tag),
                                                  materialTapTargetSize:
                                                      MaterialTapTargetSize.shrinkWrap,
                                                ))
                                            .toList(),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.schedule,
                                                size: AppThemes.dateIconSize(context),
                                                color: AppThemes.dateIconColor(context),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'Created: ${_formatDate(quote.createdAt)}',
                                                  style: AppThemes.dateText(context),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 16),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                size: AppThemes.dateIconSize(context),
                                                color: AppThemes.dateIconColor(context),
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  'Updated: ${_formatDate(quote.updatedAt)}',
                                                  style: AppThemes.dateText(context),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
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
