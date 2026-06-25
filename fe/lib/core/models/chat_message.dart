class CallMeta {
  const CallMeta({
    required this.callId,
    required this.callType,
    required this.status,
    required this.durationSeconds,
    required this.initiatorId,
  });

  final String callId;
  final String callType; // 'voice' | 'video'
  final String status; // 'missed' | 'ended' | 'rejected' | 'cancelled'
  final int durationSeconds;
  final String initiatorId;

  bool get isVideo => callType == 'video';
  bool get isMissed => status == 'missed';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isConnected => status == 'ended' && durationSeconds > 0;

  factory CallMeta.fromJson(Map<String, dynamic> json) {
    return CallMeta(
      callId: (json['callId'] ?? '').toString(),
      callType: (json['callType'] ?? 'voice').toString(),
      status: (json['status'] ?? 'ended').toString(),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      initiatorId: (json['initiatorId'] ?? '').toString(),
    );
  }
}

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
    this.callMeta,
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
  final CallMeta? callMeta;

  bool get isPostShare => type == 'POST_SHARE';
  bool get isCallBanner => type == 'CALL' && callMeta != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final dynamic rawCallMeta = json['callMeta'];
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
      callMeta: rawCallMeta is Map
          ? CallMeta.fromJson(Map<String, dynamic>.from(rawCallMeta))
          : null,
    );
  }
}
