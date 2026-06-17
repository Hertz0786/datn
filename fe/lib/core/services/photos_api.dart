import '../models/user_photo.dart';
import '../network/api_client.dart';

class PhotosApi {
  PhotosApi._();

  static final PhotosApi instance = PhotosApi._();

  final ApiClient _api = ApiClient.instance;

  Future<List<UserPhoto>> myPhotos() async {
    final dynamic response = await _api.get('/api/photos/me');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(UserPhoto.fromJson)
        .where((UserPhoto photo) => photo.url.trim().isNotEmpty)
        .toList();
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }
}
