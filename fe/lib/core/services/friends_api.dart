import '../models/friend_request_item.dart';
import '../models/friendship_status.dart';
import '../models/public_user.dart';
import '../network/api_client.dart';

class FriendsPage {
  const FriendsPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<PublicUser> items;
  final String? nextBefore;
  final bool hasMore;
}

class FriendRequestsPage {
  const FriendRequestsPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<FriendRequestItem> items;
  final String? nextBefore;
  final bool hasMore;
}

class FriendsApi {
  FriendsApi._();

  static final FriendsApi instance = FriendsApi._();

  final ApiClient _api = ApiClient.instance;

  static const int _defaultPageSize = 20;

  Future<FriendsPage> listFriends({
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/friends',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<PublicUser> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PublicUser.fromJson)
        .toList();
    return FriendsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<FriendsPage> listUserFriends({
    required String userId,
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/friends/users/$userId',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<PublicUser> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PublicUser.fromJson)
        .toList();
    return FriendsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<List<PublicUser>> mutualFriends({
    required String userId,
    int limit = 12,
  }) async {
    final dynamic response = await _api.get(
      '/api/friends/mutual/$userId',
      query: <String, dynamic>{'limit': limit},
    );
    final Map<String, dynamic> data = _toMap(response);
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PublicUser.fromJson)
        .toList();
  }

  Future<FriendRequestsPage> incomingRequests({
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/friends/requests/incoming',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<FriendRequestItem> items =
        (data['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FriendRequestItem.fromJson)
            .toList();
    return FriendRequestsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<FriendshipStatus> friendshipStatus(String userId) async {
    final dynamic response = await _api.get('/api/friends/status/$userId');
    return FriendshipStatus.fromJson(_toMap(response));
  }

  Future<void> sendRequest(String receiverId) async {
    await _api.post(
      '/api/friends/requests',
      body: <String, dynamic>{'receiverId': receiverId},
    );
  }

  Future<void> removeFriend(String friendId) async {
    await _api.delete('/api/friends/$friendId');
  }

  Future<void> updateRequest({
    required String requestId,
    required String action,
  }) async {
    await _api.patch(
      '/api/friends/requests/$requestId',
      body: <String, dynamic>{'action': action},
    );
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
