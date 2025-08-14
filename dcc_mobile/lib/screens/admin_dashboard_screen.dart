import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
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

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  List<Quote> _quotes = [];
  bool _isLoading = true;
  String? _error;
  String? _userEmail;

  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadQuotes();
  }

  Future<void> _loadUserInfo() async {
    final attributes = await AuthService.getUserAttributes();
    setState(() {
      _userEmail = attributes?['email'] ?? 'Unknown';
    });
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final idToken = await AuthService.getIdToken();
    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
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
      _isLoading = true;
    });

    try {
      final headers = await _getAuthHeaders();
      int successCount = 0;
      int errorCount = 0;

      for (final quote in quotes) {
        try {
          final response = await http.post(
            Uri.parse('$_baseUrl/admin/quotes'),
            headers: headers,
            body: json.encode(quote.toJson()),
          );

          if (response.statusCode == 201) {
            successCount++;
          } else {
            errorCount++;
          }
        } catch (e) {
          errorCount++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Import complete: $successCount imported, $errorCount failed',
            ),
            backgroundColor: successCount > 0 ? Colors.green : Colors.red,
          ),
        );
      }

      // Reload quotes to show imported ones
      await _loadQuotes();
    } catch (e) {
      setState(() {
        _error = 'Import failed: $e';
        _isLoading = false;
      });
    }
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
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
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
                );
              } else if (value == 'cleanup_tags') {
                _showCleanupTagsDialog();
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
                    Icon(Icons.file_upload, color: Color(0xFF800000)),
                    SizedBox(width: 8),
                    Text('Import Quotes'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'tags_editor',
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: Color(0xFF800000)),
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
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // User Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFFFFD700).withOpacity(0.1),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  color: Color(0xFF800000),
                ),
                const SizedBox(width: 8),
                Text(
                  'Signed in as: ${_userEmail ?? 'Loading...'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF800000),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_quotes.length} quotes',
                  style: const TextStyle(
                    color: Color(0xFF800000),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF800000)),
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
                    : _quotes.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.format_quote,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No quotes found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Tap the + button to add your first quote',
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _quotes.length,
                            itemBuilder: (context, index) {
                              final quote = _quotes[index];
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
                                          color: Color(0xFF800000),
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
                                                  backgroundColor: const Color(0xFFFFD700)
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
                  color: const Color(0xFFFFD700).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedTags.map((tag) {
                    return Chip(
                      label: Text(tag),
                      backgroundColor: const Color(0xFF800000).withOpacity(0.1),
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
                  color: const Color(0xFF800000),
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
                        selectedColor: const Color(0xFFFFD700).withOpacity(0.3),
                        checkmarkColor: const Color(0xFF800000),
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
            backgroundColor: const Color(0xFF800000),
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
          Icon(Icons.file_upload, color: Color(0xFF800000)),
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
                    backgroundColor: const Color(0xFF800000),
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
            backgroundColor: const Color(0xFF800000),
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