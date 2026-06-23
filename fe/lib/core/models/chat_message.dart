class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.mediaUrls,
    required this.voiceUrl,
    required this.type,
    required this.postId,
    required this.createdAt,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final List<String> mediaUrls;
  final String voiceUrl;
  final String type;
  final String? postId;
  final DateTime? createdAt;

  bool get isPostShare => type == 'POST_SHARE';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      chatId: (json['chatId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      mediaUrls: (json['mediaUrls'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      voiceUrl: (json['voiceUrl'] ?? '').toString(),
      type: (json['type'] ?? 'TEXT').toString(),
      postId: (json['postId'] ?? '').toString().isEmpty
          ? null
          : (json['postId'] ?? '').toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
