import 'friend_request_item.dart';

class FriendshipStatus {
  const FriendshipStatus({
    required this.userId,
    required this.status,
    this.request,
  });

  final String userId;
  final String status;
  final FriendRequestItem? request;

  factory FriendshipStatus.fromJson(Map<String, dynamic> json) {
    final dynamic rawRequest = json['request'];

    return FriendshipStatus(
      userId: (json['userId'] ?? '').toString(),
      status: (json['status'] ?? 'NONE').toString(),
      request: rawRequest is Map<String, dynamic>
          ? FriendRequestItem.fromJson(rawRequest)
          : null,
    );
  }

  bool get isSelf => status == 'SELF';
  bool get isFriend => status == 'FRIENDS';
  bool get isOutgoingPending => status == 'OUTGOING_PENDING';
  bool get isIncomingPending => status == 'INCOMING_PENDING';
  bool get isNone => status == 'NONE';
}
