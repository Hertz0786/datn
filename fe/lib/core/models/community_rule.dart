class CommunityRule {
  const CommunityRule({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;

  factory CommunityRule.fromJson(Map<String, dynamic> json) {
    return CommunityRule(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
    );
  }
}
