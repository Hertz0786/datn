class UserPhoto {
  const UserPhoto({
    required this.id,
    required this.url,
    required this.caption,
    required this.sourceType,
    this.postId,
    this.createdAt,
  });

  final String id;
  final String url;
  final String caption;
  final String sourceType;
  final String? postId;
  final DateTime? createdAt;

  factory UserPhoto.fromJson(Map<String, dynamic> json) {
    return UserPhoto(
      id: (json['id'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      caption: (json['caption'] ?? '').toString(),
      sourceType: (json['sourceType'] ?? '').toString(),
      postId: json['postId']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
