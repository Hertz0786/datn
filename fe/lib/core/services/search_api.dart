import '../../features/groups/group_info.dart';
import '../models/feed_post.dart';
import '../models/public_user.dart';
import '../models/search_results.dart';
import '../network/api_client.dart';

class SearchApi {
  SearchApi._();

  static final SearchApi instance = SearchApi._();

  final ApiClient _api = ApiClient.instance;

  Future<SearchResults> search({
    String? query,
    String type = 'all',
    String? topic,
    List<String> topics = const <String>[],
    int? age,
    int? ageMin,
    int? ageMax,
  }) async {
    final Map<String, dynamic> queryParams = <String, dynamic>{
      'q': query,
      'type': type,
      'topic': topic,
      'age': age,
      'ageMin': ageMin,
      'ageMax': ageMax,
    };
    if (topics.length == 1) {
      queryParams['topic'] = topics.first;
    } else if (topics.length > 1) {
      // The backend only filters by a single topic. Send the first one and let
      // the client filter the remaining topics in the result list.
      queryParams['topic'] = topics.first;
    }

    final dynamic response = await _api.get(
      '/api/search',
      query: queryParams,
    );

    final Map<String, dynamic> data = _toMap(response);

    final List<dynamic> usersRaw = data['users'] as List<dynamic>? ?? const [];
    final List<PublicUser> users = usersRaw
        .whereType<Map<String, dynamic>>()
        .map(PublicUser.fromJson)
        .toList();

    final List<GroupInfo> groups =
        (data['groups'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(GroupInfo.fromJson)
            .toList();

    final List<FeedPost> posts =
        (data['posts'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(FeedPost.fromJson)
            .toList();

    return SearchResults(users: users, groups: groups, posts: posts);
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return <String, dynamic>{};
  }
}
