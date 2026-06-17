class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.url,
    required this.sourceType,
    required this.sourceId,
    required this.resourceType,
    required this.status,
    this.unsafeScore = 0,
    this.unsafeLabel = '',
    this.thresholdExceeded = false,
  });

  final String id;
  final String url;
  final String sourceType;
  final String sourceId;
  final String resourceType;
  final String status;

  /// AI moderation fields — populated from the `/api/media/upload`
  /// response's `moderation` block.
  final double unsafeScore;
  final String unsafeLabel;

  /// True when the AI moderation service flagged this asset as
  /// needing admin review (i.e. the unsafe score crossed the
  /// configured threshold). The Flutter UI uses this to show the
  /// "we suspect this image contains sensitive content" message
  /// before the user even tries to publish.
  final bool thresholdExceeded;

  bool get isVideo => resourceType.toLowerCase() == 'video';

  /// Convenience: was this asset flagged by the moderation
  /// pipeline, regardless of the threshold? Used to decide
  /// whether the create-post screen should warn the user.
  bool get isFlagged =>
      status == 'BLOCKED' ||
      status == 'REVIEW' ||
      thresholdExceeded;

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> moderation = json['moderation'] is Map
        ? (json['moderation'] as Map).map(
            (key, dynamic value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    return MediaAsset(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      url: (json['secureUrl'] ?? json['url'] ?? '').toString(),
      sourceType: (json['sourceType'] ?? '').toString(),
      sourceId: (json['sourceId'] ?? '').toString(),
      resourceType: (json['resourceType'] ?? 'image').toString(),
      status: (json['status'] ?? '').toString(),
      unsafeScore: (moderation['unsafeScore'] as num?)?.toDouble() ?? 0,
      unsafeLabel: (moderation['unsafeLabel'] ?? '').toString(),
      thresholdExceeded: moderation['thresholdExceeded'] == true,
    );
  }
}
