class UserBadge {
  const UserBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.earned,
    required this.progress,
    required this.target,
  });

  final String id;
  final String title;
  final String description;
  final String icon;
  final bool earned;
  final int progress;
  final int target;

  factory UserBadge.fromJson(Map<String, dynamic> json) {
    return UserBadge(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      icon: (json['icon'] ?? '').toString(),
      earned: json['earned'] == true,
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      target: (json['target'] as num?)?.toInt() ?? 1,
    );
  }
}
