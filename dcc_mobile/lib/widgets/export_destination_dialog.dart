import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

enum ExportDestination { download, clipboard, s3 }
enum ExportFormat { json, csv }

class ExportDestinationDialog extends StatefulWidget {
  final String exportType; // 'quotes' or 'tags'
  final int? itemCount;
  
  const ExportDestinationDialog({
    super.key,
    required this.exportType,
    this.itemCount,
  });

  @override
  State<ExportDestinationDialog> createState() => _ExportDestinationDialogState();
}

class _ExportDestinationDialogState extends State<ExportDestinationDialog> {
  ExportDestination? _selectedDestination;
  ExportFormat _selectedFormat = ExportFormat.json;
  
  @override
  void initState() {
    super.initState();
    // Set default destination based on platform
    if (kIsWeb) {
      _selectedDestination = ExportDestination.download;
    } else {
      _selectedDestination = ExportDestination.s3;
    }
  }
  
  String _getEstimatedSize() {
    if (widget.itemCount == null) return '';
    
    // Rough estimation: ~500 bytes per quote, ~50 bytes per tag
    int estimatedBytes = widget.exportType == 'quotes' 
        ? widget.itemCount! * 500 
        : widget.itemCount! * 50;
    
    if (estimatedBytes < 1024) {
      return '~${estimatedBytes} bytes';
    } else if (estimatedBytes < 1024 * 1024) {
      return '~${(estimatedBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '~${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
  
  bool _isClipboardSafe() {
    if (widget.itemCount == null) {
      // For full database exports, assume it's NOT safe for clipboard
      // since we're likely dealing with hundreds or thousands of items
      return false;
    }
    
    // Consider clipboard safe for < 100 quotes or < 500 tags
    if (widget.exportType == 'quotes') {
      return widget.itemCount! < 100;
    } else {
      return widget.itemCount! < 500;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimatedSize = _getEstimatedSize();
    final isClipboardSafe = _isClipboardSafe();
    
    return AlertDialog(
      title: Text('Export ${widget.exportType.substring(0, 1).toUpperCase()}${widget.exportType.substring(1)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.itemCount != null 
                            ? '${widget.itemCount} ${widget.exportType}'
                            : 'Export all ${widget.exportType} from database',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.itemCount != null && estimatedSize.isNotEmpty
                            ? 'Estimated size: $estimatedSize'
                            : 'Full database export (size determined by backend)',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            Text(
              'Select Export Destination:',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            
            // Download option (Web only)
            if (kIsWeb) ...[
              RadioListTile<ExportDestination>(
                title: const Text('Download'),
                subtitle: const Text('Download file to your device'),
                secondary: const Icon(Icons.download),
                value: ExportDestination.download,
                groupValue: _selectedDestination,
                onChanged: (value) {
                  setState(() {
                    _selectedDestination = value;
                  });
                },
              ),
            ],
            
            // Clipboard option
            RadioListTile<ExportDestination>(
              title: const Text('Clipboard'),
              subtitle: Text(
                isClipboardSafe 
                  ? 'Copy to clipboard for easy sharing'
                  : widget.itemCount == null
                    ? 'Full database export - use Cloud Storage instead'
                    : 'Large dataset - consider using Cloud Storage',
                style: TextStyle(
                  color: isClipboardSafe ? null : theme.colorScheme.error,
                ),
              ),
              secondary: Icon(
                Icons.content_copy,
                color: isClipboardSafe ? null : theme.colorScheme.error,
              ),
              value: ExportDestination.clipboard,
              groupValue: _selectedDestination,
              onChanged: (value) {
                if (!isClipboardSafe) {
                  // Show warning dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Large Dataset Warning'),
                      content: Text(
                        'This export contains ${widget.itemCount} ${widget.exportType}, '
                        'which may be too large for the clipboard. '
                        'Consider using Cloud Storage instead.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() {
                              _selectedDestination = value;
                            });
                          },
                          child: const Text('Continue Anyway'),
                        ),
                      ],
                    ),
                  );
                } else {
                  setState(() {
                    _selectedDestination = value;
                  });
                }
              },
            ),
            
            // S3 Cloud Storage option
            RadioListTile<ExportDestination>(
              title: const Text('Cloud Storage'),
              subtitle: const Text('Export to cloud with shareable link (48 hours)'),
              secondary: const Icon(Icons.cloud_upload),
              value: ExportDestination.s3,
              groupValue: _selectedDestination,
              onChanged: (value) {
                setState(() {
                  _selectedDestination = value;
                });
              },
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            
            Text(
              'Export Format:',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            
            // Format selection
            Row(
              children: [
                Expanded(
                  child: RadioListTile<ExportFormat>(
                    title: const Text('JSON'),
                    dense: true,
                    value: ExportFormat.json,
                    groupValue: _selectedFormat,
                    onChanged: (value) {
                      setState(() {
                        _selectedFormat = value!;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<ExportFormat>(
                    title: const Text('CSV'),
                    dense: true,
                    value: ExportFormat.csv,
                    groupValue: _selectedFormat,
                    onChanged: (value) {
                      setState(() {
                        _selectedFormat = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            
            if (_selectedDestination == ExportDestination.s3) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cloud exports are compressed and available for 48 hours',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _selectedDestination == null ? null : () {
            Navigator.pop(context, {
              'destination': _selectedDestination,
              'format': _selectedFormat,
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Export'),
        ),
      ],
    );
  }
}