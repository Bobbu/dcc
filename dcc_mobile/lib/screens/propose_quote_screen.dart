import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../themes.dart';

class ProposeQuoteScreen extends StatefulWidget {
  const ProposeQuoteScreen({super.key});

  @override
  State<ProposeQuoteScreen> createState() => _ProposeQuoteScreenState();
}

class _ProposeQuoteScreenState extends State<ProposeQuoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quoteController = TextEditingController();
  final _authorController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagsController = TextEditingController();
  
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _myProposedQuotes = [];
  bool _isLoadingQuotes = false;
  
  static final String apiEndpoint = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _loadMyProposedQuotes();
  }

  @override
  void dispose() {
    _quoteController.dispose();
    _authorController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _loadMyProposedQuotes() async {
    setState(() {
      _isLoadingQuotes = true;
    });

    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in to view your proposed quotes'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final response = await http.get(
        Uri.parse('$apiEndpoint/proposed-quotes'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _myProposedQuotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        });
      } else {
        LoggerService.debug('Failed to load proposed quotes: ${response.statusCode}');
      }
    } catch (e) {
      LoggerService.debug('Error loading proposed quotes: $e');
    } finally {
      setState(() {
        _isLoadingQuotes = false;
      });
    }
  }

  Future<void> _submitQuote() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in to propose a quote'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Parse tags from comma-separated string
      List<String> tags = [];
      if (_tagsController.text.isNotEmpty) {
        tags = _tagsController.text
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList();
      }

      final Map<String, dynamic> body = {
        'quote': _quoteController.text.trim(),
        'author': _authorController.text.trim(),
      };

      if (_notesController.text.isNotEmpty) {
        body['notes'] = _notesController.text.trim();
      }

      if (tags.isNotEmpty) {
        body['tags'] = tags;
      }

      final response = await http.post(
        Uri.parse('$apiEndpoint/propose-quote'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quote proposed successfully! It will be reviewed by an admin.'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Clear the form
          _quoteController.clear();
          _authorController.clear();
          _notesController.clear();
          _tagsController.clear();
          
          // Reload the list of proposed quotes
          _loadMyProposedQuotes();
        }
      } else {
        final error = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error['error'] ?? 'Failed to propose quote'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      LoggerService.debug('Error proposing quote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Color _getStatusColor(String status, BuildContext context) {
    switch (status) {
      case 'pending':
        return AppThemes.pendingColor(context);
      case 'approved':
        return AppThemes.approvedColor(context);
      case 'rejected':
        return AppThemes.rejectedColor(context);
      default:
        return AppThemes.inactiveColor(context);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Propose a Quote'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submit a Quote for Review',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _quoteController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Quote *',
                          hintText: 'Enter the quote text...',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the quote text';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _authorController,
                        decoration: const InputDecoration(
                          labelText: 'Author *',
                          hintText: 'Who said or wrote this?',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter the author';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags (optional)',
                          hintText: 'Enter tags separated by commas',
                          border: OutlineInputBorder(),
                          helperText: 'Example: Motivation, Leadership, Success',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Notes (optional)',
                          hintText: 'Any additional context or source information',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitQuote,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Submit Quote for Review'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'My Proposed Quotes',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            if (_isLoadingQuotes)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_myProposedQuotes.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      'You haven\'t proposed any quotes yet',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              )
            else
              ...(_myProposedQuotes.map((quote) {
                final status = quote['status'] ?? 'pending';
                final statusColor = _getStatusColor(status, context);
                final statusIcon = _getStatusIcon(status);
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      statusIcon,
                      color: statusColor,
                    ),
                    title: Text(
                      quote['quote'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('— ${quote['author'] ?? ''}'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(quote['created_date']),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              }).toList()),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      
      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes} min ago';
        }
        return '${difference.inHours} hours ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }
}