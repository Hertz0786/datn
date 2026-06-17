import '../models/media_asset.dart';
import '../network/api_client.dart';

class MediaApi {
  MediaApi._();

  static final MediaApi instance = MediaApi._();

  final ApiClient _api = ApiClient.instance;

  Future<MediaAsset> upload({
    required String filePath,
    String sourceType = 'OTHER',
    String? sourceId,
  }) async {
    final Map<String, String> fields = <String, String>{
      'sourceType': sourceType,
    };
    if (sourceId != null && sourceId.trim().isNotEmpty) {
      fields['sourceId'] = sourceId.trim();
    }

    final dynamic response = await _api.uploadFile(
      '/api/media/upload',
      filePath: filePath,
      fields: fields,
    );
    // The upload response wraps the asset under `media` and also
    // returns a top-level `moderation` block with the score and
    // threshold info. We merge them so the create-post screen can
    // show a friendly message without a second round-trip.
    final Map<String, dynamic> data = _toMap(response);
    final Map<String, dynamic> media = _toMap(data['media']);
    final Map<String, dynamic> moderation = _toMap(data['moderation']);
    if (moderation.isNotEmpty) {
      media['moderation'] = moderation;
    }
    return MediaAsset.fromJson(media);
  }

  Future<MediaAsset> updateSource({
    required String mediaId,
    required String sourceType,
    required String sourceId,
  }) async {
    final dynamic response = await _api.patch(
      '/api/media/$mediaId/source',
      body: <String, dynamic>{'sourceType': sourceType, 'sourceId': sourceId},
    );
    return MediaAsset.fromJson(_toMap(_toMap(response)['media']));
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }
}
