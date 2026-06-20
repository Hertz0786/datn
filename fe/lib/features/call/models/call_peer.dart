/// Represents a brief summary of a contact shown in the incoming/outgoing
/// call UI. The backend embeds a similar payload inside socket events.
class CallPeer {
  const CallPeer({
    required this.id,
    required this.displayName,
    required this.username,
    required this.age,
    required this.role,
    this.avatarUrl = '',
  });

  final String id;
  final String displayName;
  final String username;
  final int age;
  final String role;
  final String avatarUrl;

  String get label =>
      displayName.trim().isNotEmpty ? displayName : username;

  factory CallPeer.fromJson(Map<String, dynamic> json) {
    return CallPeer(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      age: (json['age'] as num?)?.toInt() ?? 0,
      role: (json['role'] ?? 'CHILD').toString(),
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
    );
  }
}
