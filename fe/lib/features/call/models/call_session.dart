import 'call_peer.dart';

/// Payload returned by POST /api/calls/init and POST /api/calls/:id/accept.
/// The same fields are also embedded inside the matching socket events.
class CallSession {
  const CallSession({
    required this.callId,
    required this.channelName,
    required this.callType,
    required this.token,
    required this.uid,
    required this.appId,
    this.peer,
  });

  final String callId;
  final String channelName;
  final String callType; // 'voice' | 'video'
  final String token;
  final int uid;
  final String appId;
  final CallPeer? peer;

  bool get isVideo => callType == 'video';

  factory CallSession.fromJson(Map<String, dynamic> json) {
    final dynamic peerJson = json['callee'] ?? json['caller'];
    return CallSession(
      callId: json['callId'].toString(),
      channelName: json['channelName'].toString(),
      callType: (json['callType'] ?? 'voice').toString(),
      token: (json['token'] ?? '').toString(),
      uid: (json['uid'] as num?)?.toInt() ?? 0,
      appId: (json['appId'] ?? '').toString(),
      peer: peerJson is Map<String, dynamic>
          ? CallPeer.fromJson(peerJson)
          : null,
    );
  }
}

/// Payload for call:incoming socket event.
class IncomingCall {
  const IncomingCall({
    required this.callId,
    required this.channelName,
    required this.callType,
    required this.caller,
  });

  final String callId;
  final String channelName;
  final String callType;
  final CallPeer caller;

  bool get isVideo => callType == 'video';

  factory IncomingCall.fromJson(Map<String, dynamic> json) {
    return IncomingCall(
      callId: (json['callId'] ?? '').toString(),
      channelName: (json['channelName'] ?? '').toString(),
      callType: (json['callType'] ?? 'voice').toString(),
      caller: CallPeer.fromJson(
        (json['caller'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }
}
