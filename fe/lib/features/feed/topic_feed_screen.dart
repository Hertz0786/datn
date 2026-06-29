import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/realtime_service.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/skeleton_views.dart';
import '../../shared/widgets/user_avatar.dart';
import '../feed/post_detail_screen.dart';

class TopicFeedScreen extends StatefulWidget {
  const TopicFeedScreen({
    super.key,
    required this.topic,
  });

  final String topic;

  @override
  State<TopicFeedScreen> createState() => _TopicFeedScreenState();
}

class _TopicFeedScreenState extends State<TopicFeedScreen> {
  static const int _pageSize = 20;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  List<FeedPost> _posts = <FeedPost>[];
  final ScrollController _scrollController = ScrollController();

  final Set<String> _pendingLikeIds = <String>{};
  final Set<String> _pendingBookmarkIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _scrollController.addListener(_onScroll);
    RealtimeService.instance.on('post:liked', _handlePostLiked);
    RealtimeService.instance.on('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.on('feed:changed', _handleFeedChanged);
  }

  @override
  void dispose() {
    RealtimeService.instance.off('post:liked', _handlePostLiked);
    RealtimeService.instance.off('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.off('feed:changed', _handleFeedChanged);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double extent = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (extent < 400) {
      _loadMore();
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _nextCursor = null;
    });
    try {
      final FeedPage page = await PostsApi.instance.feedByTopic(
        widget.topic,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load posts: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final FeedPage page = await PostsApi.instance.feedByTopic(
        widget.topic,
        limit: _pageSize,
        before: _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        final List<FeedPost> existing = List<FeedPost>.from(_posts);
        for (final FeedPost post in page.items) {
          if (!existing.any((p) => p.id == post.id)) {
            existing.add(post);
          }
        }
        _posts = existing;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _toggleLike(FeedPost post, {String reaction = 'heart'}) async {
    if (_pendingLikeIds.contains(post.id)) return;
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

    _pendingLikeIds.add(post.id);
    _replacePost(post.id, (p) => p.copyWith(
          likedByMe: nextLiked,
          myReaction: nextReaction,
          clearMyReaction: nextReaction == null,
          reactionCount: nextCount,
        ));

    try {
      final PostLikeResult result =
          await PostsApi.instance.toggleLike(post.id, reaction: reaction);
      _replacePost(result.postId, (p) => p.copyWith(
            likedByMe: result.liked,
            myReaction: result.reaction,
            clearMyReaction: result.reaction == null,
            reactionCount: result.reactionCount,
            reactions: result.reactions,
          ));
    } on ApiException {
      _replacePost(post.id, (p) => p.copyWith(
            likedByMe: post.isLikedByMe,
            myReaction: post.myReaction,
            reactionCount: post.reactionCount,
          ));
    } catch (_) {
      _replacePost(post.id, (p) => p.copyWith(
            likedByMe: post.isLikedByMe,
            myReaction: post.myReaction,
            reactionCount: post.reactionCount,
          ));
    } finally {
      _pendingLikeIds.remove(post.id);
    }
  }

  Future<void> _toggleBookmark(FeedPost post) async {
    if (_pendingBookmarkIds.contains(post.id)) return;
    final bool nextBookmarked = !post.bookmarkedByMe;
    _pendingBookmarkIds.add(post.id);
    _replacePost(post.id, (p) => p.copyWith(bookmarkedByMe: nextBookmarked));

    try {
      if (nextBookmarked) {
        await PostsApi.instance.bookmarkPost(post.id);
      } else {
        await PostsApi.instance.unbookmarkPost(post.id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nextBookmarked
              ? 'Saved to bookmarks.'
              : 'Removed from bookmarks.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      _replacePost(post.id, (p) => p.copyWith(bookmarkedByMe: post.bookmarkedByMe));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bookmark failed: $e')),
        );
      }
    } finally {
      _pendingBookmarkIds.remove(post.id);
    }
  }

  void _replacePost(String id, FeedPost Function(FeedPost) update) {
    if (!mounted) return;
    setState(() {
      _posts = _posts.map((p) => p.id == id ? update(p) : p).toList();
    });
  }

  void _handlePostLiked(dynamic payload) {
    if (payload is! Map) return;
    final String postId = (payload['postId'] ?? '').toString();
    if (postId.isEmpty) return;
    final int? count = (payload['reactionCount'] as num?)?.toInt();
    _replacePost(postId, (p) => p.copyWith(reactionCount: count));
  }

  void _handlePostCommentCount(dynamic payload) {
    if (payload is! Map) return;
    final String postId = (payload['postId'] ?? '').toString();
    final int? count = (payload['commentCount'] as num?)?.toInt();
    if (postId.isEmpty || count == null) return;
    _replacePost(postId, (p) => p.copyWith(commentCount: count));
  }

  void _handleFeedChanged(dynamic _) {
    _loadPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A3D7C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7A5CFF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.tag_rounded,
                color: Color(0xFF7A5CFF),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.topic,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A3D7C),
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPosts,
        child: _isLoading && _posts.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: SkeletonList(itemCount: 4),
                ),
              )
            : _posts.isEmpty
                ? _buildEmpty()
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: _buildItem,
                  ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: EmptyStateView(
        icon: Icons.tag_rounded,
        title: 'No posts for "${widget.topic}"',
        message: 'Be the first to share something with this topic!',
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
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
    return _TopicPostCard(
      post: post,
      onLike: (r) => _toggleLike(post, reaction: r),
      onBookmark: () => _toggleBookmark(post),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
          ),
        ).then((_) => _loadPosts());
      },
    );
  }
}

class _TopicPostCard extends StatelessWidget {
  const _TopicPostCard({
    required this.post,
    required this.onLike,
    required this.onBookmark,
    required this.onTap,
  });

  final FeedPost post;
  final void Function(String reaction) onLike;
  final VoidCallback onBookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String authorName = post.authorDisplayName.isEmpty
        ? post.authorUsername
        : post.authorDisplayName;
    final String avatarLabel =
        authorName.isEmpty ? '?' : authorName.substring(0, 1).toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                UserAvatar(
                  avatarUrl: post.authorAvatarUrl,
                  initials: avatarLabel,
                  radius: 18,
                  backgroundColor: const Color(0xFFFFC5E6),
                  lastActiveAt: post.authorLastActiveAt,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName.isEmpty ? 'Little Star' : authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                      Text(
                        '@${post.authorUsername}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9AA7C7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    post.bookmarkedByMe
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: post.bookmarkedByMe
                        ? const Color(0xFFFFA94D)
                        : const Color(0xFF7A8BBF),
                  ),
                  onPressed: onBookmark,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.content,
              style: const TextStyle(color: Color(0xFF2B4F84), height: 1.4),
            ),
            if (post.topics.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: post.topics
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF7FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A3D7C),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _LikeButton(post: post, onLike: onLike),
                const SizedBox(width: 10),
                _ActionChip(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '${post.commentCount}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.post, required this.onLike});

  final FeedPost post;
  final void Function(String reaction) onLike;

  @override
  Widget build(BuildContext context) {
    final bool liked = post.isLikedByMe;
    return GestureDetector(
      onTap: () => onLike('heart'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: liked
              ? Colors.pink.withValues(alpha: 0.12)
              : const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 16,
              color: liked ? Colors.pink : const Color(0xFF33B8FF),
            ),
            const SizedBox(width: 6),
            Text(
              '${post.reactionCount}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
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
