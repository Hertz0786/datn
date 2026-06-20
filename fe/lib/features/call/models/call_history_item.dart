import '../../../core/models/public_user.dart';

enum CallStatus { ringing, accepted, rejected, ended, missed, failed, blocked }

enum CallDirection { incoming, outgoing, missed }

class CallHistoryItem {
  const CallHistoryItem({
    required this.id,
    required this.callType,
    required this.status,
    required this.direction,
    required this.otherUser,
    required this.startedAt,
    this.acceptedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.endReason,
  });

  final String id;
  final String callType; // 'voice' | 'video'
  final String status;
  final CallDirection direction;
  final PublicUser otherUser;
  final DateTime startedAt;
  final DateTime? acceptedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final String? endReason;

  bool get isVideo => callType == 'video';

  bool get isMissed => status == 'missed' || status == 'ringing' && endedAt != null;

  factory CallHistoryItem.fromJson(Map<String, dynamic> json) {
    final bool isOutgoing = json['isOutgoing'] == true;
    final dynamic profileJson = isOutgoing ? json['calleeProfile'] : json['initiatorProfile'];
    final PublicUser other = profileJson is Map<String, dynamic>
        ? PublicUser.fromJson(profileJson)
        : PublicUser(
            id: '',
            displayName: '',
            username: '',
            age: 0,
            role: 'CHILD',
            avatarUrl: '',
            bio: '',
            favoriteTopics: const [],
          );

    final String status = (json['status'] ?? 'ended').toString();
    CallDirection direction;
    if (status == 'missed') {
      direction = CallDirection.missed;
    } else {
      direction = isOutgoing ? CallDirection.outgoing : CallDirection.incoming;
    }

    return CallHistoryItem(
      id: (json['id'] ?? '').toString(),
      callType: (json['callType'] ?? 'voice').toString(),
      status: status,
      direction: direction,
      otherUser: other,
      startedAt: _parseDate(json['startedAt']) ?? DateTime.now(),
      acceptedAt: _parseDate(json['acceptedAt']),
      endedAt: _parseDate(json['endedAt']),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
      endReason: json['endReason']?.toString(),
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return raw;
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
  return null;
}
