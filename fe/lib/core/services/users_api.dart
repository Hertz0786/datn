import '../models/public_user.dart';
import '../network/api_client.dart';

class UsersApi {
  UsersApi._();

  static final UsersApi instance = UsersApi._();

  final ApiClient _api = ApiClient.instance;

  Future<PublicUser> getMe() async {
    final dynamic response = await _api.get('/api/users/me');
    final Map<String, dynamic> data = _toMap(response);
    return PublicUser.fromJson(_toMap(data['user']));
  }

  Future<PublicUser> getById(String userId) async {
    final dynamic response = await _api.get('/api/users/$userId');
    final Map<String, dynamic> data = _toMap(response);
    return PublicUser.fromJson(_toMap(data['user']));
  }

  Future<PublicUser> updateMe({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? coverUrl,
    List<String>? favoriteTopics,
    Map<String, dynamic>? privacy,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (displayName != null) {
      body['displayName'] = displayName;
    }
    if (bio != null) {
      body['bio'] = bio;
    }
    if (avatarUrl != null) {
      body['avatarUrl'] = avatarUrl;
    }
    if (coverUrl != null) {
      body['coverUrl'] = coverUrl;
    }
    if (favoriteTopics != null) {
      body['favoriteTopics'] = favoriteTopics;
    }
    if (privacy != null) {
      body['privacy'] = privacy;
    }

    final dynamic response = await _api.patch('/api/users/me', body: body);
    final Map<String, dynamic> data = _toMap(response);
    return PublicUser.fromJson(_toMap(data['user']));
  }

  Future<List<PublicUser>> searchUsers({
    String? query,
    int? minAge,
    int? maxAge,
  }) async {
    final dynamic response = await _api.get(
      '/api/users',
      query: <String, dynamic>{'q': query, 'minAge': minAge, 'maxAge': maxAge},
    );

    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(PublicUser.fromJson)
        .toList();
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
