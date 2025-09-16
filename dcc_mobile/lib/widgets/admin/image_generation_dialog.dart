import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/openai_image_generator.dart';

class ImageGenerationDialog extends StatefulWidget {
  final String? initialQuote;
  final String? initialAuthor;
  final String? initialTags;
  final String? quoteId;
  final String? existingImageUrl;

  const ImageGenerationDialog({
    super.key,
    this.initialQuote,
    this.initialAuthor,
    this.initialTags,
    this.quoteId,
    this.existingImageUrl,
  });

  @override
  State<ImageGenerationDialog> createState() => _ImageGenerationDialogState();
}

class _ImageGenerationDialogState extends State<ImageGenerationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quoteController = TextEditingController();
  final _authorController = TextEditingController();
  final _tagsController = TextEditingController();
  final _customUrlController = TextEditingController();
  
  bool _isGenerating = false;
  String? _generatedImageUrl;
  String? _errorMessage;
  Timer? _statusTimer;
  String _jobStatus = '';
  bool _useCustomUrl = false;

  @override
  void initState() {
    super.initState();
    _quoteController.text = widget.initialQuote ?? '';
    _authorController.text = widget.initialAuthor ?? '';
    _tagsController.text = widget.initialTags ?? '';
    _generatedImageUrl = widget.existingImageUrl;
  }

  @override
  void dispose() {
    _quoteController.dispose();
    _authorController.dispose();
    _customUrlController.dispose();
    _tagsController.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _generateImage() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedImageUrl = null;
      _jobStatus = 'Submitting job...';
    });

    try {
      // Submit the job
      final jobId = await OpenAIImageGenerator.submitImageGenerationJob(
        quote: _quoteController.text.trim(),
        author: _authorController.text.trim(),
        tags: _tagsController.text.trim().isNotEmpty 
            ? _tagsController.text.trim() 
            : null,
        quoteId: widget.quoteId,
      );

      setState(() {
        _jobStatus = 'Job submitted. Generating image...';
      });

      // Start polling for status
      _startStatusPolling(jobId);
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to submit job: $e';
        _isGenerating = false;
        _jobStatus = '';
      });
    }
  }

  Future<void> _saveCustomUrl() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_useCustomUrl || _customUrlController.text.trim().isEmpty) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _jobStatus = 'Processing URL and extracting direct image link...';
    });

    try {
      // Auto-prepend https:// if no protocol specified
      String imageUrl = _customUrlController.text.trim();
      if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
        imageUrl = 'https://$imageUrl';
      }
      
      // If we have a quote ID, update it directly
      if (widget.quoteId != null) {
        final success = await OpenAIImageGenerator.saveCustomImageUrl(
          quoteId: widget.quoteId!,
          imageUrl: imageUrl,
        );

        if (success) {
          // Force image refresh by clearing cache
          final imageProvider = NetworkImage(imageUrl);
          imageProvider.evict();
          
          setState(() {
            _generatedImageUrl = imageUrl;
            _isGenerating = false;
            _jobStatus = 'Custom image URL saved successfully!';
          });
        } else {
          throw Exception('Failed to save custom image URL');
        }
      } else {
        // No quote ID - just show the URL as if it was generated
        setState(() {
          _generatedImageUrl = imageUrl;
          _isGenerating = false;
          _jobStatus = 'Custom image URL ready!';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save custom URL: $e';
        _isGenerating = false;
        _jobStatus = '';
      });
    }
  }

  void _startStatusPolling(String jobId) {
    _statusTimer?.cancel();
    
    // Poll every 2 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await OpenAIImageGenerator.checkJobStatus(jobId);
        
        if (status['status'] == 'completed') {
          setState(() {
            _generatedImageUrl = status['imageUrl'];
            _isGenerating = false;
            _jobStatus = 'Image generated successfully!';
          });
          timer.cancel();
        } else if (status['status'] == 'failed') {
          setState(() {
            _errorMessage = 'Generation failed: ${status['error'] ?? 'Unknown error'}';
            _isGenerating = false;
            _jobStatus = '';
          });
          timer.cancel();
        } else if (status['status'] == 'processing') {
          setState(() {
            _jobStatus = 'Processing image... This may take up to 2 minutes.';
          });
        }
      } catch (e) {
        // Continue polling unless it's been too long
        if (timer.tick > 60) {  // Stop after 2 minutes
          setState(() {
            _errorMessage = 'Timeout: Image generation is taking too long';
            _isGenerating = false;
            _jobStatus = '';
          });
          timer.cancel();
        }
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Icon(
                    Icons.image,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.existingImageUrl != null 
                        ? 'Update Quote Image' 
                        : 'Generate Quote Image',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ) ?? const TextStyle(),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Quote input
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
                            return 'Quote is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Author input
                      TextFormField(
                        controller: _authorController,
                        decoration: const InputDecoration(
                          labelText: 'Author *',
                          hintText: 'Enter the author name...',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Author is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Tags input
                      TextFormField(
                        controller: _tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags (Optional)',
                          hintText: 'motivation, success, business...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Custom URL option
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Switch(
                                  value: _useCustomUrl,
                                  onChanged: (value) {
                                    setState(() {
                                      _useCustomUrl = value;
                                      if (value) {
                                        _errorMessage = null;
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Use Custom Image URL',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: 'Provide your own image URL instead of generating with AI',
                                  child: Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (_useCustomUrl) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _customUrlController,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                                decoration: const InputDecoration(
                                  labelText: 'Image URL *',
                                  hintText: 'Direct image URL or sharing page URL',
                                  helperText: 'You can paste sharing URLs from reve.com, etc.',
                                  helperMaxLines: 2,
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.link),
                                ),
                                validator: _useCustomUrl ? (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'URL is required when using custom URL';
                                  }
                                  // Just check if it looks like a valid URL (we'll auto-add https if needed)
                                  if (!value.contains('.') || value.contains(' ')) {
                                    return 'Please enter a valid URL (e.g., example.com/image.jpg)';
                                  }
                                  return null;
                                } : null,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isGenerating ? null : (_useCustomUrl ? _saveCustomUrl : _generateImage),
                                    icon: _isGenerating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(_useCustomUrl ? Icons.save : Icons.auto_awesome),
                                    label: Text(_isGenerating 
                                        ? 'Processing...' 
                                        : _useCustomUrl
                                            ? 'Save Custom Image'
                                            : widget.existingImageUrl != null 
                                                ? 'Generate New Image'
                                                : 'Generate Image'),
                                  ),
                                ],
                              ),
                              if (_jobStatus.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _jobStatus,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Generated image
                      if (_generatedImageUrl != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Generated Image:',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ) ?? const TextStyle(),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 300,
                                    minHeight: 150,
                                  ),
                                  child: Image.network(
                                    _generatedImageUrl!.contains('?') 
                                        ? '$_generatedImageUrl&t=${DateTime.now().millisecondsSinceEpoch}'
                                        : '$_generatedImageUrl?t=${DateTime.now().millisecondsSinceEpoch}',
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    headers: {
                                      'User-Agent': 'Mozilla/5.0 (compatible; Quote-Me-App/1.0)',
                                    },
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return Container(
                                        height: 200,
                                        alignment: Alignment.center,
                                        child: CircularProgressIndicator(
                                          value: loadingProgress.expectedTotalBytes != null
                                              ? loadingProgress.cumulativeBytesLoaded /
                                                  loadingProgress.expectedTotalBytes!
                                              : null,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 200,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.errorContainer,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.broken_image,
                                                size: 48,
                                                color: Theme.of(context).colorScheme.error,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Failed to load image',
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Error: ${error.toString()}',
                                                style: TextStyle(
                                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                                  fontSize: 10,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Image URL: $_generatedImageUrl',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
}