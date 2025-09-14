import '../services/logger_service.dart';

class Quote {
  final String id;
  final String quote;
  final String author;
  final List<String> tags;
  final String createdAt;
  final String updatedAt;
  final String? createdBy;
  final String? imageUrl;

  Quote({
    required this.id,
    required this.quote,
    required this.author,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
    this.imageUrl,
  });

  factory Quote.fromJson(Map<String, dynamic> json) {
    try {
      return Quote(
        id: json['id'] ?? '',
        quote: json['quote'] ?? '',
        author: json['author'] ?? '',
        tags: List<String>.from(json['tags'] ?? []),
        createdAt: json['created_at'] ?? '',
        updatedAt: json['updated_at'] ?? '',
        createdBy: json['created_by'],
        imageUrl: json['image_url'],
      );
    } catch (e) {
      LoggerService.error('❌ Error parsing quote from JSON: $json', error: e);
      rethrow;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'quote': quote,
      'author': author,
      'tags': tags,
      if (imageUrl != null) 'image_url': imageUrl,
    };
  }
}