import '../models/feed_post.dart';
import '../models/public_user.dart';
import '../network/api_client.dart';

class PostLikeResult {
  const PostLikeResult({
    required this.postId,
    required this.liked,
    required this.reactionCount,
    this.reaction,
    this.reactions = const <String, int>{},
  });

  final String postId;
  final bool liked;
  final int reactionCount;
  final String? reaction;
  final Map<String, int> reactions;

  factory PostLikeResult.fromJson(Map<String, dynamic> json) {
    final Map<String, int> reactions = <String, int>{};
    if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((key, value) {
        if (value is num) {
          reactions[key.toString()] = value.toInt();
        }
      });
    }
    return PostLikeResult(
      postId: (json['postId'] ?? '').toString(),
      liked: json['liked'] == true,
      reactionCount: (json['reactionCount'] as num?)?.toInt() ?? 0,
      reaction: (json['reaction'] ?? '').toString().isEmpty
          ? null
          : (json['reaction'] ?? '').toString(),
      reactions: reactions,
    );
  }
}

class FeedPage {
  const FeedPage({
    required this.items,
    required this.nextBefore,
    required this.hasMore,
  });

  final List<FeedPost> items;
  final String? nextBefore;
  final bool hasMore;
}

class PostReactionUser {
  const PostReactionUser({
    required this.user,
    required this.reaction,
    this.reactedAt,
  });

  final PublicUser user;
  final String reaction;
  final DateTime? reactedAt;

  factory PostReactionUser.fromJson(Map<String, dynamic> json) {
    final dynamic userData = json['user'];
    final Map<String, dynamic> userMap = userData is Map<String, dynamic>
        ? userData
        : <String, dynamic>{};
    return PostReactionUser(
      user: PublicUser.fromJson(userMap),
      reaction: (json['reaction'] ?? '').toString(),
      reactedAt: DateTime.tryParse((json['reactedAt'] ?? '').toString()),
    );
  }
}

class PostsApi {
  PostsApi._();

  static final PostsApi instance = PostsApi._();

  final ApiClient _api = ApiClient.instance;

  static const int _defaultPageSize = 50;

  Future<void> sharePost(String postId) async {
    await _api.post('/api/posts/$postId/share');
  }

  Future<FeedPage> feed({
    String? q,
    String? topic,
    int? age,
    int limit = _defaultPageSize,
    String? before,
    String scope = 'all',
  }) async {
    final dynamic response = await _api.get(
      '/api/posts/feed',
      query: <String, dynamic>{
        'q': q,
        'topic': topic,
        'age': age,
        'limit': limit,
        'before': before,
        'scope': scope,
      },
    );

    final Map<String, dynamic> data = _toMap(response);
    final List<dynamic> items = data['items'] as List<dynamic>? ?? const [];
    final List<FeedPost> posts = items
        .whereType<Map<String, dynamic>>()
        .map(FeedPost.fromJson)
        .toList();

    return FeedPage(
      items: posts,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
  }

  Future<List<FeedPost>> myPosts() async {
    final dynamic response = await _api.get('/api/posts/mine');
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(FeedPost.fromJson)
        .toList();
  }

  Future<FeedPost> createPost({
    required String content,
    List<String> topics = const <String>[],
    String mood = '',
    List<String> mediaUrls = const <String>[],
    String audience = 'FRIENDS',
    bool allowComments = true,
    bool allowReactions = true,
    int ageMin = 7,
    int ageMax = 14,
    String? groupId,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'content': content,
      'topics': topics,
      'mood': mood,
      'mediaUrls': mediaUrls,
      'audience': audience,
      'allowComments': allowComments,
      'allowReactions': allowReactions,
      'ageMin': ageMin,
      'ageMax': ageMax,
    };
    if (groupId != null && groupId.isNotEmpty) {
      body['groupId'] = groupId;
    }

    final dynamic response = await _api.post('/api/posts', body: body);

    final Map<String, dynamic> data = _toMap(response);
    return FeedPost.fromJson(_toMap(data['post']));
  }

  /// Same as `createPost` but also returns the moderation verdict
  /// that the backend attaches to the response (`moderation` block).
  /// Used by the create-post screen to render a friendly message
  /// after the user hits publish.
  Future<({FeedPost post, bool needsReview, double mediaModerationScore})>
      createPostAndCheck({
    required String content,
    List<String> topics = const <String>[],
    String mood = '',
    List<String> mediaUrls = const <String>[],
    String audience = 'FRIENDS',
    bool allowComments = true,
    bool allowReactions = true,
    int ageMin = 7,
    int ageMax = 14,
    String? groupId,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'content': content,
      'topics': topics,
      'mood': mood,
      'mediaUrls': mediaUrls,
      'audience': audience,
      'allowComments': allowComments,
      'allowReactions': allowReactions,
      'ageMin': ageMin,
      'ageMax': ageMax,
    };
    if (groupId != null && groupId.isNotEmpty) {
      body['groupId'] = groupId;
    }

    final dynamic response = await _api.post('/api/posts', body: body);
    final Map<String, dynamic> data = _toMap(response);
    final FeedPost post = FeedPost.fromJson(_toMap(data['post']));
    final Map<String, dynamic> moderation = _toMap(data['moderation']);
    return (
      post: post,
      needsReview: moderation['needsReview'] == true,
      mediaModerationScore:
          (moderation['mediaModerationScore'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<FeedPost> getPost(String postId) async {
    final dynamic response = await _api.get('/api/posts/$postId');
    final Map<String, dynamic> data = _toMap(response);
    return FeedPost.fromJson(_toMap(data['post']));
  }

  Future<FeedPost> updatePost({
    required String postId,
    String? content,
    List<String>? topics,
    String? mood,
    List<String>? mediaUrls,
    String? audience,
    bool? allowComments,
    bool? allowReactions,
    int? ageMin,
    int? ageMax,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{};
    if (content != null) {
      body['content'] = content;
    }
    if (topics != null) {
      body['topics'] = topics;
    }
    if (mood != null) {
      body['mood'] = mood;
    }
    if (mediaUrls != null) {
      body['mediaUrls'] = mediaUrls;
    }
    if (audience != null) {
      body['audience'] = audience;
    }
    if (allowComments != null) {
      body['allowComments'] = allowComments;
    }
    if (allowReactions != null) {
      body['allowReactions'] = allowReactions;
    }
    if (ageMin != null) {
      body['ageMin'] = ageMin;
    }
    if (ageMax != null) {
      body['ageMax'] = ageMax;
    }

    final dynamic response = await _api.patch('/api/posts/$postId', body: body);
    final Map<String, dynamic> data = _toMap(response);
    return FeedPost.fromJson(_toMap(data['post']));
  }

  Future<void> deletePost(String postId) async {
    await _api.delete('/api/posts/$postId');
  }

  Future<PostLikeResult> toggleLike(
    String postId, {
    String reaction = 'heart',
  }) async {
    final dynamic response = await _api.post(
      '/api/posts/$postId/like',
      body: <String, dynamic>{'reaction': reaction},
    );
    return PostLikeResult.fromJson(_toMap(response));
  }

  Future<List<PostReactionUser>> reactionUsers(
    String postId, {
    String? reaction,
  }) async {
    final dynamic response = await _api.get(
      '/api/posts/$postId/reactions',
      query: <String, dynamic>{
        if (reaction != null && reaction.isNotEmpty) 'reaction': reaction,
      },
    );
    final List<dynamic> items =
        _toMap(response)['items'] as List<dynamic>? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(PostReactionUser.fromJson)
        .toList();
  }

  Future<bool> bookmarkPost(String postId) async {
    final dynamic response = await _api.post('/api/posts/$postId/bookmark');
    return _toMap(response)['bookmarked'] == true;
  }

  Future<bool> unbookmarkPost(String postId) async {
    final dynamic response = await _api.delete('/api/posts/$postId/bookmark');
    return _toMap(response)['bookmarked'] != true;
  }

  Future<FeedPage> myBookmarks({
    int limit = _defaultPageSize,
    String? before,
  }) async {
    final dynamic response = await _api.get(
      '/api/posts/bookmarks/me',
      query: <String, dynamic>{'limit': limit, 'before': before},
    );
    final Map<String, dynamic> data = _toMap(response);
    final List<FeedPost> items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FeedPost.fromJson)
        .toList();
    return FeedPage(
      items: items,
      nextBefore: data['nextBefore']?.toString(),
      hasMore: data['hasMore'] == true,
    );
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
