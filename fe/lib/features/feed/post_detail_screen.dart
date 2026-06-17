import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/comment_item.dart';
import '../../core/models/feed_post.dart';
import '../../core/models/media_asset.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/comments_api.dart';
import '../../core/services/media_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../app/app_shell_navigator.dart';
import '../../shared/widgets/media_preview_grid.dart';
import '../../shared/widgets/post_audience_badge.dart';
import '../../shared/widgets/report_sheet.dart';
import '../../shared/widgets/user_avatar.dart';
import '../friends/friend_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, this.postId, this.initialPost});

  final String? postId;
  final FeedPost? initialPost;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedCommentMedia = <XFile>[];

  bool _isLoading = false;
  bool _isLikePending = false;
  bool _isBookmarkPending = false;
  bool _isCommentsLoading = false;
  bool _isSendingComment = false;

  FeedPost? _post;
  List<CommentItem> _comments = const <CommentItem>[];
  final Set<String> _pendingCommentReactionIds = <String>{};

  String? _replyTargetCommentId;
  String? _replyTargetAuthor;

  String? get _effectivePostId {
    final String? id = widget.postId ?? widget.initialPost?.id ?? _post?.id;
    if (id == null || id.isEmpty) {
      return null;
    }
    return id;
  }

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _loadPost();
    _loadComments();
    _listenRealtime();
  }

  @override
  void dispose() {
    final String? postId = _effectivePostId;
    if (postId != null) {
      RealtimeService.instance.emit('post:leave', postId);
    }
    RealtimeService.instance.off('post:liked', _handlePostLiked);
    RealtimeService.instance.off('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.off('comment:created', _handleCommentChanged);
    RealtimeService.instance.off('comment:updated', _handleCommentChanged);
    RealtimeService.instance.off('comment:deleted', _handleCommentChanged);
    RealtimeService.instance.off('comment:liked', _handleCommentLiked);
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _listenRealtime() {
    final String? postId = _effectivePostId;
    if (postId != null) {
      RealtimeService.instance.emit('post:join', postId);
    }
    RealtimeService.instance.on('post:liked', _handlePostLiked);
    RealtimeService.instance.on('post:comment_count', _handlePostCommentCount);
    RealtimeService.instance.on('comment:created', _handleCommentChanged);
    RealtimeService.instance.on('comment:updated', _handleCommentChanged);
    RealtimeService.instance.on('comment:deleted', _handleCommentChanged);
    RealtimeService.instance.on('comment:liked', _handleCommentLiked);
  }

  Future<void> _loadPost() async {
    final String? postId = _effectivePostId;
    if (postId == null) {
      return;
    }

    if (_post == null) {
      setState(() => _isLoading = true);
    }

    try {
      final FeedPost post = await PostsApi.instance.getPost(postId);
      if (!mounted) {
        return;
      }
      setState(() => _post = post);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadComments() async {
    final String? postId = _effectivePostId;
    if (postId == null) {
      return;
    }

    setState(() => _isCommentsLoading = true);

    try {
      final List<CommentItem> items = await CommentsApi.instance.listByPost(
        postId,
      );
      if (!mounted) {
        return;
      }
      setState(() => _comments = items);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isCommentsLoading = false);
      }
    }
  }

  Future<void> _sendComment() async {
    final String message = _commentController.text.trim();
    if ((message.isEmpty && _pickedCommentMedia.isEmpty) || _isSendingComment) {
      return;
    }
    if (_post?.allowComments == false) {
      _showCommentsLockedMessage();
      return;
    }

    final String? postId = _effectivePostId;
    if (postId == null) {
      return;
    }

    setState(() => _isSendingComment = true);

    try {
      final List<MediaAsset> uploaded = <MediaAsset>[];
      for (final XFile file in _pickedCommentMedia) {
        uploaded.add(await MediaApi.instance.upload(filePath: file.path));
      }
      final List<String> mediaUrls = uploaded
          .map((m) => m.url)
          .where((u) => u.isNotEmpty)
          .toList();

      if (_replyTargetCommentId != null) {
        await CommentsApi.instance.createReply(
          commentId: _replyTargetCommentId!,
          content: message,
          mediaUrls: mediaUrls,
        );
      } else {
        await CommentsApi.instance.createComment(
          postId: postId,
          content: message,
          mediaUrls: mediaUrls,
        );
      }

      for (final MediaAsset m in uploaded) {
        await MediaApi.instance.updateSource(
          mediaId: m.id,
          sourceType: 'COMMENT',
          sourceId: postId,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _commentController.clear();
        _pickedCommentMedia.clear();
        _replyTargetCommentId = null;
        _replyTargetAuthor = null;
      });
      _commentFocus.unfocus();
      await _loadComments();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSendingComment = false);
      }
    }
  }

  Future<void> _pickCommentMedia({required bool video}) async {
    if (_pickedCommentMedia.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can attach up to 3 files per comment.'),
        ),
      );
      return;
    }

    final XFile? file = video
        ? await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 2),
          )
        : await _picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 82,
          );
    if (file == null) {
      return;
    }
    setState(() => _pickedCommentMedia.add(file));
  }

  Future<void> _reactToPost(String reaction) async {
    final FeedPost? post = _post;
    if (post == null || _isLikePending) {
      return;
    }
    if (!post.allowReactions) {
      _showError('Reactions are locked for this post.');
      return;
    }

    final String? currentReaction = post.myReaction;
    final bool removingCurrentReaction =
        post.isLikedByMe && currentReaction == reaction;
    final String? nextReaction = removingCurrentReaction ? null : reaction;
    final bool nextLiked = nextReaction != null;
    final int nextCount = removingCurrentReaction
        ? (post.reactionCount > 0 ? post.reactionCount - 1 : 0)
        : currentReaction == null
        ? post.reactionCount + 1
        : post.reactionCount;

    setState(() {
      _isLikePending = true;
      _post = post.copyWith(
        likedByMe: nextLiked,
        myReaction: nextReaction,
        clearMyReaction: nextReaction == null,
        reactionCount: nextCount,
        reactions: _optimisticReactions(post, nextReaction),
      );
    });

    try {
      final PostLikeResult result = await PostsApi.instance.toggleLike(
        post.id,
        reaction: reaction,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _post = _post?.copyWith(
          likedByMe: result.liked,
          myReaction: result.reaction,
          clearMyReaction: result.reaction == null,
          reactionCount: result.reactionCount,
          reactions: result.reactions,
        );
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _post = post);
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _post = post);
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isLikePending = false);
      }
    }
  }

  Map<String, int> _optimisticReactions(FeedPost post, String? nextReaction) {
    final Map<String, int> reactions = Map<String, int>.from(post.reactions);
    final String? currentReaction = post.myReaction;

    if (currentReaction != null && currentReaction != nextReaction) {
      final int currentCount = reactions[currentReaction] ?? 0;
      if (currentCount > 1) {
        reactions[currentReaction] = currentCount - 1;
      } else {
        reactions.remove(currentReaction);
      }
    }

    if (nextReaction != null && nextReaction != currentReaction) {
      reactions[nextReaction] = (reactions[nextReaction] ?? 0) + 1;
    }

    return reactions;
  }

  Map<String, int>? _readReactionBreakdown(dynamic value) {
    if (value is! Map) {
      return null;
    }

    final Map<String, int> reactions = <String, int>{};
    value.forEach((key, dynamic count) {
      if (count is num && count > 0) {
        reactions[key.toString()] = count.toInt();
      }
    });
    return reactions;
  }

  void _handlePostLiked(dynamic payload) {
    if (payload is! Map || _post == null) {
      return;
    }

    final String postId = (payload['postId'] ?? '').toString();
    if (postId != _post!.id) {
      return;
    }

    final String currentUserId = (AuthSession.instance.user?['id'] ?? '')
        .toString();
    final String eventUserId = (payload['userId'] ?? '').toString();
    final bool isCurrentUser = eventUserId == currentUserId;
    final String? reaction = (payload['reaction'] ?? '').toString().isEmpty
        ? null
        : (payload['reaction'] ?? '').toString();
    final Map<String, int>? reactions = _readReactionBreakdown(
      payload['reactions'],
    );

    setState(() {
      _post = _post!.copyWith(
        reactionCount: (payload['reactionCount'] as num?)?.toInt(),
        likedByMe: isCurrentUser
            ? payload['liked'] == true
            : _post!.isLikedByMe,
        myReaction: isCurrentUser ? reaction : _post!.myReaction,
        clearMyReaction: isCurrentUser && reaction == null,
        reactions: reactions,
      );
    });
  }

  void _handlePostCommentCount(dynamic payload) {
    if (payload is! Map || _post == null) {
      return;
    }

    final String postId = (payload['postId'] ?? '').toString();
    final int? commentCount = (payload['commentCount'] as num?)?.toInt();
    if (postId != _post!.id || commentCount == null) {
      return;
    }

    setState(() {
      _post = _post!.copyWith(commentCount: commentCount);
    });
  }

  void _handleCommentChanged(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final String postId = (payload['postId'] ?? '').toString();
    if (postId != _effectivePostId) {
      return;
    }
    _loadComments();
  }

  void _handleCommentLiked(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final String postId = (payload['postId'] ?? '').toString();
    if (postId != _effectivePostId) {
      return;
    }
    final String commentId = (payload['commentId'] ?? '').toString();
    final int? likeCount = (payload['likeCount'] as num?)?.toInt();
    if (commentId.isEmpty || likeCount == null) {
      _loadComments();
      return;
    }

    final String currentUserId = (AuthSession.instance.user?['id'] ?? '')
        .toString();
    final String eventUserId = (payload['userId'] ?? '').toString();
    final bool isCurrentUser = eventUserId == currentUserId;

    setState(() {
      _comments = _replaceComment(
        _comments,
        commentId,
        (comment) => comment.copyWith(
          likeCount: likeCount,
          likedByMe: isCurrentUser
              ? payload['liked'] == true
              : comment.isLikedByMe,
        ),
      );
    });
  }

  Future<void> _toggleCommentReaction(CommentItem comment) async {
    if (_post?.allowReactions == false) {
      _showError('Reactions are locked for this post.');
      return;
    }
    if (_pendingCommentReactionIds.contains(comment.id)) {
      return;
    }

    final bool nextLiked = !comment.isLikedByMe;
    final int nextCount = nextLiked
        ? comment.likeCount + 1
        : (comment.likeCount > 0 ? comment.likeCount - 1 : 0);

    setState(() {
      _pendingCommentReactionIds.add(comment.id);
      _comments = _replaceComment(
        _comments,
        comment.id,
        (item) => item.copyWith(likedByMe: nextLiked, likeCount: nextCount),
      );
    });

    try {
      final CommentLikeResult result = await CommentsApi.instance.toggleLike(
        comment.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = _replaceComment(
          _comments,
          result.commentId,
          (item) => item.copyWith(
            likedByMe: result.liked,
            likeCount: result.likeCount,
          ),
        );
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = _replaceComment(
          _comments,
          comment.id,
          (item) => item.copyWith(
            likedByMe: comment.isLikedByMe,
            likeCount: comment.likeCount,
          ),
        );
      });
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _comments = _replaceComment(
          _comments,
          comment.id,
          (item) => item.copyWith(
            likedByMe: comment.isLikedByMe,
            likeCount: comment.likeCount,
          ),
        );
      });
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _pendingCommentReactionIds.remove(comment.id));
      } else {
        _pendingCommentReactionIds.remove(comment.id);
      }
    }
  }

  List<CommentItem> _replaceComment(
    List<CommentItem> source,
    String commentId,
    CommentItem Function(CommentItem comment) update,
  ) {
    return source.map((comment) {
      final CommentItem next = comment.id == commentId
          ? update(comment)
          : comment;
      if (next.replies.isEmpty) {
        return next;
      }
      return next.copyWith(
        replies: _replaceComment(next.replies, commentId, update),
      );
    }).toList();
  }

  bool get _isAdmin {
    final String role = (AuthSession.instance.user?['role'] ?? '')
        .toString()
        .toUpperCase();
    return role == 'ADMIN' || role == 'MODERATOR';
  }

  bool get _isPostOwner {
    final String myId = (AuthSession.instance.user?['id'] ?? '').toString();
    return _post != null && _post!.authorId == myId;
  }

  bool get _canEditPost {
    // Only the post author can edit their own post. Admins go through
    // the moderation flow, not the in-place edit dialog.
    return _isPostOwner;
  }

  bool get _canDeletePost {
    // Post author or admin can delete the post.
    return _isPostOwner || _isAdmin;
  }

  bool _canDeleteComment(CommentItem comment) {
    // Comment author can always delete their own comment.
    if (_isMyComment(comment)) {
      return true;
    }
    // The post owner can delete any comment on their post.
    if (_isPostOwner) {
      return true;
    }
    // Admins / moderators can delete any comment.
    if (_isAdmin) {
      return true;
    }
    return false;
  }

  Future<void> _editPost() async {
    final FeedPost? post = _post;
    if (post == null) {
      return;
    }

    final TextEditingController controller = TextEditingController(
      text: post.content,
    );
    bool allowComments = post.allowComments;
    bool allowReactions = post.allowReactions;

    final _PostEditDraft? draft = await showDialog<_PostEditDraft>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit post'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Post content',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: allowComments,
                    onChanged: (value) =>
                        setDialogState(() => allowComments = value),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFF33B8FF),
                    title: const Text(
                      'Allow comments',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'People who can see this post can comment.',
                    ),
                  ),
                  SwitchListTile(
                    value: allowReactions,
                    onChanged: (value) =>
                        setDialogState(() => allowReactions = value),
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: const Color(0xFF33B8FF),
                    title: const Text(
                      'Allow reactions',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'People who can see this post can react.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(
                  context,
                  _PostEditDraft(
                    content: controller.text.trim(),
                    allowComments: allowComments,
                    allowReactions: allowReactions,
                  ),
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    if (draft == null) {
      return;
    }
    if (draft.content.isEmpty) {
      _showError('Post content cannot be empty.');
      return;
    }

    try {
      final FeedPost updated = await PostsApi.instance.updatePost(
        postId: post.id,
        content: draft.content,
        allowComments: draft.allowComments,
        allowReactions: draft.allowReactions,
      );
      if (!mounted) {
        return;
      }
      setState(() => _post = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post updated.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  Future<void> _reportPost() async {
    final FeedPost? post = _post;
    if (post == null) {
      return;
    }
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

  Future<void> _deletePost() async {
    final FeedPost? post = _post;
    if (post == null) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This post will be removed from the feed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await PostsApi.instance.deletePost(post.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Post deleted.')));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  Future<void> _toggleBookmark() async {
    final FeedPost? post = _post;
    if (post == null || _isBookmarkPending) {
      return;
    }

    final bool nextBookmarked = !post.bookmarkedByMe;
    setState(() {
      _isBookmarkPending = true;
      _post = post.copyWith(bookmarkedByMe: nextBookmarked);
    });

    try {
      final bool confirmed = nextBookmarked
          ? await PostsApi.instance.bookmarkPost(post.id)
          : await PostsApi.instance.unbookmarkPost(post.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _post = _post?.copyWith(bookmarkedByMe: confirmed);
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _post = post);
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _post = post);
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isBookmarkPending = false);
      }
    }
  }

  Future<void> _reportComment(CommentItem comment) async {
    final bool submitted = await showReportSheet(
      context: context,
      targetType: 'COMMENT',
      targetId: comment.id,
      title: 'Report this comment',
      description: 'Tell us what is wrong with this comment.',
    );
    if (!submitted || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thanks! We will review it.')));
  }

  Future<void> _deleteComment(CommentItem comment) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: Text(
          _isMyComment(comment)
              ? 'Your comment will be removed permanently.'
              : 'This comment will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD04545),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    // Optimistically remove the comment from local state so the UI updates
    // immediately. The realtime 'comment:deleted' event will reconcile
    // if we missed anything.
    setState(() {
      _comments = _removeCommentFromList(_comments, comment.id);
    });

    try {
      await CommentsApi.instance.deleteComment(comment.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Comment deleted.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      // Reload on failure to restore the optimistic update.
      await _loadComments();
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _loadComments();
      if (!mounted) {
        return;
      }
      _showError(error.toString());
    }
  }

  List<CommentItem> _removeCommentFromList(
    List<CommentItem> source,
    String commentId,
  ) {
    final List<CommentItem> next = <CommentItem>[];
    for (final CommentItem c in source) {
      if (c.id == commentId) {
        continue;
      }
      final List<CommentItem> filteredReplies = c.replies
          .where((reply) => reply.id != commentId)
          .toList();
      next.add(c.copyWith(replies: filteredReplies));
    }
    return next;
  }

  void _setReplyTarget(CommentItem comment) {
    setState(() {
      _replyTargetCommentId = comment.id;
      _replyTargetAuthor = comment.authorDisplayName;
    });
    _commentFocus.requestFocus();
  }

  void _clearReplyTarget() {
    setState(() {
      _replyTargetCommentId = null;
      _replyTargetAuthor = null;
    });
  }

  void _showCommentsLockedMessage() {
    _showError('Comments are locked for this post.');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pop back to the caller (typically the Home tab) so the user lands
  /// on the home feed. If we are not inside a push stack (e.g. opened
  /// from a deep link), fall back to switching the bottom tab.
  void _goToHome() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    AppShellNavigator.instance.switchToHome();
  }

  @override
  Widget build(BuildContext context) {
    final FeedPost? post = _post;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'Post details',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        leading: IconButton(
          tooltip: 'Back to home',
          icon: const Icon(Icons.home_rounded),
          onPressed: _goToHome,
        ),
        actions: [
          if (_post != null)
            IconButton(
              tooltip: _post!.bookmarkedByMe ? 'Remove bookmark' : 'Save post',
              onPressed: _isBookmarkPending ? null : _toggleBookmark,
              icon: _isBookmarkPending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _post!.bookmarkedByMe
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      color: _post!.bookmarkedByMe
                          ? const Color(0xFFFFA94D)
                          : const Color(0xFF1A3D7C),
                    ),
            ),
          if (_post != null && !_isPostOwner && !_isAdmin)
            IconButton(
              tooltip: 'Report post',
              icon: const Icon(Icons.flag_outlined),
              onPressed: _reportPost,
            ),
          if (_canEditPost)
            IconButton(
              tooltip: 'Edit post',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _editPost,
            ),
          if (_canDeletePost)
            IconButton(
              tooltip: _isAdmin && !_isPostOwner
                  ? 'Admin: delete post'
                  : 'Delete post',
              icon: const Icon(Icons.delete_outline),
              onPressed: _deletePost,
            ),
        ],
      ),
      body: _isLoading && post == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait<void>([_loadPost(), _loadComments()]);
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _buildPostCard(post),
                        const SizedBox(height: 20),
                        _buildCommentsHeader(),
                        const SizedBox(height: 10),
                        _buildCommentsList(),
                      ],
                    ),
                  ),
                ),
                _buildCommentInput(),
              ],
            ),
    );
  }

  Future<void> _showReactionUsers(String reaction) async {
    final FeedPost? post = _post;
    if (post == null || !_isPostOwner) {
      return;
    }

    final ReactionOption? option = kReactionCatalog[reaction];
    if (option == null) {
      return;
    }

    final String title = _reactionTitle(reaction);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: FutureBuilder<List<PostReactionUser>>(
                future: PostsApi.instance.reactionUsers(
                  post.id,
                  reaction: reaction,
                ),
                builder: (context, snapshot) {
                  final List<PostReactionUser> users =
                      snapshot.data ?? const <PostReactionUser>[];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: option.color.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(option.icon, color: option.color),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$title reactions',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A3D7C),
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'People who reacted to your post.',
                        style: TextStyle(
                          color: Color(0xFF7A8BBF),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 26),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Text(
                            snapshot.error.toString(),
                            style: const TextStyle(color: Color(0xFFFF5A9E)),
                          ),
                        )
                      else if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No users found for this reaction.',
                              style: TextStyle(
                                color: Color(0xFF7A8BBF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: users.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final PostReactionUser item = users[index];
                              final PublicUser user = item.user;
                              final String name =
                                  user.displayName.trim().isEmpty
                                  ? user.username
                                  : user.displayName;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: UserAvatar(
                                  avatarUrl: user.avatarUrl,
                                  initials: user.initials,
                                  radius: 20,
                                  lastActiveAt: user.lastActiveAt,
                                ),
                                title: Text(
                                  name.isEmpty ? 'Friend' : name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A3D7C),
                                  ),
                                ),
                                subtitle: Text(
                                  user.username.isEmpty
                                      ? DateTimeFormatter.format(item.reactedAt)
                                      : '@${user.username} - ${DateTimeFormatter.format(item.reactedAt)}',
                                  style: const TextStyle(
                                    color: Color(0xFF7A8BBF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: Icon(
                                  option.icon,
                                  color: option.color,
                                  size: 20,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openPublicUserProfile(user);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCommentReactionUsers(CommentItem comment) async {
    if (!_isMyComment(comment) || comment.likeCount <= 0) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
              ),
              child: FutureBuilder<List<CommentReactionUser>>(
                future: CommentsApi.instance.reactionUsers(comment.id),
                builder: (context, snapshot) {
                  final List<CommentReactionUser> users =
                      snapshot.data ?? const <CommentReactionUser>[];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFF5A9E,
                              ).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF5A9E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Comment reactions',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A3D7C),
                                fontSize: 16,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'People who reacted to your comment.',
                        style: TextStyle(
                          color: Color(0xFF7A8BBF),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 26),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          child: Text(
                            snapshot.error.toString(),
                            style: const TextStyle(color: Color(0xFFFF5A9E)),
                          ),
                        )
                      else if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No users found for this reaction.',
                              style: TextStyle(
                                color: Color(0xFF7A8BBF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: users.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final CommentReactionUser item = users[index];
                              final PublicUser user = item.user;
                              final String name =
                                  user.displayName.trim().isEmpty
                                  ? user.username
                                  : user.displayName;

                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: UserAvatar(
                                  avatarUrl: user.avatarUrl,
                                  initials: user.initials,
                                  radius: 20,
                                  lastActiveAt: user.lastActiveAt,
                                ),
                                title: Text(
                                  name.isEmpty ? 'Friend' : name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A3D7C),
                                  ),
                                ),
                                subtitle: Text(
                                  user.username.isEmpty
                                      ? DateTimeFormatter.format(item.reactedAt)
                                      : '@${user.username} - ${DateTimeFormatter.format(item.reactedAt)}',
                                  style: const TextStyle(
                                    color: Color(0xFF7A8BBF),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.favorite_rounded,
                                  color: Color(0xFFFF5A9E),
                                  size: 20,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  _openPublicUserProfile(user);
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  String _displayAuthorName(FeedPost? post) {
    if (post == null) {
      return '';
    }
    final String displayName = post.authorDisplayName.trim();
    if (displayName.isNotEmpty) {
      return displayName;
    }
    return post.authorUsername.trim();
  }

  void _openPostAuthor(FeedPost post) {
    final String authorId = post.authorId.trim();
    if (authorId.isEmpty) {
      return;
    }
    final String name = _displayAuthorName(post);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: authorId,
          name: name.isEmpty ? 'Friend' : name,
          age: 0,
          favoriteTopic: 'Music',
          avatarLabel: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          avatarUrl: post.authorAvatarUrl,
        ),
      ),
    );
  }

  void _openCommentAuthor(CommentItem comment) {
    final String authorId = comment.authorId.trim();
    if (authorId.isEmpty) {
      return;
    }
    final String name = comment.authorDisplayName.trim().isNotEmpty
        ? comment.authorDisplayName.trim()
        : comment.authorUsername.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: authorId,
          name: name.isEmpty ? 'Friend' : name,
          age: 0,
          favoriteTopic: 'Music',
          avatarLabel: name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
          avatarUrl: comment.authorAvatarUrl,
        ),
      ),
    );
  }

  void _openPublicUserProfile(PublicUser user) {
    final String name = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()
        : user.username.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: user.id,
          name: name.isEmpty ? 'Friend' : name,
          age: user.age,
          favoriteTopic: user.favoriteTopics.isEmpty
              ? 'Music'
              : user.favoriteTopics.first,
          avatarLabel: user.initials,
          avatarUrl: user.avatarUrl,
        ),
      ),
    );
  }

  Widget _buildPostCard(FeedPost? post) {
    final String authorName = _displayAuthorName(post);
    final String avatarLabel = authorName.isEmpty
        ? '?'
        : authorName.substring(0, 1).toUpperCase();
    final String? myReaction = post?.myReaction;
    final String activeReaction =
        myReaction != null && kReactionCatalog.containsKey(myReaction)
        ? myReaction
        : 'heart';
    final Map<String, int> reactions = _reactionBreakdownFor(post);

    return Container(
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
                onTap: post == null ? null : () => _openPostAuthor(post),
                child: UserAvatar(
                  avatarUrl: post?.authorAvatarUrl ?? '',
                  initials: avatarLabel,
                  radius: 20,
                  backgroundColor: const Color(0xFFFFC5E6),
                  lastActiveAt: post?.authorLastActiveAt,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: post == null ? null : () => _openPostAuthor(post),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        authorName.isEmpty ? 'Little Star' : authorName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              DateTimeFormatter.format(post?.createdAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9AA7C7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (post != null) ...[
                            const SizedBox(width: 6),
                            PostAudienceBadge.forPost(post, compact: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (post != null && _isPendingReview(post)) _buildReviewBanner(post),
          Text(
            post?.content ??
                'Today I drew a beautiful sky! Look at those sparkling stars.',
            style: const TextStyle(height: 1.4),
          ),
          if (post?.mediaUrls.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            MediaPreviewGrid(urls: post!.mediaUrls),
          ],
          if (reactions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _ReactionBreakdown(
              reactions: reactions,
              onReactionTap: _isPostOwner ? _showReactionUsers : null,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (post != null && post.allowReactions)
                _ReactionButton(
                  post: post,
                  activeReaction: activeReaction,
                  isPending: _isLikePending,
                  onPick: _reactToPost,
                )
              else if (post != null)
                const _ActionChip(
                  icon: Icons.lock_outline_rounded,
                  label: 'Reactions off',
                )
              else
                _ActionChip(
                  icon: Icons.favorite_border_rounded,
                  label: '0 likes',
                ),
              _ActionChip(
                icon: post?.allowComments == false
                    ? Icons.lock_outline_rounded
                    : Icons.chat_bubble,
                label: post?.allowComments == false
                    ? 'Comments off'
                    : '${post?.commentCount ?? _comments.length} comments',
              ),
              _ActionChip(
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: _post == null ? null : _reportPost,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// True when the post is currently waiting for admin review
  /// (HIDDEN because an attachment crossed the AI threshold). The
  /// post author is the only one who can see this state on the
  /// detail screen — the feed query already hides HIDDEN posts
  /// from everyone else.
  bool _isPendingReview(FeedPost post) {
    return post.isPendingReview;
  }

  Widget _buildReviewBanner(FeedPost post) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD591)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(
            Icons.shield_outlined,
            color: Color(0xFF874800),
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang chờ admin duyệt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF874800),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Hình ảnh trong bài đăng này đang được admin xem xét. Bạn sẽ nhận được thông báo khi có kết quả.',
                  style: TextStyle(
                    color: Color(0xFF874800),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, int> _reactionBreakdownFor(FeedPost? post) {
    if (post == null) {
      return const <String, int>{};
    }
    if (post.reactions.isNotEmpty) {
      return post.reactions;
    }
    if (post.reactionCount <= 0) {
      return const <String, int>{};
    }

    final String fallbackReaction =
        post.myReaction != null && kReactionCatalog.containsKey(post.myReaction)
        ? post.myReaction!
        : 'heart';
    return <String, int>{fallbackReaction: post.reactionCount};
  }

  String _reactionTitle(String reaction) {
    if (reaction.isEmpty) {
      return 'Reaction';
    }
    return '${reaction[0].toUpperCase()}${reaction.substring(1)}';
  }

  Widget _buildCommentsHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Comments',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loadComments,
          icon: const Icon(Icons.refresh_rounded, size: 20),
        ),
      ],
    );
  }

  Widget _buildCommentsList() {
    if (_isCommentsLoading && _comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_comments.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.forum_outlined, size: 48, color: Color(0xFF9AA7C7)),
            SizedBox(height: 8),
            Text(
              'No comments yet. Be the first to reply!',
              style: TextStyle(color: Color(0xFF7A8BBF)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final CommentItem comment in _comments) ...[
          _CommentCard(
            comment: comment,
            isMine: _isMyComment(comment),
            canDelete: _canDeleteComment(comment),
            onReport: () => _reportComment(comment),
            onDelete: () => _deleteComment(comment),
            onReply: _post?.allowComments == false
                ? _showCommentsLockedMessage
                : () => _setReplyTarget(comment),
            onReact: () => _toggleCommentReaction(comment),
            reactionsEnabled: _post?.allowReactions != false,
            isReactionPending: _pendingCommentReactionIds.contains(comment.id),
            canViewReactors: _isMyComment(comment) && comment.likeCount > 0,
            onViewReactors: () => _showCommentReactionUsers(comment),
            onAuthorTap: () => _openCommentAuthor(comment),
            onAuthorTapFor: _openCommentAuthor,
            depth: 0,
            onReportReply: _reportComment,
            onReplyToReply: _post?.allowComments == false
                ? (_) => _showCommentsLockedMessage()
                : _setReplyTarget,
            onReactReply: _toggleCommentReaction,
            isReplyReactionPending: (reply) =>
                _pendingCommentReactionIds.contains(reply.id),
            canViewReplyReactors: (reply) =>
                _isMyComment(reply) && reply.likeCount > 0,
            onViewReplyReactors: _showCommentReactionUsers,
            onDeleteReply: _deleteComment,
            isMyReply: _isMyComment,
            canDeleteReply: _canDeleteComment,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  bool _isMyComment(CommentItem comment) {
    final String myId = (AuthSession.instance.user?['id'] ?? '').toString();
    return myId.isNotEmpty && comment.authorId == myId;
  }

  Widget _buildCommentInput() {
    if (_post?.allowComments == false) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F6FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD7E7FF)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: Color(0xFF7A8BBF),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Comments are locked for this post.',
                  style: TextStyle(
                    color: Color(0xFF1A3D7C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final String replyHint = _replyTargetCommentId == null
        ? 'Write a comment...'
        : 'Reply to ${_replyTargetAuthor ?? 'friend'}...';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTargetCommentId != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.reply_rounded,
                    size: 16,
                    color: Color(0xFF33B8FF),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Replying to ${_replyTargetAuthor ?? 'comment'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1A3D7C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _clearReplyTarget,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF7A8BBF),
                    ),
                  ),
                ],
              ),
            ),
          if (_pickedCommentMedia.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final XFile file in _pickedCommentMedia)
                    Chip(
                      label: Text(file.name),
                      onDeleted: _isSendingComment
                          ? null
                          : () => setState(
                              () => _pickedCommentMedia.remove(file),
                            ),
                    ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: _isSendingComment
                    ? null
                    : () => _pickCommentMedia(video: false),
                icon: const Icon(Icons.photo_library_rounded),
                color: const Color(0xFF33B8FF),
              ),
              IconButton(
                onPressed: _isSendingComment
                    ? null
                    : () => _pickCommentMedia(video: true),
                icon: const Icon(Icons.video_library_rounded),
                color: const Color(0xFF7A5CFF),
              ),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _commentFocus,
                  decoration: InputDecoration(
                    hintText: replyHint,
                    filled: true,
                    fillColor: const Color(0xFFF0F6FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFF9AD5),
                child: IconButton(
                  onPressed: _sendComment,
                  icon: _isSendingComment
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostEditDraft {
  const _PostEditDraft({
    required this.content,
    required this.allowComments,
    required this.allowReactions,
  });

  final String content;
  final bool allowComments;
  final bool allowReactions;
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF33B8FF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.post,
    required this.activeReaction,
    required this.isPending,
    required this.onPick,
  });

  final FeedPost post;
  final String activeReaction;
  final bool isPending;
  final ValueChanged<String> onPick;

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
                        border: active
                            ? Border.all(color: entry.value.color, width: 1.4)
                            : null,
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
    if (reaction != null) {
      onPick(reaction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ReactionOption active = kReactionCatalog[activeReaction]!;
    final bool isActive = post.isLikedByMe;
    final String reactionName =
        '${activeReaction[0].toUpperCase()}${activeReaction.substring(1)}';

    return InkWell(
      onTap: isPending ? null : () => _showPicker(context),
      onLongPress: isPending ? null : () => _showPicker(context),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? active.color.withValues(alpha: 0.12)
              : const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPending)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isActive ? active.color : const Color(0xFF33B8FF),
                ),
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
                  ? '$reactionName ${post.reactionCount}'
                  : '${post.reactionCount} likes',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionBreakdown extends StatelessWidget {
  const _ReactionBreakdown({required this.reactions, this.onReactionTap});

  final Map<String, int> reactions;
  final ValueChanged<String>? onReactionTap;

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

        return InkWell(
          onTap: onReactionTap == null ? null : () => onReactionTap!(entry.key),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: option.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: onReactionTap == null
                  ? null
                  : Border.all(color: option.color.withValues(alpha: 0.28)),
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
          ),
        );
      }).toList(),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({
    required this.comment,
    required this.isMine,
    required this.canDelete,
    required this.onReport,
    required this.onDelete,
    required this.onReply,
    required this.onReact,
    required this.reactionsEnabled,
    required this.isReactionPending,
    required this.canViewReactors,
    required this.onViewReactors,
    required this.onAuthorTap,
    required this.onAuthorTapFor,
    required this.depth,
    required this.onReportReply,
    required this.onReplyToReply,
    required this.onReactReply,
    required this.isReplyReactionPending,
    required this.canViewReplyReactors,
    required this.onViewReplyReactors,
    required this.onDeleteReply,
    required this.isMyReply,
    required this.canDeleteReply,
  });

  final CommentItem comment;
  final bool isMine;
  final bool canDelete;
  final VoidCallback onReport;
  final VoidCallback onDelete;
  final VoidCallback onReply;
  final VoidCallback onReact;
  final bool reactionsEnabled;
  final bool isReactionPending;
  final bool canViewReactors;
  final VoidCallback onViewReactors;
  final VoidCallback onAuthorTap;
  final void Function(CommentItem) onAuthorTapFor;
  final int depth;
  final void Function(CommentItem) onReportReply;
  final void Function(CommentItem) onReplyToReply;
  final void Function(CommentItem) onReactReply;
  final bool Function(CommentItem) isReplyReactionPending;
  final bool Function(CommentItem) canViewReplyReactors;
  final void Function(CommentItem) onViewReplyReactors;
  final void Function(CommentItem) onDeleteReply;
  final bool Function(CommentItem) isMyReply;
  final bool Function(CommentItem) canDeleteReply;

  @override
  Widget build(BuildContext context) {
    final bool indented = depth > 0;
    final String authorName = _displayName(
      comment.authorDisplayName,
      fallback: comment.authorUsername,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(indented ? 12 : 12, 12, 12, 12),
      margin: EdgeInsets.only(left: depth * 16.0),
      decoration: BoxDecoration(
        color: indented ? const Color(0xFFF3F8FF) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: indented
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAuthorTap,
                child: UserAvatar(
                  avatarUrl: comment.authorAvatarUrl,
                  initials: _initials(authorName),
                  radius: 16,
                  backgroundColor: const Color(0xFFBEEAFF),
                  lastActiveAt: comment.authorLastActiveAt,
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
                        authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                      if (DateTimeFormatter.format(
                        comment.createdAt,
                      ).isNotEmpty)
                        Text(
                          DateTimeFormatter.format(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF9AA7C7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (canDelete)
                IconButton(
                  tooltip: isMine ? 'Delete' : 'Moderator: delete',
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFD04545),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                IconButton(
                  tooltip: 'Report',
                  onPressed: onReport,
                  icon: const Icon(
                    Icons.flag_outlined,
                    size: 18,
                    color: Color(0xFF7A8BBF),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          if (comment.content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment.content,
              style: const TextStyle(color: Color(0xFF1A3D7C)),
            ),
          ],
          if (comment.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            MediaPreviewGrid(urls: comment.mediaUrls, compact: true),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: reactionsEnabled && !isReactionPending
                    ? onReact
                    : null,
                icon: isReactionPending
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        comment.isLikedByMe
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 16,
                      ),
                label: Text(comment.isLikedByMe ? 'Reacted' : 'React'),
                style: TextButton.styleFrom(
                  foregroundColor: comment.isLikedByMe
                      ? const Color(0xFFFF5A9E)
                      : const Color(0xFF33B8FF),
                  disabledForegroundColor: const Color(0xFF9AA7C7),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onReply,
                icon: const Icon(Icons.reply_rounded, size: 16),
                label: const Text('Reply'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF33B8FF),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 28),
                ),
              ),
              if (comment.likeCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: InkWell(
                    onTap: canViewReactors ? onViewReactors : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.favorite_rounded,
                            size: 12,
                            color: Color(0xFFFF5A9E),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${comment.likeCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: canViewReactors
                                  ? const Color(0xFFFF5A9E)
                                  : const Color(0xFF7A8BBF),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (comment.replies.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final CommentItem reply in comment.replies) ...[
              _CommentCard(
                comment: reply,
                isMine: isMyReply(reply),
                canDelete: canDeleteReply(reply),
                onReport: () => onReportReply(reply),
                onDelete: () => onDeleteReply(reply),
                onReply: () => onReplyToReply(reply),
                onReact: () => onReactReply(reply),
                reactionsEnabled: reactionsEnabled,
                isReactionPending: isReplyReactionPending(reply),
                canViewReactors: canViewReplyReactors(reply),
                onViewReactors: () => onViewReplyReactors(reply),
                onAuthorTap: () => onAuthorTapFor(reply),
                onAuthorTapFor: onAuthorTapFor,
                depth: depth + 1,
                onReportReply: onReportReply,
                onReplyToReply: onReplyToReply,
                onReactReply: onReactReply,
                isReplyReactionPending: isReplyReactionPending,
                canViewReplyReactors: canViewReplyReactors,
                onViewReplyReactors: onViewReplyReactors,
                onDeleteReply: onDeleteReply,
                isMyReply: isMyReply,
                canDeleteReply: canDeleteReply,
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  String _displayName(Object? value, {Object? fallback}) {
    final String primary = (value ?? '').toString().trim();
    if (primary.isNotEmpty) {
      return primary;
    }
    final String secondary = (fallback ?? '').toString().trim();
    return secondary.isNotEmpty ? secondary : 'Member';
  }

  String _initials(Object? source) {
    final String text = (source ?? '').toString().trim();
    if (text.isEmpty) {
      return '?';
    }
    final List<String> parts = text
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
