import '../models/chat_message.dart';
import '../models/chat_summary.dart';
import '../network/api_client.dart';

class ChatsPage {
  const ChatsPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<ChatSummary> items;
  final String? nextBefore;
  final bool hasMore;
}

class ChatsApi {
  ChatsApi._();

  static final ChatsApi instance = ChatsApi._();

  final ApiClient _api = ApiClient.instance;

  static const int _defaultPageSize = 20;

  Future<ChatsPage> listChats({
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/chats',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<ChatSummary> items =
        (data['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatSummary.fromJson)
            .toList();
    return ChatsPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<ChatSummary> createDirectChat(String targetUserId) async {
    final dynamic response = await _api.post(
      '/api/chats/direct',
      body: <String, dynamic>{'targetUserId': targetUserId},
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<ChatSummary> createGroupChat({
    required String title,
    required List<String> memberIds,
    String avatarUrl = '',
  }) async {
    final dynamic response = await _api.post(
      '/api/chats/group',
      body: <String, dynamic>{
        'title': title,
        'avatarUrl': avatarUrl,
        'memberIds': memberIds,
      },
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<ChatSummary> openSocialGroupChat(String groupId) async {
    final dynamic response = await _api.post('/api/groups/$groupId/chat');
    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<ChatSummary> updateGroupChat({
    required String chatId,
    String? title,
    String? avatarUrl,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (title != null) {
      body['title'] = title;
    }
    if (avatarUrl != null) {
      body['avatarUrl'] = avatarUrl;
    }

    final dynamic response = await _api.patch(
      '/api/chats/$chatId/group',
      body: body,
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<ChatSummary> addGroupMembers({
    required String chatId,
    required List<String> memberIds,
  }) async {
    final dynamic response = await _api.post(
      '/api/chats/$chatId/members',
      body: <String, dynamic>{'memberIds': memberIds},
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<ChatSummary> removeGroupMember({
    required String chatId,
    required String userId,
  }) async {
    final dynamic response = await _api.delete(
      '/api/chats/$chatId/members/$userId',
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatSummary.fromJson(_toMap(data['chat']));
  }

  Future<List<ChatMessage>> listMessages(String chatId) async {
    final dynamic response = await _api.get('/api/chats/$chatId/messages');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  Future<ChatMessage> sendMessage({
    required String chatId,
    required String content,
    List<String> mediaUrls = const <String>[],
  }) async {
    final dynamic response = await _api.post(
      '/api/chats/$chatId/messages',
      body: <String, dynamic>{'content': content, 'mediaUrls': mediaUrls},
    );

    final Map<String, dynamic> data = _toMap(response);
    return ChatMessage.fromJson(_toMap(data['data']));
  }

  Future<void> sendPostShare({
    required String chatId,
    required String postId,
  }) async {
    await _api.post(
      '/api/chats/$chatId/messages',
      body: <String, dynamic>{'postId': postId},
    );
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
