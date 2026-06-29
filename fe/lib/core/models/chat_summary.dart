import 'chat_message.dart';
import 'public_user.dart';

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.type,
    required this.groupId,
    required this.title,
    required this.avatarUrl,
    required this.memberIds,
    required this.memberUsers,
    required this.memberCount,
    required this.createdBy,
    required this.updatedAt,
    this.unreadCount = 0,
    this.otherUser,
    this.lastMessage,
  });

  final String id;
  final String type;
  final String groupId;
  final String title;
  final String avatarUrl;
  final List<String> memberIds;
  final List<PublicUser> memberUsers;
  final int memberCount;
  final String createdBy;
  final DateTime? updatedAt;
  final PublicUser? otherUser;
  final ChatMessage? lastMessage;

  /// Number of messages from other members that the current user has not
  /// read yet. Server-computed; falls back to 0 if the backend version
  /// does not yet expose it.
  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  bool get isMessageGroup => type.toUpperCase() == 'GROUP';
  bool get isSocialGroup => type.toUpperCase() == 'SOCIAL_GROUP';
  bool get isGroup => isMessageGroup || isSocialGroup;

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      type: (json['type'] ?? 'DIRECT').toString(),
      groupId: (json['groupId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
      memberIds: (json['memberIds'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      memberUsers: (json['memberUsers'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(PublicUser.fromJson)
          .toList(),
      memberCount:
          (json['memberCount'] as num?)?.toInt() ??
          (json['memberIds'] as List<dynamic>? ?? const []).length,
      createdBy: (json['createdBy'] ?? '').toString(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      otherUser: json['otherUser'] is Map<String, dynamic>
          ? PublicUser.fromJson(json['otherUser'] as Map<String, dynamic>)
          : null,
      lastMessage: json['lastMessage'] is Map<String, dynamic>
          ? ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
    );
  }

  ChatSummary copyWith({
    String? groupId,
    String? title,
    String? avatarUrl,
    List<String>? memberIds,
    List<PublicUser>? memberUsers,
    int? memberCount,
    String? createdBy,
    DateTime? updatedAt,
    int? unreadCount,
    PublicUser? otherUser,
    ChatMessage? lastMessage,
  }) {
    return ChatSummary(
      id: id,
      type: type,
      groupId: groupId ?? this.groupId,
      title: title ?? this.title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      memberIds: memberIds ?? this.memberIds,
      memberUsers: memberUsers ?? this.memberUsers,
      memberCount: memberCount ?? this.memberCount,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
    );
  }
}
