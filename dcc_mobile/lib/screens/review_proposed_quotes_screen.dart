import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../services/logger_service.dart';
import '../themes.dart';

class ReviewProposedQuotesScreen extends StatefulWidget {
  const ReviewProposedQuotesScreen({super.key});

  @override
  State<ReviewProposedQuotesScreen> createState() => _ReviewProposedQuotesScreenState();
}

class _ReviewProposedQuotesScreenState extends State<ReviewProposedQuotesScreen> {
  List<Map<String, dynamic>> _proposedQuotes = [];
  bool _isLoading = false;
  String? _processingId;
  
  static final String apiEndpoint = dotenv.env['API_ENDPOINT']?.replaceAll('/quote', '') ?? '';

  @override
  void initState() {
    super.initState();
    _loadProposedQuotes();
  }

  Future<void> _loadProposedQuotes() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication required'),
              backgroundColor: Colors.red,
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
          _proposedQuotes = List<Map<String, dynamic>>.from(data['quotes'] ?? []);
        });
      } else {
        LoggerService.debug('Failed to load proposed quotes: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load proposed quotes: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      LoggerService.debug('Error loading proposed quotes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Network error loading quotes'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _processQuote(String quoteId, String action, {String? feedback}) async {
    setState(() {
      _processingId = quoteId;
    });

    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final body = {
        'action': action,
      };
      
      if (feedback != null && feedback.isNotEmpty) {
        body['feedback'] = feedback;
      }

      final response = await http.put(
        Uri.parse('$apiEndpoint/proposed-quotes/$quoteId'),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Quote ${action}d successfully'),
              backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
            ),
          );
          
          // Reload the list
          _loadProposedQuotes();
        }
      } else {
        final error = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error['error'] ?? 'Failed to $action quote'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      LoggerService.debug('Error processing quote: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: Failed to $action quote'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _processingId = null;
      });
    }
  }

  void _showClearProcessedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Processed Quotes'),
        content: Text(
          'This will permanently delete ${_processedQuotes.length} processed quotes (approved/rejected) from the system. This action cannot be undone.\n\nPending quotes will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clearProcessedQuotes();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearProcessedQuotes() async {
    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication required'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Delete each processed quote
      int deletedCount = 0;
      for (final quote in _processedQuotes) {
        try {
          final response = await http.delete(
            Uri.parse('$apiEndpoint/proposed-quotes/${quote['id']}'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
          );
          
          if (response.statusCode == 200) {
            deletedCount++;
          }
        } catch (e) {
          LoggerService.debug('Error deleting quote ${quote['id']}: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $deletedCount processed quotes'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Reload the list
        _loadProposedQuotes();
      }
    } catch (e) {
      LoggerService.debug('Error clearing processed quotes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear processed quotes'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showApprovalDialog(Map<String, dynamic> quote) {
    final feedbackController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${quote['quote']}"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            Text('— ${quote['author']}'),
            const SizedBox(height: 16),
            TextField(
              controller: feedbackController,
              decoration: const InputDecoration(
                labelText: 'Approval notes (optional)',
                hintText: 'Add any notes about the approval...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
              _processQuote(
                quote['id'],
                'approve',
                feedback: feedbackController.text.isEmpty ? null : feedbackController.text,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectionDialog(Map<String, dynamic> quote) {
    final feedbackController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Quote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"${quote['quote']}"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 8),
            Text('— ${quote['author']}'),
            const SizedBox(height: 16),
            TextField(
              controller: feedbackController,
              decoration: const InputDecoration(
                labelText: 'Rejection reason (optional)',
                hintText: 'Explain why this quote is being rejected...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
              _processQuote(
                quote['id'],
                'reject',
                feedback: feedbackController.text.isEmpty ? null : feedbackController.text,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
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

  List<Map<String, dynamic>> get _pendingQuotes {
    return _proposedQuotes.where((quote) => quote['status'] == 'pending').toList();
  }

  List<Map<String, dynamic>> get _processedQuotes {
    return _proposedQuotes.where((quote) => quote['status'] != 'pending').toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Proposed Quotes'),
        centerTitle: true,
        actions: [
          if (_processedQuotes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: _isLoading ? null : _showClearProcessedDialog,
              tooltip: 'Clear Processed',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadProposedQuotes,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pendingQuotes.isNotEmpty) ...[
                    Text(
                      'Pending Review (${_pendingQuotes.length})',
                      style: TextStyle(
                        color: AppThemes.pendingColor(context),
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_pendingQuotes.map((quote) => _buildQuoteCard(quote, isPending: true))),
                    const SizedBox(height: 24),
                  ],
                  
                  if (_processedQuotes.isNotEmpty) ...[
                    Text(
                      'Recently Processed (${_processedQuotes.length})',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_processedQuotes.map((quote) => _buildQuoteCard(quote, isPending: false))),
                  ],
                  
                  if (_proposedQuotes.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 64,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 128),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No proposed quotes to review',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Proposed quotes will appear here for admin review',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildQuoteCard(Map<String, dynamic> quote, {required bool isPending}) {
    final status = quote['status'] ?? 'pending';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final isProcessing = _processingId == quote['id'];
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 4 : 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  statusIcon,
                  color: statusColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote['quote'] ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).textTheme.headlineLarge?.color,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '— ${quote['author'] ?? ''}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.headlineMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Metadata row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'By ${quote['proposer_name'] ?? quote['proposer_email'] ?? ''}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(quote['created_date']),
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
            
            // Tags if present
            ...() {
              final validTags = quote['tags'] != null 
                  ? (quote['tags'] as List)
                      .where((tag) => tag != null && tag.toString().trim().isNotEmpty)
                      .toList()
                  : <String>[];
              
              if (validTags.isNotEmpty) {
                return [
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: validTags.map((tag) => Chip(
                      label: Text(tag.toString().trim()),
                    )).toList(),
                  ),
                ];
              } else {
                return <Widget>[];
              }
            }(),
            
            // Notes if present
            if (quote['notes'] != null && quote['notes'].toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(alpha: 128),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Notes: ${quote['notes']}',
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ],
            
            // Admin feedback if present - completely removed for now to debug
            
            // Action buttons ONLY for pending quotes that are actually pending
            if (isPending && status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: isProcessing ? null : () => _showRejectionDialog(quote),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text('Reject', style: TextStyle(fontSize: 16)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: isProcessing ? null : () => _showApprovalDialog(quote),
                    icon: isProcessing 
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      isProcessing ? 'Processing...' : 'Approve',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ] else if (!isPending) ...[
              // For processed quotes, don't render any action buttons or empty containers
              const SizedBox.shrink(),
            ],
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
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }
}