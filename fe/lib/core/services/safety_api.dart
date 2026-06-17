import '../models/community_rule.dart';
import '../network/api_client.dart';

class SafetyApi {
  SafetyApi._();

  static final SafetyApi instance = SafetyApi._();

  final ApiClient _api = ApiClient.instance;

  Future<List<CommunityRule>> getRules() async {
    final dynamic response = await _api.get(
      '/api/safety/rules',
      authRequired: false,
    );
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CommunityRule.fromJson)
        .toList();
  }

  Future<void> submitReport({
    required String targetType,
    required String targetId,
    required String category,
    required String details,
    required int urgency,
  }) async {
    await _api.post(
      '/api/safety/reports',
      body: <String, dynamic>{
        'targetType': targetType,
        'targetId': targetId,
        'category': category,
        'details': details,
        'urgency': urgency,
      },
    );
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }
}
