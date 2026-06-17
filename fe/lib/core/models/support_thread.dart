class SupportThread {
  const SupportThread({
    required this.id,
    required this.userId,
    required this.subject,
    required this.category,
    required this.status,
    required this.lastMessageAt,
  });

  final String id;
  final String userId;
  final String subject;
  final String category;
  final String status;
  final DateTime? lastMessageAt;

  factory SupportThread.fromJson(Map<String, dynamic> json) {
    return SupportThread(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      subject: (json['subject'] ?? 'Support request').toString(),
      category: (json['category'] ?? 'GENERAL').toString(),
      status: (json['status'] ?? 'OPEN').toString(),
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.tryParse(json['lastMessageAt'].toString())
          : null,
    );
  }
}
