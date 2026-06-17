import 'package:flutter/material.dart';

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorId,
    required this.content,
    required this.topics,
    required this.mood,
    required this.mediaUrls,
    required this.authorDisplayName,
    required this.authorUsername,
    required this.authorAvatarUrl,
    required this.audience,
    bool? allowComments,
    bool? allowReactions,
    required this.commentCount,
    required this.reactionCount,
    required this.likedByMe,
    required this.createdAt,
    this.bookmarkedByMe = false,
    this.myReaction,
    this.reactions = const <String, int>{},
    this.groupId,
    this.authorLastActiveAt,
    this.status = 'PUBLISHED',
    this.pendingMediaReview = false,
    this.mediaModerationScore = 0,
    this.mediaModerationLabel = '',
  }) : _allowComments = allowComments,
       _allowReactions = allowReactions;

  final String id;
  final String authorId;
  final String content;
  final List<String> topics;
  final String mood;
  final List<String> mediaUrls;
  final String authorDisplayName;
  final String authorUsername;
  final String authorAvatarUrl;
  final String audience;
  final bool? _allowComments;
  final bool? _allowReactions;
  final int commentCount;
  final int reactionCount;
  final bool? likedByMe;

  bool get isLikedByMe => likedByMe == true;
  final bool bookmarkedByMe;
  final String? myReaction;
  final Map<String, int> reactions;
  final DateTime? createdAt;
  final String? groupId;
  final DateTime? authorLastActiveAt;

  // Moderation fields, populated by the backend when the post is
  // either waiting for review or has been reviewed.
  final String status;
  final bool pendingMediaReview;
  final double mediaModerationScore;
  final String mediaModerationLabel;

  /// True when the post is held back from the feed because an
  /// attached image crossed the safe-publish threshold. The detail
  /// screen uses this to show the "Đang chờ admin duyệt" banner.
  bool get isPendingReview => status == 'HIDDEN' && pendingMediaReview;

  bool get isPublic => audience.toUpperCase() == 'PUBLIC';
  bool get isFriendsOnly => audience.toUpperCase() == 'FRIENDS';
  bool get allowComments => _allowComments != false;
  bool get allowReactions => _allowReactions != false;
  bool get isGroupPost =>
      audience.toUpperCase() == 'GROUP' ||
      (groupId != null && groupId!.isNotEmpty);

  FeedPost copyWith({
    String? id,
    String? authorId,
    String? content,
    List<String>? topics,
    String? mood,
    List<String>? mediaUrls,
    String? authorDisplayName,
    String? authorUsername,
    String? authorAvatarUrl,
    String? audience,
    bool? allowComments,
    bool? allowReactions,
    int? commentCount,
    int? reactionCount,
    bool? likedByMe,
    bool? bookmarkedByMe,
    String? myReaction,
    bool clearMyReaction = false,
    Map<String, int>? reactions,
    DateTime? createdAt,
    String? groupId,
    DateTime? authorLastActiveAt,
    String? status,
    bool? pendingMediaReview,
    double? mediaModerationScore,
    String? mediaModerationLabel,
  }) {
    return FeedPost(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      content: content ?? this.content,
      topics: topics ?? this.topics,
      mood: mood ?? this.mood,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorUsername: authorUsername ?? this.authorUsername,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      audience: audience ?? this.audience,
      allowComments: allowComments ?? this.allowComments,
      allowReactions: allowReactions ?? this.allowReactions,
      commentCount: commentCount ?? this.commentCount,
      reactionCount: reactionCount ?? this.reactionCount,
      likedByMe: likedByMe ?? this.likedByMe ?? false,
      bookmarkedByMe: bookmarkedByMe ?? this.bookmarkedByMe,
      myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
      reactions: reactions ?? this.reactions,
      createdAt: createdAt ?? this.createdAt,
      groupId: groupId ?? this.groupId,
      authorLastActiveAt: authorLastActiveAt ?? this.authorLastActiveAt,
      status: status ?? this.status,
      pendingMediaReview: pendingMediaReview ?? this.pendingMediaReview,
      mediaModerationScore:
          mediaModerationScore ?? this.mediaModerationScore,
      mediaModerationLabel: mediaModerationLabel ?? this.mediaModerationLabel,
    );
  }

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> authorSnapshot = _readMap(
      json['authorSnapshot'],
    );
    final Map<String, dynamic> author = _readMap(json['author']);

    final Map<String, int> reactions = <String, int>{};
    if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((key, value) {
        if (value is num) {
          reactions[key.toString()] = value.toInt();
        }
      });
    }

    return FeedPost(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      authorId: _firstNonEmpty([
        json['authorId'],
        authorSnapshot['_id'],
        authorSnapshot['id'],
        author['_id'],
        author['id'],
      ]),
      content: (json['content'] ?? '').toString(),
      topics: (json['topics'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      mood: (json['mood'] ?? '').toString(),
      mediaUrls: (json['mediaUrls'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
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
      audience: _firstNonEmpty([
        json['audience'],
      ], fallback: 'FRIENDS').toUpperCase(),
      allowComments: json['allowComments'] != false,
      allowReactions: json['allowReactions'] != false,
      commentCount: (json['commentCount'] as num?)?.toInt() ?? 0,
      reactionCount: (json['reactionCount'] as num?)?.toInt() ?? 0,
      likedByMe: json['likedByMe'] == true,
      bookmarkedByMe: json['bookmarkedByMe'] == true,
      myReaction: (json['myReaction'] ?? '').toString().isEmpty
          ? null
          : (json['myReaction'] ?? '').toString(),
      reactions: reactions,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      groupId: (json['groupId'] ?? '').toString().isEmpty
          ? null
          : (json['groupId'] ?? '').toString(),
      authorLastActiveAt: authorSnapshot['lastActiveAt'] != null
          ? DateTime.tryParse(authorSnapshot['lastActiveAt'].toString())
          : null,
      status: (json['status'] ?? 'PUBLISHED').toString().toUpperCase(),
      pendingMediaReview: json['pendingMediaReview'] == true,
      mediaModerationScore:
          (json['mediaModerationScore'] as num?)?.toDouble() ?? 0,
      mediaModerationLabel: (json['mediaModerationLabel'] ?? '').toString(),
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

/// Catalog of supported reactions shared between UI and API.
const Map<String, ReactionOption> kReactionCatalog = <String, ReactionOption>{
  'heart': ReactionOption(icon: Icons.favorite, color: Color(0xFFFF5A9E)),
  'star': ReactionOption(icon: Icons.star_rounded, color: Color(0xFFFFC93C)),
  'laugh': ReactionOption(
    icon: Icons.emoji_emotions_rounded,
    color: Color(0xFFFFA94D),
  ),
  'wow': ReactionOption(icon: Icons.bolt_rounded, color: Color(0xFF7A5CFF)),
  'clap': ReactionOption(
    icon: Icons.celebration_rounded,
    color: Color(0xFF33B8FF),
  ),
};

class ReactionOption {
  const ReactionOption({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}
