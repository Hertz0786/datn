import '../models/user_badge.dart';
import '../network/api_client.dart';

class BadgesApi {
  BadgesApi._();

  static final BadgesApi instance = BadgesApi._();

  final ApiClient _api = ApiClient.instance;

  Future<List<UserBadge>> myBadges() async {
    final dynamic response = await _api.get('/api/badges/me');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(UserBadge.fromJson)
        .toList();
  }

  Future<List<UserBadge>> userBadges(String userId) async {
    final dynamic response = await _api.get('/api/badges/users/$userId');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(UserBadge.fromJson)
        .toList();
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }
}
