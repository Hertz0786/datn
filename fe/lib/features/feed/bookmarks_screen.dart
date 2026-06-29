import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/feed_post.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/posts_api.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/post_audience_badge.dart';
import '../../shared/widgets/skeleton_views.dart';
import '../../shared/widgets/user_avatar.dart';
import '../friends/friend_profile_screen.dart';
import 'post_detail_screen.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
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

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _hasMore = true;
        _nextCursor = null;
      });
    }

    try {
      final FeedPage page = await PostsApi.instance.myBookmarks();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load bookmarks: $error')),
      );
    } finally {
      if (mounted && showLoading) {
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
      final FeedPage page = await PostsApi.instance.myBookmarks(
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
      // Silent failure for background pagination.
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
    ).then((_) => _load(showLoading: false));
  }

  void _openPostAuthor(FeedPost post) {
    final String authorId = post.authorId.trim();
    if (authorId.isEmpty) {
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

  Future<void> _removeBookmark(FeedPost post) async {
    try {
      final bool removed = await PostsApi.instance.unbookmarkPost(post.id);
      if (!mounted) {
        return;
      }
      if (removed) {
        setState(() {
          _posts = _posts.where((p) => p.id != post.id).toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Removed "${_shortTitle(post.content)}"')),
        );
      }
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
      ).showSnackBar(SnackBar(content: Text('Unbookmark failed: $error')));
    }
  }

  String _shortTitle(String content) {
    if (content.isEmpty) return 'bookmark';
    final String trimmed = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    return trimmed.length > 30 ? '${trimmed.substring(0, 30)}...' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'Bookmarks',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: const [
                  SizedBox(height: 80),
                  SkeletonList(itemCount: 3, compact: true),
                ],
              )
            : _posts.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyStateView(
                    icon: Icons.bookmark_border_rounded,
                    title: 'No bookmarks yet',
                    message: 'Tap the bookmark icon on a post to save it here.',
                  ),
                ],
              )
            : ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == _posts.length) {
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
                  return _BookmarkTile(
                    post: post,
                    onTap: () => _openPost(post),
                    onAuthorTap: () => _openPostAuthor(post),
                    onRemove: () => _removeBookmark(post),
                  );
                },
              ),
      ),
    );
  }
}

class _BookmarkTile extends StatelessWidget {
  const _BookmarkTile({
    required this.post,
    required this.onTap,
    required this.onAuthorTap,
    required this.onRemove,
  });

  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback onAuthorTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String authorName = post.authorDisplayName.isNotEmpty
        ? post.authorDisplayName
        : post.authorUsername;
    final String label = authorName.isNotEmpty
        ? authorName.substring(0, 1).toUpperCase()
        : '?';

    return Dismissible(
      key: ValueKey<String>('bookmark:${post.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE0E0),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_remove_rounded, color: Color(0xFFD04545)),
            SizedBox(width: 6),
            Text(
              'Remove',
              style: TextStyle(
                color: Color(0xFFD04545),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final bool? confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove bookmark?'),
            content: const Text(
              'This post will be removed from your bookmarks.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        return confirm == true;
      },
      onDismissed: (_) => onRemove(),
      child: InkWell(
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
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAuthorTap,
                child: UserAvatar(
                  avatarUrl: post.authorAvatarUrl,
                  initials: label,
                  radius: 22,
                  backgroundColor: const Color(0xFFFFE59E),
                  lastActiveAt: post.authorLastActiveAt,
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
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onAuthorTap,
                            child: Text(
                              authorName.isEmpty ? 'Little Star' : authorName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A3D7C),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
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
                    const SizedBox(height: 4),
                    Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF2B4F84)),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        PostAudienceBadge.forPost(post, compact: true),
                        const SizedBox(width: 8),
                        Icon(
                          post.allowReactions
                              ? Icons.bookmark_rounded
                              : Icons.lock_outline_rounded,
                          size: 14,
                          color: post.allowReactions
                              ? const Color(0xFFFFA94D)
                              : const Color(0xFF7A8BBF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          post.allowReactions
                              ? '${post.reactionCount} likes'
                              : 'reactions off',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7A8BBF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          post.allowComments
                              ? '${post.commentCount} comments'
                              : 'comments off',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7A8BBF),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove bookmark',
                onPressed: () async {
                  final bool? confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Remove bookmark?'),
                      content: const Text(
                        'This post will be removed from your bookmarks.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    onRemove();
                  }
                },
                icon: const Icon(
                  Icons.bookmark_remove_rounded,
                  color: Color(0xFFD04545),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
