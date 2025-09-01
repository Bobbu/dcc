import 'package:flutter/material.dart';
import '../../models/quote.dart';

class DuplicateCleanupDialog extends StatefulWidget {
  final List<List<Quote>> duplicateGroups;
  final Function(List<String>) onCleanup;

  const DuplicateCleanupDialog({
    super.key,
    required this.duplicateGroups,
    required this.onCleanup,
  });

  @override
  State<DuplicateCleanupDialog> createState() => _DuplicateCleanupDialogState();
}

class _DuplicateCleanupDialogState extends State<DuplicateCleanupDialog> {
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
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade200),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Enhanced Detection: Now finds duplicates with minor differences in punctuation, spacing, or author attribution.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
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
                            '"${group.first.quote.length > 100 ? '${group.first.quote.substring(0, 100)}...' : group.first.quote}"',
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
                                    style: Theme.of(context).textTheme.bodySmall,
                                  )
                                : null,
                              value: isSelected,
                              onChanged: (value) {
                                setState(() {
                                  _selectedQuotesToDelete[quote.id] = value ?? false;
                                });
                              },
                            );
                          }),
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