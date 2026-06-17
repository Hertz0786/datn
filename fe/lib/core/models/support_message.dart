class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderRole,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String senderRole;
  final String content;
  final DateTime? createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      threadId: (json['threadId'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      senderRole: (json['senderRole'] ?? 'USER').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
