class PublicUser {
  const PublicUser({
    required this.id,
    required this.displayName,
    required this.username,
    required this.age,
    required this.role,
    required this.avatarUrl,
    this.coverUrl = '',
    required this.bio,
    required this.favoriteTopics,
    this.privacy = const UserPrivacy(),
    this.lastActiveAt,
  });

  final String id;
  final String displayName;
  final String username;
  final int age;
  final String role;
  final String avatarUrl;
  final String coverUrl;
  final String bio;
  final List<String> favoriteTopics;
  final UserPrivacy privacy;
  final DateTime? lastActiveAt;

  factory PublicUser.fromJson(Map<String, dynamic> json) {
    return PublicUser(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      age: (json['age'] as num?)?.toInt() ?? 0,
      role: (json['role'] ?? 'CHILD').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      bio: (json['bio'] ?? '').toString(),
      favoriteTopics: (json['favoriteTopics'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      privacy: UserPrivacy.fromJson(
        json['privacy'] is Map<String, dynamic>
            ? json['privacy'] as Map<String, dynamic>
            : const <String, dynamic>{},
      ),
      lastActiveAt: _parseDate(json['lastActiveAt']),
    );
  }

  String get initials {
    final String source = displayName.trim().isEmpty
        ? username.trim()
        : displayName.trim();
    if (source.isEmpty) {
      return '?';
    }

    final List<String> parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      final String first = parts.first;
      return first.length >= 2
          ? first.substring(0, 2).toUpperCase()
          : first.toUpperCase();
    }

    final String firstInitial = parts.first.substring(0, 1).toUpperCase();
    final String lastInitial = parts.last.substring(0, 1).toUpperCase();
    return '$firstInitial$lastInitial';
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) {
    return null;
  }
  if (raw is DateTime) {
    return raw;
  }
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw);
  }
  return null;
}

class UserPrivacy {
  const UserPrivacy({
    this.allowFriendRequests = true,
    this.allowComments = true,
    this.safeSearchOnly = true,
  });

  final bool allowFriendRequests;
  final bool allowComments;
  final bool safeSearchOnly;

  factory UserPrivacy.fromJson(Map<String, dynamic> json) {
    return UserPrivacy(
      allowFriendRequests: json['allowFriendRequests'] != false,
      allowComments: json['allowComments'] != false,
      safeSearchOnly: json['safeSearchOnly'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'allowFriendRequests': allowFriendRequests,
      'allowComments': allowComments,
      'safeSearchOnly': safeSearchOnly,
    };
  }
}
