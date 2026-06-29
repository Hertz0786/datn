class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.payload,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime? readAt;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final dynamic rawPayload = json['payload'];

    return AppNotification(
      id: (json['_id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const <String, dynamic>{},
      readAt: json['readAt'] != null
          ? DateTime.tryParse(json['readAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  bool get isRead => readAt != null;

  String get title {
    final dynamic raw = payload['title'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'Notification';
  }

  String get body {
    final dynamic raw = payload['body'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return '';
  }
}
