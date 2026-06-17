import '../network/api_client.dart';

class AssistantApi {
  AssistantApi._();

  static final AssistantApi instance = AssistantApi._();

  final ApiClient _api = ApiClient.instance;

  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final dynamic response = await _api.post(
      '/api/assistant/chat',
      body: <String, dynamic>{'message': message, 'history': history},
    );

    final Map<String, dynamic> data = _toMap(response);
    return (data['reply'] ?? '').toString();
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
