class FriendRequestItem {
  const FriendRequestItem({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.sender,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime? createdAt;
  final dynamic sender;

  factory FriendRequestItem.fromJson(Map<String, dynamic> json) {
    String readId(dynamic value) {
      if (value is Map<String, dynamic>) {
        return (value['_id'] ?? '').toString();
      }
      return (value ?? '').toString();
    }

    return FriendRequestItem(
      id: (json['_id'] ?? '').toString(),
      senderId: readId(json['senderId']),
      receiverId: readId(json['receiverId']),
      status: (json['status'] ?? '').toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      sender: json['sender'] is Map<String, dynamic>
          ? json['sender'] as Map<String, dynamic>
          : null,
    );
  }
}
