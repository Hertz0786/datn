import '../models/app_notification.dart';
import '../network/api_client.dart';

class NotificationsApi {
  NotificationsApi._();

  static final NotificationsApi instance = NotificationsApi._();

  final ApiClient _api = ApiClient.instance;

  Future<List<AppNotification>> listNotifications() async {
    final dynamic response = await _api.get('/api/notifications');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromJson)
        .toList();
  }

  Future<void> markAllRead() async {
    await _api.patch('/api/notifications/read-all');
  }

  Future<void> markRead(String notificationId) async {
    await _api.patch('/api/notifications/$notificationId/read');
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    return <String, dynamic>{};
  }
}
