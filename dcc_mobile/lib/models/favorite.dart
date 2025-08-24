import '../services/logger_service.dart';
import 'quote.dart';

class Favorite {
  final String quoteId;
  final String createdAt;
  final Quote quote;

  Favorite({
    required this.quoteId,
    required this.createdAt,
    required this.quote,
  });

  factory Favorite.fromJson(Map<String, dynamic> json) {
    try {
      final quoteData = json['quote'] ?? {};
      
      return Favorite(
        quoteId: json['quote_id'] ?? '',
        createdAt: json['created_at'] ?? '',
        quote: Quote(
          id: json['quote_id'] ?? '',
          quote: quoteData['quote'] ?? '',
          author: quoteData['author'] ?? '',
          tags: List<String>.from(quoteData['tags'] ?? []),
          createdAt: json['created_at'] ?? '',
          updatedAt: json['created_at'] ?? '',
        ),
      );
    } catch (e) {
      LoggerService.error('❌ Error parsing favorite from JSON: $json', error: e);
      rethrow;
    }
  }
}