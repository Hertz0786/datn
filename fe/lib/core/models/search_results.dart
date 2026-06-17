import '../../features/groups/group_info.dart';
import 'feed_post.dart';
import 'public_user.dart';

class SearchResults {
  const SearchResults({
    required this.users,
    required this.groups,
    required this.posts,
  });

  final List<PublicUser> users;
  final List<GroupInfo> groups;
  final List<FeedPost> posts;
}
