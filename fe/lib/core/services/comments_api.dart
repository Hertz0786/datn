import '../models/comment_item.dart';
import '../models/public_user.dart';
import '../network/api_client.dart';

class CommentLikeResult {
  const CommentLikeResult({
    required this.commentId,
    required this.liked,
    required this.likeCount,
  });

  final String commentId;
  final bool liked;
  final int likeCount;

  factory CommentLikeResult.fromJson(Map<String, dynamic> json) {
    return CommentLikeResult(
      commentId: (json['commentId'] ?? '').toString(),
      liked: json['liked'] == true,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class CommentReactionUser {
  const CommentReactionUser({required this.user, this.reactedAt});

  final PublicUser user;
  final DateTime? reactedAt;

  factory CommentReactionUser.fromJson(Map<String, dynamic> json) {
    return CommentReactionUser(
      user: PublicUser.fromJson(_readMap(json['user'])),
      reactedAt: DateTime.tryParse((json['reactedAt'] ?? '').toString()),
    );
  }
}

class CommentsApi {
  CommentsApi._();

  static final CommentsApi instance = CommentsApi._();

  final ApiClient _api = ApiClient.instance;

  Future<List<CommentItem>> listByPost(String postId) async {
    final dynamic response = await _api.get('/api/comments/posts/$postId');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];

    return items
        .whereType<Map<String, dynamic>>()
        .map(CommentItem.fromJson)
        .toList();
  }

  Future<CommentItem> createComment({
    required String postId,
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
      '/api/comments/posts/$postId',
      body: body,
    );

    final Map<String, dynamic> data = _toMap(response);
    return CommentItem.fromJson(_toMap(data['comment']));
  }

  Future<CommentItem> createReply({
    required String commentId,
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
      '/api/comments/$commentId/replies',
      body: body,
    );

    final Map<String, dynamic> data = _toMap(response);
    return CommentItem.fromJson(_toMap(data['reply']));
  }

  Future<CommentLikeResult> toggleLike(String commentId) async {
    final dynamic response = await _api.post('/api/comments/$commentId/like');
    return CommentLikeResult.fromJson(_toMap(response));
  }

  Future<List<CommentReactionUser>> reactionUsers(String commentId) async {
    final dynamic response = await _api.get(
      '/api/comments/$commentId/reactions',
    );
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(CommentReactionUser.fromJson)
        .toList();
  }

  Future<CommentItem> updateComment({
    required String commentId,
    required String content,
    List<String>? mediaUrls,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{'content': content};
    if (mediaUrls != null) {
      body['mediaUrls'] = mediaUrls;
    }
    final dynamic response = await _api.patch(
      '/api/comments/$commentId',
      body: body,
    );
    final Map<String, dynamic> data = _toMap(response);
    return CommentItem.fromJson(_toMap(data['comment']));
  }

  Future<void> deleteComment(String commentId) async {
    await _api.delete('/api/comments/$commentId');
  }

  Map<String, dynamic> _toMap(dynamic value) {
    return _readMap(value);
  }
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic item) => MapEntry(key.toString(), item));
  }
  return <String, dynamic>{};
}
