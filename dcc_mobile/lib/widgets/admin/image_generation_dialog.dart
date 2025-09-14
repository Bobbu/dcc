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
  
  bool _isGenerating = false;
  String? _generatedImageUrl;
  String? _errorMessage;
  String? _currentJobId;
  Timer? _statusTimer;
  String _jobStatus = '';

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
        _currentJobId = jobId;
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

  Future<void> _generateTestImage() async {
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _generatedImageUrl = null;
      _jobStatus = 'Submitting test job...';
    });

    try {
      final jobId = await OpenAIImageGenerator.generateTestImage();
      
      setState(() {
        _currentJobId = jobId;
        _jobStatus = 'Test job submitted. Generating image...';
      });

      // Start polling for status
      _startStatusPolling(jobId);
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to submit test job: $e';
        _isGenerating = false;
        _jobStatus = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
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
            const SizedBox(height: 24),

            // Form
            Expanded(
              child: SingleChildScrollView(
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

                      // Action buttons
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isGenerating ? null : _generateImage,
                                    icon: _isGenerating
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.auto_awesome),
                                    label: Text(_isGenerating 
                                        ? 'Processing...' 
                                        : widget.existingImageUrl != null 
                                            ? 'Generate New Image'
                                            : 'Generate Image'),
                                  ),
                                  const SizedBox(width: 12),
                                  TextButton.icon(
                                    onPressed: _isGenerating ? null : _generateTestImage,
                                    icon: const Icon(Icons.science),
                                    label: const Text('Test Image'),
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
                                child: Image.network(
                                  _generatedImageUrl!,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
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
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
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