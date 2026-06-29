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

class MessagesPage {
  const MessagesPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<ChatMessage> items;
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

  Future<MessagesPage> listMessages(
    String chatId, {
    int limit = 50,
    String? before,
  }) async {
    final Map<String, dynamic> query = <String, dynamic>{'limit': limit};
    if (before != null && before.isNotEmpty) {
      query['before'] = before;
    }
    final dynamic response = await _api.get(
      '/api/chats/$chatId/messages',
      query: query,
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<ChatMessage> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
    return MessagesPage(
      items: items,
      hasMore: data['hasMore'] == true,
      nextBefore: data['nextBefore']?.toString(),
    );
  }

  Future<ChatMessage> sendMessage({
    required String chatId,
    required String content,
    List<String> mediaUrls = const <String>[],
    String voiceUrl = '',
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'content': content,
      'mediaUrls': mediaUrls,
    };
    if (voiceUrl.isNotEmpty) {
      body['voiceUrl'] = voiceUrl;
    }
    final dynamic response = await _api.post(
      '/api/chats/$chatId/messages',
      body: body,
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

  /// Mark every currently-unread message in [chatId] as read for the
  /// authenticated user. Idempotent — calling again after all messages
  /// are already read is a no-op on the server.
  Future<void> markChatRead(String chatId) async {
    if (chatId.isEmpty) {
      return;
    }
    await _api.post('/api/chats/$chatId/read');
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
