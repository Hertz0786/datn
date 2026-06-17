import '../models/support_message.dart';
import '../models/support_thread.dart';
import '../network/api_client.dart';

class SupportConversation {
  const SupportConversation({required this.thread, required this.messages});

  final SupportThread thread;
  final List<SupportMessage> messages;
}

class SupportApi {
  SupportApi._();

  static final SupportApi instance = SupportApi._();

  final ApiClient _api = ApiClient.instance;

  Future<SupportConversation> getThread() async {
    final dynamic response = await _api.get('/api/support/thread');
    return _readConversation(response);
  }

  Future<SupportMessage> sendMessage({
    required String content,
    String subject = 'Support request',
    String category = 'GENERAL',
  }) async {
    final dynamic response = await _api.post(
      '/api/support/messages',
      body: <String, dynamic>{
        'content': content,
        'subject': subject,
        'category': category,
      },
    );

    final Map<String, dynamic> data = _toMap(response);
    return SupportMessage.fromJson(_toMap(data['message']));
  }

  Future<SupportThread> resolveThread(String threadId) async {
    final dynamic response = await _api.patch(
      '/api/support/thread/$threadId/resolve',
    );
    return SupportThread.fromJson(_toMap(_toMap(response)['thread']));
  }

  SupportConversation _readConversation(dynamic response) {
    final Map<String, dynamic> data = _toMap(response);
    final List<dynamic> rawMessages =
        data['messages'] as List<dynamic>? ?? const [];

    return SupportConversation(
      thread: SupportThread.fromJson(_toMap(data['thread'])),
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(SupportMessage.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
