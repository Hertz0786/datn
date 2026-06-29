import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/feed_post.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/posts_api.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/post_audience_badge.dart';
import '../../shared/widgets/skeleton_views.dart';
import '../../shared/widgets/user_avatar.dart';
import '../friends/friend_profile_screen.dart';
import 'post_detail_screen.dart';

/// Full paginated list of a specific user's posts. Opened from
/// the "See all" link in [FriendProfileScreen].
class FriendPostsScreen extends StatefulWidget {
  const FriendPostsScreen({
    super.key,
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  @override
  State<FriendPostsScreen> createState() => _FriendPostsScreenState();
}

class _FriendPostsScreenState extends State<FriendPostsScreen> {
  final ScrollController _scrollController = ScrollController();

  static const int _pageSize = 20;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _forbidden = false;
  String? _nextCursor;
  String? _loadError;
  List<FeedPost> _posts = const <FeedPost>[];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final double extent =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (extent < 300) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _forbidden = false;
      _loadError = null;
      _nextCursor = null;
    });

    try {
      final FeedPage page = await PostsApi.instance.userPosts(
        widget.userId,
        limit: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _posts = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.statusCode == 401 || error.statusCode == 403) {
        setState(() {
          _forbidden = true;
          _posts = const <FeedPost>[];
        });
      } else {
        setState(() => _loadError = error.message);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadError = 'Failed to load posts: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final FeedPage page = await PostsApi.instance.userPosts(
        widget.userId,
        limit: _pageSize,
        before: _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final List<FeedPost> next = List<FeedPost>.from(_posts);
        for (final FeedPost post in page.items) {
          if (!next.any((item) => item.id == post.id)) {
            next.add(post);
          }
        }
        _posts = next;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } catch (_) {
      // Silent: leave pagination state unchanged so user can scroll again.
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _openPost(FeedPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      ),
    );
  }

  void _openAuthor(FeedPost post) {
    final String authorId = post.authorId.trim();
    if (authorId.isEmpty) {
      return;
    }
    final String currentUserId =
        (AuthSession.instance.user?['id'] ?? '').toString().trim();
    if (authorId == currentUserId) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      return;
    }
    final String name = post.authorDisplayName.trim().isNotEmpty
        ? post.authorDisplayName.trim()
        : post.authorUsername.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PushedScreenShell(
          child: FriendProfileScreen(
            userId: authorId,
            name: name.isEmpty ? 'Friend' : name,
            age: 0,
            favoriteTopic: 'Music',
            avatarLabel: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
            avatarUrl: post.authorAvatarUrl,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title = widget.displayName.trim().isEmpty
        ? 'Posts'
        : "${widget.displayName}'s posts";

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: const [
          SizedBox(height: 80),
          SkeletonList(itemCount: 3, compact: true),
        ],
      );
    }

    if (_forbidden) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyStateView(
            icon: Icons.lock_outline_rounded,
            title: "Can't view posts",
            message:
                "You can only see this friend's posts once you're friends.",
            actionLabel: 'Refresh',
            onAction: _load,
          ),
        ],
      );
    }

    if (_loadError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyStateView(
            icon: Icons.error_outline_rounded,
            title: 'Something went wrong',
            message: _loadError!,
            actionLabel: 'Try again',
            onAction: _load,
          ),
        ],
      );
    }

    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          const EmptyStateView(
            icon: Icons.edit_note_rounded,
            title: 'No posts yet',
            message: 'When your friend shares something, it will appear here.',
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _posts.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        final FeedPost post = _posts[index];
        return _PostTile(
          post: post,
          onTap: () => _openPost(post),
          onAuthorTap: () => _openAuthor(post),
        );
      },
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({
    required this.post,
    required this.onTap,
    required this.onAuthorTap,
  });

  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final String content = post.content.isEmpty ? '(no text)' : post.content;
    final String preview = content.length > 160
        ? '${content.substring(0, 160)}...'
        : content;
    final String timeText = DateTimeFormatter.relative(post.createdAt);
    final String authorName = post.authorDisplayName.isNotEmpty
        ? post.authorDisplayName
        : '@${post.authorUsername}';
    final String initials = authorName.isNotEmpty
        ? authorName.substring(0, 1).toUpperCase()
        : '?';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: onAuthorTap,
              child: UserAvatar(
                initials: initials,
                avatarUrl: post.authorAvatarUrl,
                radius: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          authorName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: Color(0xFF1A3D7C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeText,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7C8DA6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    preview,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: Color(0xFF334155),
                    ),
                  ),
                  if (post.audience.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    PostAudienceBadge(audience: post.audience),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        size: 14,
                        color: Color(0xFF7C8DA6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.reactionCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7C8DA6),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 14,
                        color: Color(0xFF7C8DA6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${post.commentCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7C8DA6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}