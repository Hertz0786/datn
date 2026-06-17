import '../../features/groups/group_info.dart';
import '../models/feed_post.dart';
import '../models/group_detail_data.dart';
import '../models/public_user.dart';
import '../network/api_client.dart';

class GroupsPage {
  const GroupsPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<GroupInfo> items;
  final String? nextBefore;
  final bool hasMore;
}

class GroupPostsPage {
  const GroupPostsPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<FeedPost> items;
  final String? nextBefore;
  final bool hasMore;
}

class GroupsApi {
  GroupsApi._();

  static final GroupsApi instance = GroupsApi._();

  final ApiClient _api = ApiClient.instance;

  static const int _defaultPageSize = 20;

  Future<GroupsPage> listGroups({
    String? q,
    String? topic,
    int? age,
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/groups',
      query: <String, dynamic>{
        'q': q,
        'topic': topic,
        'age': age,
        'limit': limit,
        'before': before,
      },
    );

    final Map<String, dynamic> data = _toMap(response);
    final List<GroupInfo> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GroupInfo.fromJson)
        .toList();
    return GroupsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<GroupsPage> listUserGroups({
    required String userId,
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/groups/users/$userId',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );

    final Map<String, dynamic> data = _toMap(response);
    final List<GroupInfo> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(GroupInfo.fromJson)
        .toList();
    return GroupsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<GroupInfo> createGroup({
    required String name,
    required String topic,
    String description = '',
    int ageMin = 7,
    int ageMax = 14,
  }) async {
    final dynamic response = await _api.post(
      '/api/groups',
      body: <String, dynamic>{
        'name': name,
        'topic': topic,
        'description': description,
        'ageMin': ageMin,
        'ageMax': ageMax,
      },
    );
    final Map<String, dynamic> data = _toMap(response);
    return GroupInfo.fromJson(_toMap(data['group']));
  }

  Future<GroupDetailData> getGroup(String groupId) async {
    final dynamic response = await _api.get('/api/groups/$groupId');
    final Map<String, dynamic> data = _toMap(response);

    final GroupInfo group = GroupInfo.fromJson(_toMap(data['group']));
    final List<dynamic> membersRaw =
        data['members'] as List<dynamic>? ?? const [];
    final List<dynamic> pendingMembersRaw =
        data['pendingMembers'] as List<dynamic>? ?? const [];

    final List<PublicUser> members = membersRaw
        .map(_publicUserFromMembership)
        .where((PublicUser user) => user.id.isNotEmpty)
        .toList();
    final List<PublicUser> pendingMembers = pendingMembersRaw
        .map(_publicUserFromMembership)
        .where((PublicUser user) => user.id.isNotEmpty)
        .toList();

    return GroupDetailData(
      group: group,
      members: members,
      pendingMembers: pendingMembers,
      isJoined: data['isJoined'] == true,
      isPending: data['isPending'] == true,
    );
  }

  Future<String> joinGroup(String groupId) async {
    final dynamic response = await _api.post('/api/groups/$groupId/join');
    return (_toMap(response)['message'] ?? '').toString();
  }

  Future<void> leaveGroup(String groupId) async {
    await _api.post('/api/groups/$groupId/leave');
  }

  Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    await _api.delete('/api/groups/$groupId/members/$userId');
  }

  Future<void> updateJoinRequest({
    required String groupId,
    required String userId,
    required String action,
  }) async {
    await _api.patch(
      '/api/groups/$groupId/join-requests/$userId',
      body: <String, dynamic>{'action': action},
    );
  }

  Future<GroupPostsPage> listGroupPosts({
    required String groupId,
    int limit = 20,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/groups/$groupId/posts',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<FeedPost> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedPost.fromJson)
        .toList();
    return GroupPostsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }

  PublicUser _publicUserFromMembership(dynamic member) {
    if (member is! Map<String, dynamic>) {
      return _emptyUser;
    }

    final dynamic userField = member['userId'];
    if (userField is Map<String, dynamic>) {
      return PublicUser.fromJson(userField);
    }

    return _emptyUser;
  }

  static const PublicUser _emptyUser = PublicUser(
    id: '',
    displayName: '',
    username: '',
    age: 0,
    role: 'CHILD',
    avatarUrl: '',
    bio: '',
    favoriteTopics: <String>[],
  );
}
