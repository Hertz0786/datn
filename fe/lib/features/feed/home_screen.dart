import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/groups_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../core/utils/presence.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/media_preview_grid.dart';
import '../../shared/widgets/post_audience_badge.dart';
import '../../shared/widgets/report_sheet.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/skeleton_views.dart';
import '../../shared/widgets/user_avatar.dart';
import '../friends/friend_list_screen.dart';
import '../friends/friend_profile_screen.dart';
import '../groups/group_detail_screen.dart';
import '../groups/group_info.dart';
import '../groups/group_list_screen.dart';
import '../safety/community_rules_screen.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

enum _FeedScope { all, friends, public }

extension on _FeedScope {
  String get apiValue {
    switch (this) {
      case _FeedScope.all:
        return 'all';
      case _FeedScope.friends:
        return 'friends';
      case _FeedScope.public:
        return 'public';
    }
  }

  String get label {
    switch (this) {
      case _FeedScope.all:
        return 'For you';
      case _FeedScope.friends:
        return 'Friends';
      case _FeedScope.public:
        return 'Public';
    }
  }

  IconData get icon {
    switch (this) {
      case _FeedScope.all:
        return Icons.auto_awesome_rounded;
      case _FeedScope.friends:
        return Icons.group_rounded;
      case _FeedScope.public:
        return Icons.public_rounded;
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 50;
  static const double _loadMoreThreshold = 600;

  _FeedScope _scope = _FeedScope.all;

  bool _isPostsLoading = true;
  bool _isLoadingMorePosts = false;
  bool _hasMorePosts = true;
  String? _nextPostCursor;
  List<FeedPost> _posts = const <FeedPost>[];

  bool _isFriendsLoading = true;
  bool _isSummaryLoading = true;
  bool _isGroupsLoading = true;
  List<PublicUser> _friends = const <PublicUser>[];
  List<GroupInfo> _groups = const <GroupInfo>[];
  int _incomingFriendRequestCount = 0;

  final Set<String> _pendingLikePostIds = <String>{};
  final Set<String> _pendingBookmarkPostIds = <String>{};

  bool _showJumpToTop = false;

  Timer? _presenceRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadFriends();
    _loadSummary();
    _loadGroups();
    _listenRealtime();
    _scrollController.addListener(_onScroll);
    // Refresh friends + posts every minute so the green online dot
    // reflects the latest server state even if the user just sits on
    // the screen. We skip if the screen is not visible to be polite.
    _presenceRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) {
        return;
      }
      _loadFriends(showLoading: false);
      _loadPosts(reset: true);
    });
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    _presenceRefreshTimer = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    RealtimeService.instance.off('post:liked', _handlePostLiked);
    RealtimeService.instance.off('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.off('feed:changed', _handleFeedChanged);
    RealtimeService.instance.off(
      'notification:created',
      _handleNotificationCreated,
    );
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels >= 800 && !_showJumpToTop) {
      setState(() => _showJumpToTop = true);
    } else if (pos.pixels < 200 && _showJumpToTop) {
      setState(() => _showJumpToTop = false);
    }
    final double extent = pos.maxScrollExtent - pos.pixels;
    if (extent < _loadMoreThreshold) {
      _loadMorePosts();
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _listenRealtime() {
    RealtimeService.instance.on('post:liked', _handlePostLiked);
    RealtimeService.instance.on('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.on('feed:changed', _handleFeedChanged);
    RealtimeService.instance.on(
      'notification:created',
      _handleNotificationCreated,
    );
  }

  Future<void> _loadPosts({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isPostsLoading = true;
        _hasMorePosts = true;
        _nextPostCursor = null;
      });
    } else {
      setState(() => _isPostsLoading = true);
    }

    try {
      final FeedPage page = await PostsApi.instance.feed(
        limit: _pageSize,
        scope: _scope.apiValue,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _posts = page.items;
        _hasMorePosts = page.hasMore;
        _nextPostCursor = page.nextBefore;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load posts: $error')));
    } finally {
      if (mounted) {
        setState(() => _isPostsLoading = false);
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isPostsLoading ||
        _isLoadingMorePosts ||
        !_hasMorePosts ||
        _nextPostCursor == null) {
      return;
    }

    setState(() => _isLoadingMorePosts = true);
    try {
      final FeedPage page = await PostsApi.instance.feed(
        limit: _pageSize,
        before: _nextPostCursor,
        scope: _scope.apiValue,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final List<FeedPost> existing = List<FeedPost>.from(_posts);
        for (final FeedPost post in page.items) {
          if (!existing.any((item) => item.id == post.id)) {
            existing.add(post);
          }
        }
        _posts = existing;
        _hasMorePosts = page.hasMore;
        _nextPostCursor = page.nextBefore;
      });
    } on ApiException catch (_) {
      // silent
    } catch (_) {
      // silent
    } finally {
      if (mounted) {
        setState(() => _isLoadingMorePosts = false);
      }
    }
  }

  Future<void> _changeScope(_FeedScope newScope) async {
    if (newScope == _scope) {
      return;
    }
    setState(() => _scope = newScope);
    _scrollToTop();
    await _loadPosts();
  }

  Future<void> _loadFriends({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isFriendsLoading = true);
    }
    try {
      final FriendsPage page = await FriendsApi.instance.listFriends();
      if (!mounted) {
        return;
      }
      setState(() => _friends = page.items);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load friends: $error')));
    } finally {
      if (mounted && showLoading) {
        setState(() => _isFriendsLoading = false);
      }
    }
  }

  Future<void> _loadSummary({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isSummaryLoading = true);
    }
    try {
      final FriendRequestsPage page = await FriendsApi.instance
          .incomingRequests();
      if (!mounted) {
        return;
      }
      setState(() => _incomingFriendRequestCount = page.items.length);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load summary: $error')));
    } finally {
      if (mounted && showLoading) {
        setState(() => _isSummaryLoading = false);
      }
    }
  }

  Future<void> _loadGroups({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isGroupsLoading = true);
    }
    try {
      final GroupsPage groupsPage = await GroupsApi.instance.listGroups();
      if (!mounted) {
        return;
      }
      setState(() => _groups = groupsPage.items);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load groups: $error')));
    } finally {
      if (mounted && showLoading) {
        setState(() => _isGroupsLoading = false);
      }
    }
  }

  Future<void> _refreshHome() async {
    await Future.wait([
      _loadPosts(),
      _loadFriends(),
      _loadSummary(),
      _loadGroups(),
    ]);
  }

  String get _displayName {
    final dynamic rawName = AuthSession.instance.user?['displayName'];
    final dynamic rawUsername = AuthSession.instance.user?['username'];
    final String displayName = rawName == null ? '' : rawName.toString().trim();
    final String username = rawUsername == null
        ? ''
        : rawUsername.toString().trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    if (username.isNotEmpty) {
      return username;
    }
    return 'Little Star';
  }

  String get _homeSummaryText {
    if (_isSummaryLoading || _isPostsLoading || _isFriendsLoading) {
      return 'Loading your latest updates...';
    }
    final int postCount = _posts.length;
    final int friendCount = _friends.length;
    final int requestCount = _incomingFriendRequestCount;
    final String postWord = postCount == 1 ? 'post' : 'posts';
    final String friendWord = friendCount == 1 ? 'friend' : 'friends';
    final String requestWord = requestCount == 1 ? 'request' : 'requests';
    return 'Today you have $postCount fun $postWord, $friendCount $friendWord, and $requestCount friend $requestWord.';
  }

  String _friendDisplayName(PublicUser friend) {
    try {
      if (friend.displayName.trim().isNotEmpty) {
        return friend.displayName.trim();
      }
      if (friend.username.trim().isNotEmpty) {
        return friend.username.trim();
      }
    } catch (_) {}
    return 'Friend';
  }

  String _friendTopic(PublicUser friend) {
    try {
      final List<String> topics = friend.favoriteTopics;
      if (topics.isNotEmpty) {
        return topics.first;
      }
    } catch (_) {}
    return 'Music';
  }

  String _friendInitials(PublicUser friend) {
    final String source = _friendDisplayName(friend);
    final List<String> parts = source
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length <= 1) {
      return source.length >= 2
          ? source.substring(0, 2).toUpperCase()
          : source.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  Future<void> _togglePostLike(
    FeedPost post, {
    String reaction = 'heart',
  }) async {
    if (!post.allowReactions) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reactions are locked for this post.')),
        );
      }
      return;
    }
    if (_pendingLikePostIds.contains(post.id)) {
      return;
    }
    final String currentReaction = post.myReaction ?? '';
    final bool tappingSame =
        currentReaction.isNotEmpty && currentReaction == reaction;
    final bool nextLiked = !tappingSame;
    final String? nextReaction = tappingSame ? null : reaction;
    final int nextCount = !tappingSame
        ? (currentReaction.isEmpty
              ? post.reactionCount + 1
              : post.reactionCount)
        : (post.reactionCount > 0 ? post.reactionCount - 1 : 0);

    _pendingLikePostIds.add(post.id);
    _replacePost(
      post.id,
      (item) => item.copyWith(
        likedByMe: nextLiked,
        myReaction: nextReaction,
        clearMyReaction: nextReaction == null,
        reactionCount: nextCount,
      ),
    );

    try {
      final PostLikeResult result = await PostsApi.instance.toggleLike(
        post.id,
        reaction: reaction,
      );
      _replacePost(
        result.postId,
        (item) => item.copyWith(
          likedByMe: result.liked,
          myReaction: result.reaction,
          clearMyReaction: result.reaction == null,
          reactionCount: result.reactionCount,
          reactions: result.reactions,
        ),
      );
    } on ApiException catch (error) {
      _replacePost(
        post.id,
        (item) => item.copyWith(
          likedByMe: post.isLikedByMe,
          myReaction: post.myReaction,
          reactionCount: post.reactionCount,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      _replacePost(
        post.id,
        (item) => item.copyWith(
          likedByMe: post.isLikedByMe,
          myReaction: post.myReaction,
          reactionCount: post.reactionCount,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Like failed: $error')));
      }
    } finally {
      _pendingLikePostIds.remove(post.id);
    }
  }

  Future<void> _togglePostBookmark(FeedPost post) async {
    if (_pendingBookmarkPostIds.contains(post.id)) {
      return;
    }
    final bool nextBookmarked = !post.bookmarkedByMe;
    _pendingBookmarkPostIds.add(post.id);
    _replacePost(
      post.id,
      (item) => item.copyWith(bookmarkedByMe: nextBookmarked),
    );

    try {
      if (nextBookmarked) {
        await PostsApi.instance.bookmarkPost(post.id);
      } else {
        await PostsApi.instance.unbookmarkPost(post.id);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextBookmarked ? 'Saved to bookmarks.' : 'Removed from bookmarks.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      _replacePost(
        post.id,
        (item) => item.copyWith(bookmarkedByMe: post.bookmarkedByMe),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Bookmark failed: $error')));
      }
    } finally {
      _pendingBookmarkPostIds.remove(post.id);
    }
  }

  void _replacePost(String postId, FeedPost Function(FeedPost post) update) {
    if (!mounted) {
      return;
    }
    setState(() {
      _posts = _posts
          .map((post) => post.id == postId ? update(post) : post)
          .toList();
    });
  }

  void _handlePostLiked(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final String postId = (payload['postId'] ?? '').toString();
    if (postId.isEmpty) {
      return;
    }
    final String currentUserId = (AuthSession.instance.user?['id'] ?? '')
        .toString();
    final String eventUserId = (payload['userId'] ?? '').toString();
    final int? reactionCount = (payload['reactionCount'] as num?)?.toInt();
    final bool? likedByCurrentUser = eventUserId == currentUserId
        ? payload['liked'] == true
        : null;
    _replacePost(
      postId,
      (post) => post.copyWith(
        reactionCount: reactionCount,
        likedByMe: likedByCurrentUser,
      ),
    );
  }

  void _handlePostCommentCount(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final String postId = (payload['postId'] ?? '').toString();
    final int? commentCount = (payload['commentCount'] as num?)?.toInt();
    if (postId.isEmpty || commentCount == null) {
      return;
    }
    _replacePost(postId, (post) => post.copyWith(commentCount: commentCount));
  }

  void _handleFeedChanged(dynamic _) {
    _loadPosts();
  }

  void _handleNotificationCreated(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final dynamic rawNotification = payload['notification'];
    if (rawNotification is! Map) {
      _loadSummary(showLoading: false);
      return;
    }
    final String type = (rawNotification['type'] ?? '').toString();
    if (type == 'FRIEND_REQUEST_RECEIVED') {
      setState(() => _incomingFriendRequestCount += 1);
      return;
    }
    if (type == 'FRIEND_REQUEST_ACCEPTED') {
      _loadFriends(showLoading: false);
      _loadSummary(showLoading: false);
    }
  }

  void _openPost(FeedPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      ),
    ).then((_) => _loadPosts());
  }

  void _openPostAuthor(FeedPost post) {
    final String authorId = post.authorId.trim();
    if (authorId.isEmpty) {
      return;
    }
    final String name = post.authorDisplayName.trim().isNotEmpty
        ? post.authorDisplayName.trim()
        : post.authorUsername.trim();
    final String initials = name.isEmpty
        ? '?'
        : name.substring(0, 1).toUpperCase();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: authorId,
          name: name.isEmpty ? 'Friend' : name,
          age: 0,
          favoriteTopic: 'Music',
          avatarLabel: initials,
          avatarUrl: post.authorAvatarUrl,
        ),
      ),
    );
  }

  Future<void> _reportPost(FeedPost post) async {
    final bool submitted = await showReportSheet(
      context: context,
      targetType: 'POST',
      targetId: post.id,
      title: 'Report this post',
      description: 'Help our moderators keep the community safe.',
    );
    if (!submitted || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanks! We will review it.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF33B8FF).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFF33B8FF)),
            ),
            const SizedBox(width: 12),
            const Text(
              'Kiddo Social',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A3D7C),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CommunityRulesScreen()),
              );
            },
            icon: const Icon(Icons.shield_rounded),
            color: const Color(0xFF1A3D7C),
          ),
        ],
      ),
      floatingActionButton: _showJumpToTop
          ? FloatingActionButton.small(
              heroTag: 'home-jump-top',
              onPressed: _scrollToTop,
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              child: const Icon(Icons.keyboard_arrow_up_rounded),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _refreshHome,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeroCard()),
            SliverToBoxAdapter(child: _buildScopeTabs()),
            SliverToBoxAdapter(child: _buildNewPostEntry()),
            SliverToBoxAdapter(child: _buildFriendsRow()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: SectionHeader(
                  title: _scope == _FeedScope.friends
                      ? 'Friend posts'
                      : _scope == _FeedScope.public
                      ? 'Public posts'
                      : 'New posts',
                  actionText: 'Post',
                  onAction: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreatePostScreen(),
                      ),
                    ).then((_) => _loadPosts());
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            _buildPostsSliver(),
            SliverToBoxAdapter(child: _buildGroupsBlock()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE59E), Color(0xFFFFC5E6)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi, $_displayName!',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF7A2E5A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _homeSummaryText,
                    style: const TextStyle(color: Color(0xFF7A2E5A)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_nature, color: Color(0xFF7A2E5A)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScopeTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final _FeedScope option in _FeedScope.values)
              Expanded(
                child: _ScopeTab(
                  scope: option,
                  isActive: _scope == option,
                  onTap: () => _changeScope(option),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewPostEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreatePostScreen()),
          ).then((_) => _loadPosts());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFFFC5E6),
                child: Icon(
                  Icons.edit_rounded,
                  color: Color(0xFF7A2E5A),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "What's on your mind today, $_displayName?",
                  style: const TextStyle(
                    color: Color(0xFF7A8BBF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF33B8FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Share',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Friends',
            actionText: 'See all',
            onAction: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendListScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          if (_isFriendsLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LoadingStateView(title: 'Loading friends...'),
            )
          else if (_friends.isEmpty)
            const EmptyStateView(
              icon: Icons.group_rounded,
              title: 'No friends yet',
              message: 'Invite a friend to start chatting together.',
            )
          else
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _friends.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final PublicUser friend = _friends[index];
                  final String title = _friendDisplayName(friend);
                  final String topic = _friendTopic(friend);
                  final String initials = _friendInitials(friend);
                  final bool isOnline = isUserOnline(friend.lastActiveAt);
                  final String presenceLabel = isOnline
                      ? 'Online'
                      : formatOfflineSince(friend.lastActiveAt);
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FriendProfileScreen(
                            userId: friend.id,
                            name: title,
                            age: friend.age,
                            favoriteTopic: topic,
                            avatarLabel: initials,
                            avatarColor: const Color(0xFFBEEAFF),
                            avatarUrl: friend.avatarUrl,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(30),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isOnline
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFD7E7FF),
                              width: 2,
                            ),
                          ),
                          child: UserAvatar(
                            avatarUrl: friend.avatarUrl,
                            initials: initials,
                            radius: 28,
                            backgroundColor: const Color(0xFFBEEAFF),
                            lastActiveAt: friend.lastActiveAt,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 72,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 86,
                          child: Text(
                            presenceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isOnline
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF9AA7C7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPostsSliver() {
    if (_isPostsLoading && _posts.isEmpty) {
      return const SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(child: SkeletonList(itemCount: 4)),
      );
    }
    if (_posts.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(
          child: EmptyStateView(
            icon: _scope == _FeedScope.friends
                ? Icons.group_outlined
                : _scope == _FeedScope.public
                ? Icons.public_off_rounded
                : Icons.photo_library_outlined,
            title: _scope == _FeedScope.friends
                ? 'No friend posts yet'
                : _scope == _FeedScope.public
                ? 'No public posts yet'
                : 'No posts yet',
            message: _scope == _FeedScope.friends
                ? 'Add more friends to see their posts here.'
                : 'Be the first to share something fun!',
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _posts.length + (_isLoadingMorePosts ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final FeedPost post = _posts[index];
          return _PostCard(
            post: post,
            isLikePending: _pendingLikePostIds.contains(post.id),
            isBookmarkPending: _pendingBookmarkPostIds.contains(post.id),
            onLike: (reaction) => _togglePostLike(post, reaction: reaction),
            onBookmark: () => _togglePostBookmark(post),
            onReport: () => _reportPost(post),
            onTap: () => _openPost(post),
            onAuthorTap: () => _openPostAuthor(post),
          );
        },
      ),
    );
  }

  Widget _buildGroupsBlock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_hasMorePosts && _posts.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  'You are all caught up.',
                  style: TextStyle(
                    color: Color(0xFF9AA7C7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          SectionHeader(
            title: 'Fun groups',
            actionText: 'See more',
            onAction: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupListScreen()),
              ).then((_) => _loadGroups(showLoading: false));
            },
          ),
          const SizedBox(height: 10),
          if (_isGroupsLoading)
            const LoadingStateView(title: 'Loading groups...')
          else if (_groups.isEmpty)
            const EmptyStateView(
              icon: Icons.groups_rounded,
              title: 'No groups yet',
              message: 'Join a group to explore fun activities.',
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _groups.take(8).map((group) {
                return _GroupChip(
                  label: group.topic,
                  color: group.color,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupDetailScreen(group: group),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    required this.scope,
    required this.isActive,
    required this.onTap,
  });

  final _FeedScope scope;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF33B8FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              scope.icon,
              size: 16,
              color: isActive ? Colors.white : const Color(0xFF7A8BBF),
            ),
            const SizedBox(width: 6),
            Text(
              scope.label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isActive ? Colors.white : const Color(0xFF1A3D7C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.isLikePending,
    required this.onLike,
    required this.onTap,
    required this.onAuthorTap,
    required this.onBookmark,
    required this.onReport,
    required this.isBookmarkPending,
  });

  final FeedPost post;
  final bool isLikePending;
  final bool isBookmarkPending;
  final void Function(String reaction) onLike;
  final VoidCallback onBookmark;
  final VoidCallback onReport;
  final VoidCallback onTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    String displayName = '';
    String username = '';
    try {
      displayName = post.authorDisplayName.trim();
      username = post.authorUsername.trim();
    } catch (_) {}
    final String authorName = displayName.isEmpty ? username : displayName;
    final String avatarLabel = authorName.isEmpty
        ? '?'
        : authorName.substring(0, 1).toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAuthorTap,
                  child: UserAvatar(
                    avatarUrl: post.authorAvatarUrl,
                    initials: avatarLabel,
                    radius: 18,
                    backgroundColor: const Color(0xFFFFC5E6),
                    lastActiveAt: post.authorLastActiveAt,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onAuthorTap,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          authorName.isEmpty ? 'Little Star' : authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A3D7C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateTimeFormatter.format(post.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9AA7C7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: PostAudienceBadge.forPost(post, compact: true),
                ),
                IconButton(
                  tooltip: post.bookmarkedByMe
                      ? 'Remove bookmark'
                      : 'Save post',
                  onPressed: isBookmarkPending ? null : onBookmark,
                  icon: isBookmarkPending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          post.bookmarkedByMe
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: post.bookmarkedByMe
                              ? const Color(0xFFFFA94D)
                              : const Color(0xFF7A8BBF),
                        ),
                ),
                IconButton(
                  tooltip: 'Report',
                  onPressed: onReport,
                  icon: const Icon(
                    Icons.flag_outlined,
                    color: Color(0xFF7A8BBF),
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.content,
              style: const TextStyle(color: Color(0xFF2B4F84), height: 1.4),
            ),
            if (post.mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              MediaPreviewGrid(urls: post.mediaUrls),
            ],
            if (post.topics.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: post.topics
                    .map((topic) => _TopicPill(label: topic))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            if (post.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReactionBreakdown(reactions: post.reactions),
              ),
            Row(
              children: [
                if (post.allowReactions)
                  _ReactionButton(
                    post: post,
                    isLikePending: isLikePending,
                    onPick: onLike,
                  )
                else
                  const _ActionChip(
                    icon: Icons.lock_outline_rounded,
                    label: 'Reactions off',
                  ),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: post.allowComments
                      ? Icons.chat_bubble
                      : Icons.lock_outline_rounded,
                  label: post.allowComments
                      ? '${post.commentCount} comments'
                      : 'Comments off',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF7FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A3D7C),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF33B8FF)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.post,
    required this.isLikePending,
    required this.onPick,
  });
  final FeedPost post;
  final bool isLikePending;
  final void Function(String reaction) onPick;

  Future<void> _showPicker(BuildContext context) async {
    final String? reaction = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'React with',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A3D7C),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: kReactionCatalog.entries.map((entry) {
                  final bool active = post.myReaction == entry.key;
                  return GestureDetector(
                    onTap: () => Navigator.pop(context, entry.key),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: active
                            ? entry.value.color.withValues(alpha: 0.18)
                            : const Color(0xFFF5F8FF),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        entry.value.icon,
                        color: entry.value.color,
                        size: 28,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (reaction == null) {
      return;
    }
    onPick(reaction);
  }

  @override
  Widget build(BuildContext context) {
    final String activeKey =
        post.myReaction != null && kReactionCatalog.containsKey(post.myReaction)
        ? post.myReaction!
        : 'heart';
    final ReactionOption active = kReactionCatalog[activeKey]!;
    final bool isActive = post.isLikedByMe;

    return InkWell(
      onTap: isLikePending ? null : () => onPick(activeKey),
      onLongPress: isLikePending ? null : () => _showPicker(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? active.color.withValues(alpha: 0.12)
              : const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            if (isLikePending)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                isActive ? active.icon : Icons.favorite_border_rounded,
                size: 16,
                color: isActive ? active.color : const Color(0xFF33B8FF),
              ),
            const SizedBox(width: 6),
            Text(
              isActive
                  ? '${activeKey[0].toUpperCase()}${activeKey.substring(1)} ${post.reactionCount}'
                  : '${post.reactionCount} likes',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionBreakdown extends StatelessWidget {
  const _ReactionBreakdown({required this.reactions});
  final Map<String, int> reactions;
  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, int>> entries =
        reactions.entries.where((entry) => entry.value > 0).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((entry) {
        final ReactionOption? option = kReactionCatalog[entry.key];
        if (option == null) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: option.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(option.icon, size: 12, color: option.color),
              const SizedBox(width: 4),
              Text(
                '${entry.value}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: option.color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
