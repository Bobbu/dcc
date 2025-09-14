import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'auth_service.dart';

class OpenAIImageGenerator {
  static const int _timeoutSeconds = 30; // Quick response for job submission

  /// Submits an image generation job and returns a job ID
  /// The actual generation happens asynchronously
  static Future<String> submitImageGenerationJob({
    required String quote,
    required String author,
    String? tags,
    String? quoteId,
  }) async {
    try {
      final idToken = await AuthService.getIdToken();
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/admin/generate-image'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'quote': quote,
          'author': author,
          'tags': tags ?? '',
          if (quoteId != null) 'quote_id': quoteId,
        }),
      ).timeout(Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 202) {  // Accepted
        final data = jsonDecode(response.body);
        return data['jobId'] ?? '';
      } else {
        throw Exception('Failed to submit job: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      throw Exception('Error submitting job: $e');
    }
  }

  /// Checks the status of an image generation job
  static Future<Map<String, dynamic>> checkJobStatus(String jobId) async {
    try {
      final idToken = await AuthService.getIdToken();
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/admin/image-generation-status/$jobId'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Job not found');
      } else {
        throw Exception('Failed to check status: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error checking status: $e');
    }
  }

  /// Legacy method for backward compatibility - now submits async job
  static Future<String> generateImageForQuote({
    required String quote,
    required String author,
    String? tags,
    String? quoteId,
  }) async {
    // Submit the job
    final jobId = await submitImageGenerationJob(
      quote: quote,
      author: author,
      tags: tags,
      quoteId: quoteId,
    );
    
    // For backward compatibility, return the job ID
    // The UI should be updated to handle async generation
    return jobId;
  }

  /// Generates a sophisticated prompt for consistent quote imagery
  static String _buildImagePrompt({
    required String quote,
    required String author,
    String? tags,
  }) {
    // Build a sophisticated prompt that creates consistent, professional imagery
    final baseStyle = """
Create a sophisticated, inspirational image that visually represents the essence of this quote.

Style Guidelines:
- Professional, high-quality digital art aesthetic
- Warm, inviting color palette with subtle gradients
- Soft, diffused lighting that creates depth and atmosphere
- Clean composition with balanced visual elements
- Slightly abstract or symbolic rather than literal interpretation
- Suitable for displaying alongside inspirational text
- 16:9 aspect ratio for versatile display

Visual Elements to Consider:
- Symbolic representations of the quote's core message
- Natural elements like light, sky, water, or landscapes when appropriate
- Geometric patterns or flowing lines that suggest growth, progress, or wisdom
- Subtle textures that add depth without overwhelming the composition
- Color psychology that matches the quote's emotional tone

Quote: "$quote"
Author: $author
""";

    // Add context based on tags if provided
    if (tags != null && tags.isNotEmpty) {
      final tagList = tags.split(',').map((t) => t.trim()).join(', ');
      return '$baseStyle\nThematic Context: $tagList';
    }

    return baseStyle;
  }

  /// Generates a test image using the backend proxy
  static Future<String> generateTestImage() async {
    return submitImageGenerationJob(
      quote: "The only way to do great work is to love what you do.",
      author: "Steve Jobs",
      tags: "motivation, success, passion",
    );
  }
}