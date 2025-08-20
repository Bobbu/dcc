class Tag {
  final String name;
  final int? usageCount;
  final String? createdAt;
  final String? updatedAt;
  final String? createdBy;

  Tag({
    required this.name,
    this.usageCount,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  factory Tag.fromJson(dynamic json) {
    // Handle both string format (just the tag name) and object format
    if (json is String) {
      return Tag(name: json);
    }
    
    return Tag(
      name: json['name'] ?? json['tag'] ?? '',
      usageCount: json['usage_count'] ?? json['count'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      createdBy: json['created_by'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (usageCount != null) 'usage_count': usageCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  // Helper method to create from simple string list (common in API responses)
  static List<Tag> fromStringList(List<String> tagStrings) {
    return tagStrings.map((tag) => Tag(name: tag)).toList();
  }

  // Helper method to convert list of Tags to list of strings (for API requests)
  static List<String> toStringList(List<Tag> tags) {
    return tags.map((tag) => tag.name).toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => name;
}