class CommentItem {
  const CommentItem({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.content,
    required this.mediaUrls,
    required this.voiceUrl,
    required this.parentCommentId,
    required this.likeCount,
    required this.likedByMe,
    required this.createdAt,
    required this.replies,
    this.authorLastActiveAt,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorDisplayName;
  final String authorUsername;
  final String authorAvatarUrl;
  final String content;
  final List<String> mediaUrls;
  final String voiceUrl;
  final String? parentCommentId;
  final int likeCount;
  final bool? likedByMe;

  bool get isLikedByMe => likedByMe == true;
  final DateTime? createdAt;
  final List<CommentItem> replies;
  final DateTime? authorLastActiveAt;

  CommentItem copyWith({
    String? id,
    String? postId,
    String? authorId,
    String? authorDisplayName,
    String? authorUsername,
    String? authorAvatarUrl,
    String? content,
    List<String>? mediaUrls,
    String? voiceUrl,
    String? parentCommentId,
    int? likeCount,
    bool? likedByMe,
    DateTime? createdAt,
    List<CommentItem>? replies,
    DateTime? authorLastActiveAt,
  }) {
    return CommentItem(
      id: id ?? this.id,
      postId: postId ?? this.postId,
      authorId: authorId ?? this.authorId,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorUsername: authorUsername ?? this.authorUsername,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      content: content ?? this.content,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      voiceUrl: voiceUrl ?? this.voiceUrl,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe ?? false,
      createdAt: createdAt ?? this.createdAt,
      replies: replies ?? this.replies,
      authorLastActiveAt: authorLastActiveAt ?? this.authorLastActiveAt,
    );
  }

  factory CommentItem.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> authorSnapshot = _readMap(
      json['authorSnapshot'],
    );
    final Map<String, dynamic> author = _readMap(json['author']);

    final List<dynamic> repliesRaw =
        json['replies'] as List<dynamic>? ?? const [];

    return CommentItem(
      id: (json['_id'] ?? '').toString(),
      postId: (json['postId'] ?? '').toString(),
      authorId: (json['authorId'] ?? '').toString(),
      authorDisplayName: _firstNonEmpty([
        authorSnapshot['displayName'],
        author['displayName'],
        json['authorDisplayName'],
      ]),
      authorUsername: _firstNonEmpty([
        authorSnapshot['username'],
        author['username'],
        json['authorUsername'],
      ]),
      authorAvatarUrl: _firstNonEmpty([
        authorSnapshot['avatarUrl'],
        author['avatarUrl'],
        json['authorAvatarUrl'],
        json['avatarUrl'],
      ]),
      content: (json['content'] ?? '').toString(),
      mediaUrls: (json['mediaUrls'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      voiceUrl: (json['voiceUrl'] ?? '').toString(),
      parentCommentId: json['parentCommentId']?.toString(),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      authorLastActiveAt: authorSnapshot['lastActiveAt'] != null
          ? DateTime.tryParse(authorSnapshot['lastActiveAt'].toString())
          : null,
      replies: repliesRaw
          .whereType<Map<String, dynamic>>()
          .map(CommentItem.fromJson)
          .toList(),
    );
  }
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
  for (final dynamic value in values) {
    final String text = (value ?? '').toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return fallback;
}
