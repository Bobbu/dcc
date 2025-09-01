#!/usr/bin/env dart
/// Test script to demonstrate enhanced duplicate detection
/// Run with: dart test_duplicate_detection.dart

void main() {
  print('=== Enhanced Duplicate Detection Test ===\n');
  
  // Test normalization function
  print('Testing text normalization:');
  print('Original: "Hello   World!"');
  print('Normalized: "${_normalizeText("Hello   World!")}"');
  print('Original: "Einstein."');
  print('Normalized: "${_normalizeText("Einstein.")}"');
  print('Original: ""Smart quotes""');
  print('Normalized: "${_normalizeText('\"Smart quotes\"')}"');
  print('');
  
  // Test similarity calculation
  print('Testing similarity calculation:');
  print('Similarity between "Hello World" and "Hello World": ${_calculateSimilarity("hello world", "hello world")}');
  print('Similarity between "Hello World" and "Hello World!": ${_calculateSimilarity("hello world", "hello world!")}');
  print('Similarity between "Albert Einstein" and "Einstein": ${_calculateSimilarity("albert einstein", "einstein")}');
  print('Similarity between "To be or not to be" and "To be, or not to be": ${_calculateSimilarity("to be or not to be", "to be, or not to be")}');
  print('');
  
  // Test sample duplicate scenarios
  print('Testing duplicate scenarios:');
  
  // Scenario 1: Exact duplicates with different punctuation
  var quote1 = TestQuote('The only way to do great work is to love what you do.', 'Steve Jobs');
  var quote2 = TestQuote('The only way to do great work is to love what you do', 'Steve Jobs');
  print('Scenario 1 - Punctuation difference:');
  print('Quote 1: "${quote1.quote}" — ${quote1.author}');
  print('Quote 2: "${quote2.quote}" — ${quote2.author}');
  print('Are similar: ${_areSimilarQuotes(quote1, quote2)}\n');
  
  // Scenario 2: Author attribution variations
  var quote3 = TestQuote('Life is what happens to you while you\'re busy making other plans.', 'John Lennon');
  var quote4 = TestQuote('Life is what happens to you while you\'re busy making other plans.', 'John Lennon.');
  print('Scenario 2 - Author punctuation:');
  print('Quote 3: "${quote3.quote}" — ${quote3.author}');
  print('Quote 4: "${quote4.quote}" — ${quote4.author}');
  print('Are similar: ${_areSimilarQuotes(quote3, quote4)}\n');
  
  // Scenario 3: Minor quote differences
  var quote5 = TestQuote('Be yourself; everyone else is already taken.', 'Oscar Wilde');
  var quote6 = TestQuote('Be yourself, everyone else is already taken.', 'Oscar Wilde');
  print('Scenario 3 - Minor punctuation in quote:');
  print('Quote 5: "${quote5.quote}" — ${quote5.author}');
  print('Quote 6: "${quote6.quote}" — ${quote6.author}');
  print('Are similar: ${_areSimilarQuotes(quote5, quote6)}\n');
  
  // Scenario 4: Should NOT be considered similar
  var quote7 = TestQuote('The best time to plant a tree was 20 years ago.', 'Chinese Proverb');
  var quote8 = TestQuote('A journey of a thousand miles begins with a single step.', 'Lao Tzu');
  print('Scenario 4 - Different quotes:');
  print('Quote 7: "${quote7.quote}" — ${quote7.author}');
  print('Quote 8: "${quote8.quote}" — ${quote8.author}');
  print('Are similar: ${_areSimilarQuotes(quote7, quote8)}\n');
  
  print('=== Test Complete ===');
}

class TestQuote {
  final String quote;
  final String author;
  
  TestQuote(this.quote, this.author);
}

/// Normalizes text for softer comparison by removing extra whitespace,
/// punctuation variations, and common differences
String _normalizeText(String text) {
  return text
      .trim()
      .toLowerCase()
      // Remove extra whitespace
      .replaceAll(RegExp(r'\s+'), ' ')
      // Normalize punctuation
      .replaceAll(RegExp(r'[""]'), '"')
      .replaceAll(RegExp(r'['']'), "'")
      .replaceAll(RegExp(r'[—–]'), '-')
      .replaceAll(RegExp(r'…'), '...')
      // Remove trailing periods from authors
      .replaceAll(RegExp(r'\.$'), '');
}

/// Calculates similarity ratio between two strings using a simple
/// character-based approach suitable for quotes and author names
double _calculateSimilarity(String text1, String text2) {
  if (text1.isEmpty && text2.isEmpty) return 1.0;
  if (text1.isEmpty || text2.isEmpty) return 0.0;
  
  // For very similar lengths, use character-by-character comparison
  if ((text1.length - text2.length).abs() <= 3) {
    int matches = 0;
    int maxLength = text1.length > text2.length ? text1.length : text2.length;
    
    for (int i = 0; i < maxLength; i++) {
      if (i < text1.length && i < text2.length && text1[i] == text2[i]) {
        matches++;
      }
    }
    return matches / maxLength;
  }
  
  // For different lengths, use word-based comparison
  List<String> words1 = text1.split(' ');
  List<String> words2 = text2.split(' ');
  
  int commonWords = 0;
  for (String word1 in words1) {
    if (words2.contains(word1) && word1.length > 2) {
      commonWords++;
    }
  }
  
  int totalUniqueWords = (words1.toSet()..addAll(words2.toSet())).length;
  return totalUniqueWords > 0 ? (2.0 * commonWords) / (words1.length + words2.length) : 0.0;
}

/// Checks if two quotes are similar enough to be considered duplicates
bool _areSimilarQuotes(TestQuote quote1, TestQuote quote2) {
  String normalizedQuote1 = _normalizeText(quote1.quote);
  String normalizedQuote2 = _normalizeText(quote2.quote);
  String normalizedAuthor1 = _normalizeText(quote1.author);
  String normalizedAuthor2 = _normalizeText(quote2.author);
  
  // Exact match after normalization
  if (normalizedQuote1 == normalizedQuote2 && normalizedAuthor1 == normalizedAuthor2) {
    return true;
  }
  
  // Similar quote text with exact author match
  double quoteSimilarity = _calculateSimilarity(normalizedQuote1, normalizedQuote2);
  if (quoteSimilarity >= 0.90 && normalizedAuthor1 == normalizedAuthor2) {
    return true;
  }
  
  // Exact quote with similar author (handles attribution variations)
  double authorSimilarity = _calculateSimilarity(normalizedAuthor1, normalizedAuthor2);
  if (normalizedQuote1 == normalizedQuote2 && authorSimilarity >= 0.85) {
    return true;
  }
  
  // Both quote and author are very similar (for cases with minor differences)
  if (quoteSimilarity >= 0.95 && authorSimilarity >= 0.90) {
    return true;
  }
  
  return false;
}