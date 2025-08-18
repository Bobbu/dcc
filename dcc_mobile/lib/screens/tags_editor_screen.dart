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

class _TagsEditorScreenState extends State<TagsEditorScreen> {
  List<String> _tags = [];
  bool _isLoading = true;
  String? _error;

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
        final tags = List<String>.from(data['tags'] ?? []);
        
        setState(() {
          _tags = tags;
          _isLoading = false;
        });
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

  void _showEditTagDialog(String currentTag) {
    final tagController = TextEditingController(text: currentTag);

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
              if (newTag.isNotEmpty && newTag != currentTag) {
                Navigator.of(context).pop();
                _updateTag(currentTag, newTag);
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
            icon: Icon(Icons.cleaning_services),
            tooltip: 'Clean Unused Tags',
          ),
          IconButton(
            onPressed: _loadTags,
            icon: Icon(Icons.refresh),
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
          // Header with count
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 51),
            child: Row(
              children: [
                Icon(
                  Icons.local_offer,
                  color: Theme.of(context).colorScheme.onSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tag Management',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_tags.length} tags',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
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
                            padding: const EdgeInsets.all(8),
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
                                    label: Text(tag),
                                  ),
                                  title: Text(
                                    'Tag: $tag',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showEditTagDialog(tag);
                                      } else if (value == 'delete') {
                                        _showDeleteTagDialog(tag);
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