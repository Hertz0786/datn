import '../../../core/network/api_client.dart';
import '../models/call_history_item.dart';

class CallApi {
  CallApi._();

  static final CallApi instance = CallApi._();

  final ApiClient _api = ApiClient.instance;

  Future<Map<String, dynamic>> initCall({
    required String calleeId,
    required String callType,
  }) async {
    final dynamic response = await _api.post(
      '/api/calls/init',
      body: <String, dynamic>{
        'calleeId': calleeId,
        'callType': callType,
      },
    );
    return _toMap(response);
  }

  Future<Map<String, dynamic>> acceptCall(String callId) async {
    final dynamic response = await _api.post('/api/calls/$callId/accept');
    return _toMap(response);
  }

  Future<void> rejectCall(String callId) async {
    await _api.post('/api/calls/$callId/reject');
  }

  Future<Map<String, dynamic>> endCall(String callId) async {
    final dynamic response = await _api.post('/api/calls/$callId/end');
    return _toMap(response);
  }

  Future<CallHistoryPage> listHistory({
    int limit = 30,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/calls/history',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<CallHistoryItem> items =
        (data['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CallHistoryItem.fromJson)
            .toList();
    return CallHistoryPage(
      items: items,
      hasMore: data['hasMore'] == true,
      nextBefore: data['nextBefore']?.toString(),
    );
  }

  Future<CallSettingsModel> getSettings() async {
    final dynamic response = await _api.get('/api/calls/settings');
    return CallSettingsModel.fromJson(_toMap(response));
  }

  Future<CallSettingsModel> updateSettings({
    String? whoCanCall,
    List<String>? allowedCallTypes,
    int? maxCallDurationSeconds,
    bool? notificationsEnabled,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (whoCanCall != null) body['whoCanCall'] = whoCanCall;
    if (allowedCallTypes != null) body['allowedCallTypes'] = allowedCallTypes;
    if (maxCallDurationSeconds != null) {
      body['maxCallDurationSeconds'] = maxCallDurationSeconds;
    }
    if (notificationsEnabled != null) {
      body['notificationsEnabled'] = notificationsEnabled;
    }
    final dynamic response = await _api.patch(
      '/api/calls/settings',
      body: body,
    );
    return CallSettingsModel.fromJson(_toMap(response));
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return <String, dynamic>{};
  }
}

class CallHistoryPage {
  const CallHistoryPage({
    required this.items,
    required this.hasMore,
    this.nextBefore,
  });

  final List<CallHistoryItem> items;
  final bool hasMore;
  final String? nextBefore;
}

class CallSettingsModel {
  const CallSettingsModel({
    required this.whoCanCall,
    required this.allowedCallTypes,
    required this.maxCallDurationSeconds,
    required this.notificationsEnabled,
  });

  final String whoCanCall;
  final List<String> allowedCallTypes;
  final int maxCallDurationSeconds;
  final bool notificationsEnabled;

  factory CallSettingsModel.fromJson(Map<String, dynamic> json) {
    return CallSettingsModel(
      whoCanCall: (json['whoCanCall'] ?? 'friends_only').toString(),
      allowedCallTypes: (json['allowedCallTypes'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      maxCallDurationSeconds:
          (json['maxCallDurationSeconds'] as num?)?.toInt() ?? 0,
      notificationsEnabled: json['notificationsEnabled'] != false,
    );
  }
}
