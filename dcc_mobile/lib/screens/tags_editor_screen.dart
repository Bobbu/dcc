import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/auth_service.dart';
import '../themes.dart';

class TagsEditorScreen extends StatefulWidget {
  const TagsEditorScreen({super.key});

  @override
  State<TagsEditorScreen> createState() => _TagsEditorScreenState();
}

class TagMetadata {
  final String name;
  final int quoteCount;
  final String? createdAt;
  final String? updatedAt;
  final String? createdBy;
  final String? lastUsed;

  TagMetadata({
    required this.name,
    required this.quoteCount,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.lastUsed,
  });

  factory TagMetadata.fromJson(Map<String, dynamic> json) {
    return TagMetadata(
      name: json['name'] ?? '',
      quoteCount: json['quote_count'] ?? 0,
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      createdBy: json['created_by'],
      lastUsed: json['last_used'],
    );
  }
}

class _TagsEditorScreenState extends State<TagsEditorScreen> {
  List<TagMetadata> _tags = [];
  bool _isLoading = true;
  String? _error;
  
  // Sorting state
  String _sortBy = 'name'; // 'name', 'created', 'updated', 'usage'
  bool _sortAscending = true;

  static final String _baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final idToken = await AuthService.getIdToken();
    return {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/tags'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tagsData = data['tags'] ?? [];
        
        List<TagMetadata> tags = [];
        for (var tagData in tagsData) {
          if (tagData is String) {
            // Handle legacy format (simple string array)
            tags.add(TagMetadata(name: tagData, quoteCount: 0));
          } else if (tagData is Map<String, dynamic>) {
            // Handle new format (metadata objects)
            tags.add(TagMetadata.fromJson(tagData));
          }
        }
        
        setState(() {
          _tags = tags;
          _isLoading = false;
        });
        
        _sortTags();
      } else if (response.statusCode == 401) {
        _navigateBack();
      } else {
        setState(() {
          _error = 'Failed to load tags (${response.statusCode})';
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

  Future<void> _addTag(String tagName) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/tags'),
        headers: headers,
        body: json.encode({'tag': tagName}),
      );

      if (response.statusCode == 201) {
        _loadTags(); // Refresh the list
        _showMessage('Tag "$tagName" added successfully!', isError: false);
      } else {
        final errorData = json.decode(response.body);
        _showMessage(errorData['error'] ?? 'Failed to add tag', isError: true);
      }
    } catch (e) {
      _showMessage('Error adding tag: $e', isError: true);
    }
  }

  Future<void> _updateTag(String oldTag, String newTag) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl/admin/tags/${Uri.encodeComponent(oldTag)}'),
        headers: headers,
        body: json.encode({'tag': newTag}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotesUpdated = data['quotes_updated'] ?? 0;
        _loadTags(); // Refresh the list
        _showMessage('Tag updated successfully! ($quotesUpdated quotes updated)', isError: false);
      } else {
        final errorData = json.decode(response.body);
        _showMessage(errorData['error'] ?? 'Failed to update tag', isError: true);
      }
    } catch (e) {
      _showMessage('Error updating tag: $e', isError: true);
    }
  }

  Future<void> _deleteTag(String tagName) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/tags/${Uri.encodeComponent(tagName)}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final quotesUpdated = data['quotes_updated'] ?? 0;
        _loadTags(); // Refresh the list
        _showMessage('Tag deleted successfully! ($quotesUpdated quotes updated)', isError: false);
      } else {
        final errorData = json.decode(response.body);
        _showMessage(errorData['error'] ?? 'Failed to delete tag', isError: true);
      }
    } catch (e) {
      _showMessage('Error deleting tag: $e', isError: true);
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
        
        _loadTags(); // Refresh to show updated data
      } else {
        _showMessage('Failed to cleanup unused tags (${response.statusCode})', isError: true);
      }
    } catch (e) {
      _showMessage('Error cleaning up unused tags: $e', isError: true);
    }
  }

  void _sortTags() {
    setState(() {
      switch (_sortBy) {
        case 'name':
          _tags.sort((a, b) {
            final comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return _sortAscending ? comparison : -comparison;
          });
          break;
        case 'created':
          _tags.sort((a, b) {
            final aDate = DateTime.tryParse(a.createdAt ?? '') ?? DateTime(1970);
            final bDate = DateTime.tryParse(b.createdAt ?? '') ?? DateTime(1970);
            final comparison = aDate.compareTo(bDate);
            return _sortAscending ? comparison : -comparison;
          });
          break;
        case 'updated':
          _tags.sort((a, b) {
            final aDate = DateTime.tryParse(a.updatedAt ?? '') ?? DateTime(1970);
            final bDate = DateTime.tryParse(b.updatedAt ?? '') ?? DateTime(1970);
            final comparison = aDate.compareTo(bDate);
            return _sortAscending ? comparison : -comparison;
          });
          break;
        case 'usage':
          _tags.sort((a, b) {
            final comparison = a.quoteCount.compareTo(b.quoteCount);
            return _sortAscending ? comparison : -comparison;
          });
          break;
      }
    });
  }

  void _toggleSort(String sortBy) {
    setState(() {
      if (_sortBy == sortBy) {
        _sortAscending = !_sortAscending;
      } else {
        _sortBy = sortBy;
        _sortAscending = true;
      }
    });
    _sortTags();
  }

  Widget _buildHeaderSortButton(String sortBy, String label, IconData icon) {
    final isActive = _sortBy == sortBy;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ElevatedButton.icon(
        onPressed: () => _toggleSort(sortBy),
        icon: Icon(
          icon,
          size: 16,
          color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSecondary,
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _sortAscending ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 14,
              color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSecondary,
            ),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive 
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondary.withValues(alpha: 51),
          foregroundColor: isActive 
            ? Theme.of(context).colorScheme.onPrimary
            : Theme.of(context).colorScheme.onSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      
      // Month names
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      
      // Convert to 12-hour format
      int hour12 = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
      String amPm = date.hour >= 12 ? 'pm' : 'am';
      
      return '${months[date.month - 1]} ${date.day}, ${date.year} at ${hour12}:${date.minute.toString().padLeft(2, '0')} $amPm';
    } catch (e) {
      return dateString; // Return original string if parsing fails
    }
  }

  void _navigateBack() {
    Navigator.of(context).pop();
  }

  void _showAddTagDialog() {
    final tagController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: 8),
            Text('Add New Tag'),
          ],
        ),
        content: TextField(
          controller: tagController,
          decoration: const InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
            hintText: 'Enter tag name',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final tagName = tagController.text.trim();
              if (tagName.isNotEmpty) {
                Navigator.of(context).pop();
                _addTag(tagName);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditTagDialog(TagMetadata tag) {
    final tagController = TextEditingController(text: tag.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit, color: Theme.of(context).colorScheme.primary),
            SizedBox(width: 8),
            Text('Edit Tag'),
          ],
        ),
        content: TextField(
          controller: tagController,
          decoration: const InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTag = tagController.text.trim();
              if (newTag.isNotEmpty && newTag != tag.name) {
                Navigator.of(context).pop();
                _updateTag(tag.name, newTag);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showDeleteTagDialog(String tagName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Tag'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the tag "$tagName"?\n\nThis will remove it from all quotes that use it. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteTag(tagName);
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

  void _showCleanupDialog() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tags Editor'),
        actions: [
          IconButton(
            onPressed: _showCleanupDialog,
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Clean Unused Tags',
          ),
          IconButton(
            onPressed: _loadTags,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTagDialog,
        child: Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Header with count and sort buttons
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 51),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag count and Sort by label
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sort by:',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                    Text(
                      '${_tags.length} tags',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Sort buttons in a wrappable layout
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildHeaderSortButton('name', 'Tag', Icons.local_offer),
                    _buildHeaderSortButton('usage', 'Usage', Icons.trending_up),
                    _buildHeaderSortButton('created', 'Created', Icons.access_time),
                    _buildHeaderSortButton('updated', 'Updated', Icons.update),
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
                              style: AppThemes.errorText(context).copyWith(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadTags,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _tags.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.local_offer_outlined,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No tags found',
                                  style: Theme.of(context).textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap the + button to add your first tag',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                            itemCount: _tags.length,
                            itemBuilder: (context, index) {
                              final tag = _tags[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: ListTile(
                                  leading: Chip(
                                    label: Text(tag.name),
                                  ),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tag.name,
                                        style: Theme.of(context).textTheme.headlineSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${tag.quoteCount} ${tag.quoteCount == 1 ? 'quote' : 'quotes'}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (tag.createdAt != null)
                                        Text(
                                          'Created: ${_formatDate(tag.createdAt!)}',
                                          style: AppThemes.dateText(context),
                                        ),
                                      if (tag.updatedAt != null)
                                        Text(
                                          'Updated: ${_formatDate(tag.updatedAt!)}',
                                          style: AppThemes.dateText(context),
                                        ),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showEditTagDialog(tag);
                                      } else if (value == 'delete') {
                                        _showDeleteTagDialog(tag.name);
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