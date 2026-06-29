class TrendingTopic {
  const TrendingTopic({
    required this.topic,
    required this.postCount,
  });

  final String topic;
  final int postCount;

  factory TrendingTopic.fromJson(Map<String, dynamic> json) {
    return TrendingTopic(
      topic: (json['topic'] as String?) ?? '',
      postCount: (json['postCount'] as num?)?.toInt() ?? 0,
    );
  }
}
