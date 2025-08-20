import 'package:flutter/material.dart';
import '../../models/quote.dart';

class ImportResultsDialog extends StatefulWidget {
  final List<Quote> successfulQuotes;
  final List<Map<String, dynamic>> failedQuotes;
  final Function(List<Quote>) onRetry;

  const ImportResultsDialog({
    super.key,
    required this.successfulQuotes,
    required this.failedQuotes,
    required this.onRetry,
  });

  @override
  State<ImportResultsDialog> createState() => _ImportResultsDialogState();
}

class _ImportResultsDialogState extends State<ImportResultsDialog> {
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
                      const Icon(Icons.check_circle, color: Colors.green, size: 32),
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
                        const Icon(Icons.error, color: Colors.red, size: 32),
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
            const SizedBox(height: 16),
            if (widget.successfulQuotes.isNotEmpty) ...[
              const Text(
                'Successfully Imported:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.successfulQuotes.take(5).length,
                  itemBuilder: (context, index) {
                    final quote = widget.successfulQuotes[index];
                    return Card(
                      child: ListTile(
                        dense: true,
                        title: Text(
                          '"${quote.quote.length > 50 ? '${quote.quote.substring(0, 50)}...' : quote.quote}"',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('— ${quote.author}', style: const TextStyle(fontWeight: FontWeight.w500)),
                            Text(
                              'Tags: ${quote.tags.join(', ')}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.successfulQuotes.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '... and ${widget.successfulQuotes.length - 5} more',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ),
            ],
            if (hasFailures) ...[
              const SizedBox(height: 16),
              Text(
                'Failed Imports ($selectedCount selected for retry):',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _editableFailedQuotes.length,
                  itemBuilder: (context, index) {
                    final item = _editableFailedQuotes[index];
                    final quote = item['quote'] as Quote;
                    final isSelected = item['selected'] as bool;
                    
                    return Card(
                      color: isSelected ? null : Colors.grey.shade100,
                      child: CheckboxListTile(
                        dense: true,
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            _editableFailedQuotes[index]['selected'] = value ?? false;
                          });
                        },
                        title: Text(
                          '#${item['index']}: "${quote.quote.length > 40 ? '${quote.quote.substring(0, 40)}..." — ${quote.author}' : '${quote.quote}" — ${quote.author}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Error: ${item['error']}',
                              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                            ),
                            if (quote.tags.isNotEmpty)
                              Text(
                                'Tags: ${quote.tags.join(', ')}',
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                        secondary: IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editFailedQuote(index),
                        ),
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
              final quotesToRetry = _editableFailedQuotes
                  .where((item) => item['selected'] == true)
                  .map((item) => item['quote'] as Quote)
                  .toList();
              Navigator.of(context).pop();
              widget.onRetry(quotesToRetry);
            },
            child: Text('Retry Selected ($selectedCount)'),
          ),
      ],
    );
  }
}