import 'package:flutter/material.dart';
import '../../services/admin_api_service.dart';
import '../../services/logger_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/auth_service.dart';

class EditQuoteDialog extends StatefulWidget {
  final bool isEditing;
  final TextEditingController quoteController;
  final TextEditingController authorController;
  final List<String> initialTags;
  final Future<void> Function(List<String>) onSave;

  const EditQuoteDialog({
    super.key,
    required this.isEditing,
    required this.quoteController,
    required this.authorController,
    required this.initialTags,
    required this.onSave,
  });

  @override
  State<EditQuoteDialog> createState() => _EditQuoteDialogState();
}

class _EditQuoteDialogState extends State<EditQuoteDialog> {
  List<String> _availableTags = [];
  Set<String> _selectedTags = {};
  bool _isLoadingTags = true;
  bool _isSaving = false;
  bool _isRecommending = false;
  final TextEditingController _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTags = Set<String>.from(widget.initialTags);
    _loadAvailableTags();
  }

  Future<void> _loadAvailableTags() async {
    try {
      final tags = await AdminApiService.getTags();
      setState(() {
        _availableTags = tags;
        _isLoadingTags = false;
      });
    } catch (e) {
      LoggerService.error('Error loading tags', error: e);
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

  Future<void> _recommendTags() async {
    final quote = widget.quoteController.text.trim();
    final author = widget.authorController.text.trim();
    
    if (quote.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a quote first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      _isRecommending = true;
    });
    
    try {
      final baseUrl = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';
      final token = await AuthService.getIdToken();
      
      LoggerService.debug('Recommending tags for quote: "$quote" by $author');
      LoggerService.debug('Using endpoint: $baseUrl/admin/generate-tags');
      
      if (token == null) {
        throw Exception('Not authenticated');
      }
      
      final requestBody = {
        'quote': quote,
        'author': author.isNotEmpty ? author : 'Unknown',
        'existingTags': _availableTags,
      };
      
      LoggerService.debug('Request body: ${json.encode(requestBody)}');
      
      final response = await http.post(
        Uri.parse('$baseUrl/admin/generate-tags'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestBody),
      );
      
      LoggerService.debug('Response status: ${response.statusCode}');
      LoggerService.debug('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final recommendedTags = List<String>.from(data['tags'] ?? []);
        
        if (recommendedTags.isNotEmpty) {
          setState(() {
            // Add recommended tags to selected tags
            _selectedTags.addAll(recommendedTags);
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added ${recommendedTags.length} recommended tags'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No tags recommended'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded. Please wait a moment and try again.');
      } else {
        throw Exception('Failed to get tag recommendations');
      }
    } catch (e) {
      LoggerService.error('Error recommending tags', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isRecommending = false;
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _selectedTags.map((tag) {
                  return Chip(
                    label: Text(tag),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      setState(() {
                        _selectedTags.remove(tag);
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],
            
            // Add new tag field and Recommend Tags button
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
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Recommend Tags button
            Center(
              child: ElevatedButton.icon(
                onPressed: _isRecommending ? null : _recommendTags,
                icon: _isRecommending 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
                label: Text(_isRecommending ? 'Getting recommendations...' : 'Recommend Tags'),
              ),
            ),
            const SizedBox(height: 12),
            
            // Available tags
            Text(
              'Available Tags (tap to select)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
                        // Remove custom colors - use theme styling for consistency
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
          onPressed: _isSaving ? null : () async {
            setState(() {
              _isSaving = true;
            });
            
            try {
              // Wait for the save operation to complete
              await widget.onSave(_selectedTags.toList());
              
              // Only close dialog after successful save
              if (mounted) {
                Navigator.of(context).pop();
              }
            } catch (e) {
              // Handle error - don't close dialog
              setState(() {
                _isSaving = false;
              });
            }
          },
          child: _isSaving 
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Saving...'),
                ],
              )
            : Text(widget.isEditing ? 'Update' : 'Create'),
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