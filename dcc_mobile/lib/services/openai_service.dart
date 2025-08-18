import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService {
  static const String _baseUrl = 'https://api.openai.com/v1/chat/completions';
  
  static String get _apiKey {
    final key = dotenv.env['OPENAI_API_KEY'] ?? '';
    print('🔑 OpenAI API Key loaded: ${key.isNotEmpty ? "✅ Found (${key.length} chars)" : "❌ Missing"}');
    return key;
  }

  /// Generate up to 5 relevant tags for a quote using OpenAI's GPT model
  static Future<List<String>> generateTagsForQuote({
    required String quote,
    required String author,
    List<String> existingTags = const [],
  }) async {
    final apiKey = _apiKey;
    if (apiKey.isEmpty) {
      print('❌ OpenAI API key not found in environment variables');
      print('Available env vars: ${dotenv.env.keys.toList()}');
      throw Exception('OpenAI API key not configured - check .env file');
    }

    try {
      // Create a comprehensive prompt for tag generation
      final prompt = _buildTagGenerationPrompt(quote, author, existingTags);
      print("🔑 The prompt will be: ${prompt}");
      
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': 'gpt-4o-mini',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a thoughtful tag selector. You analyze quotes deeply to understand their core meaning, then select the most relevant tags from a provided list. You ONLY choose from existing tags and NEVER create new ones. Always return a JSON array of 3-5 selected tags.'
            },
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'max_tokens': 100,
          'temperature': 0.2,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final content = data['choices'][0]['message']['content'] as String;
        
        // Parse the JSON response to extract tags
        return _parseTagsFromResponse(content);
      } else if (response.statusCode == 429) {
        // Rate limit hit - provide helpful error message
        throw Exception('Rate limit exceeded. Please wait a moment and try again with fewer quotes or longer delays.');
      } else {
        throw Exception('OpenAI API request failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('❌ Error generating tags: $e');
      rethrow;
    }
  }

  /// Build a comprehensive prompt for tag generation
  static String _buildTagGenerationPrompt(String quote, String author, List<String> existingTags) {
    final existingTagsText = existingTags.isNotEmpty 
        ? existingTags.join(', ')
        : 'No existing tags provided.';
    
    return '''
Analyze this quote and select exactly 3-5 tags that best capture its core meaning. Choose ONLY from the existing tags provided.

Quote: "$quote"
Author: $author

Available tags to choose from: $existingTagsText

Instructions:
1. Think deeply about what this quote is really about (not just surface keywords)
2. Select 3-5 tags from the list above that best match the quote's meaning
3. Avoid tags that don't strongly relate to the quote's core message
4. Return only a JSON array of selected tags

Example response: ["Thinking", "Wisdom", "Reflection"]
''';
  }

  /// Parse tags from the OpenAI response, handling various response formats
  static List<String> _parseTagsFromResponse(String content) {
    try {
      // Clean up the response - remove any markdown formatting or extra text
      String cleanContent = content.trim();
      
      // Remove markdown code blocks if present
      cleanContent = cleanContent.replaceAll('```json', '').replaceAll('```', '').trim();
      
      // Look for JSON array pattern
      final jsonMatch = RegExp(r'\[(.*?)\]').firstMatch(cleanContent);
      if (jsonMatch != null) {
        cleanContent = jsonMatch.group(0)!;
      }
      
      // Parse the JSON array
      final List<dynamic> tagList = json.decode(cleanContent);
      
      // Convert to strings and clean up
      final tags = tagList
          .map((tag) => tag.toString().trim())
          .where((tag) => tag.isNotEmpty)
          .map((tag) => _cleanTag(tag))
          .where((tag) => tag.isNotEmpty)
          .take(5) // Ensure we don't exceed 5 tags
          .toList();
      
      return tags;
    } catch (e) {
      print('❌ Error parsing tags from response: $e');
      print('Response content: $content');
      
      // Fallback: try to extract words that look like tags
      return _extractTagsFallback(content);
    }
  }

  /// Clean and format individual tags
  static String _cleanTag(String tag) {
    // Remove quotes and extra whitespace
    tag = tag.replaceAll('"', '').replaceAll("'", '').trim();
    
    // Ensure proper title case
    if (tag.isNotEmpty) {
      return tag.split(' ')
          .map((word) => word.isNotEmpty 
              ? word[0].toUpperCase() + word.substring(1).toLowerCase()
              : word)
          .join(' ');
    }
    
    return tag;
  }

  /// Fallback method to extract tags if JSON parsing fails
  static List<String> _extractTagsFallback(String content) {
    // Look for comma-separated words that could be tags
    final words = content
        .replaceAll('[', '').replaceAll(']', '').replaceAll('{', '').replaceAll('}', '')
        .replaceAll('"', '').replaceAll("'", '')
        .split(RegExp(r'[,\n]'))
        .map((word) => _cleanTag(word))
        .where((word) => word.isNotEmpty && word.length > 2 && word.length < 20)
        .take(5)
        .toList();
    
    return words;
  }

  /// Test the OpenAI connection and API key
  static Future<bool> testConnection() async {
    try {
      await generateTagsForQuote(
        quote: "The only way to do great work is to love what you do.",
        author: "Steve Jobs",
      );
      return true;
    } catch (e) {
      print('❌ OpenAI connection test failed: $e');
      return false;
    }
  }
}