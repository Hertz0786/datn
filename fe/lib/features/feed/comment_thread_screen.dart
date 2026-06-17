import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/comment_item.dart';
import '../../core/models/media_asset.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/comments_api.dart';
import '../../core/services/media_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/media_preview_grid.dart';
import '../../shared/widgets/report_sheet.dart';
import '../../shared/widgets/user_avatar.dart';

class CommentThreadScreen extends StatefulWidget {
  const CommentThreadScreen({
    super.key,
    this.postId,
    required this.postAuthor,
    required this.postTitle,
  });

  final String? postId;
  final String postAuthor;
  final String postTitle;

  @override
  State<CommentThreadScreen> createState() => _CommentThreadScreenState();
}

class _CommentThreadScreenState extends State<CommentThreadScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedMedia = <XFile>[];

  bool _isLoading = false;
  bool _isSending = false;
  List<CommentItem> _comments = const <CommentItem>[];
  final Set<String> _pendingLikeCommentIds = <String>{};

  String? _replyTargetCommentId;
  String? _replyTargetAuthor;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _listenRealtime();
  }

  @override
  void dispose() {
    if (widget.postId != null && widget.postId!.isNotEmpty) {
      RealtimeService.instance.emit('post:leave', widget.postId);
    }
    RealtimeService.instance.off('comment:created', _handleCommentChanged);
    RealtimeService.instance.off('comment:updated', _handleCommentChanged);
    RealtimeService.instance.off('comment:deleted', _handleCommentChanged);
    RealtimeService.instance.off('comment:liked', _handleCommentLiked);
    _inputController.dispose();
    super.dispose();
  }

  void _listenRealtime() {
    if (widget.postId != null && widget.postId!.isNotEmpty) {
      RealtimeService.instance.emit('post:join', widget.postId);
    }
    RealtimeService.instance.on('comment:created', _handleCommentChanged);
    RealtimeService.instance.on('comment:updated', _handleCommentChanged);
    RealtimeService.instance.on('comment:deleted', _handleCommentChanged);
    RealtimeService.instance.on('comment:liked', _handleCommentLiked);
  }

  Future<void> _loadComments() async {
    if (widget.postId == null || widget.postId!.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<CommentItem> items = await CommentsApi.instance.listByPost(
        widget.postId!,
      );

      if (!mounted) {
        return;
      }

      setState(() => _comments = items);
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
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _send() async {
    final String message = _inputController.text.trim();
    if ((message.isEmpty && _pickedMedia.isEmpty) || _isSending) {
      return;
    }

    if (widget.postId == null || widget.postId!.isEmpty) {
      return;
    }

    setState(() => _isSending = true);

    try {
      final List<MediaAsset> uploadedMedia = <MediaAsset>[];
      for (final XFile file in _pickedMedia) {
        uploadedMedia.add(await MediaApi.instance.upload(filePath: file.path));
      }
      final List<String> mediaUrls = uploadedMedia
          .map((media) => media.url)
          .where((url) => url.isNotEmpty)
          .toList();

      late final CommentItem created;
      if (_replyTargetCommentId != null) {
        created = await CommentsApi.instance.createReply(
          commentId: _replyTargetCommentId!,
          content: message,
          mediaUrls: mediaUrls,
        );
      } else {
        created = await CommentsApi.instance.createComment(
          postId: widget.postId!,
          content: message,
          mediaUrls: mediaUrls,
        );
      }

      for (final MediaAsset media in uploadedMedia) {
        await MediaApi.instance.updateSource(
          mediaId: media.id,
          sourceType: 'COMMENT',
          sourceId: created.id,
        );
      }

      _inputController.clear();
      _pickedMedia.clear();
      _replyTargetCommentId = null;
      _replyTargetAuthor = null;

      await _loadComments();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _pickMedia({required bool video}) async {
    if (_pickedMedia.length >= 3) {
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

    setState(() => _pickedMedia.add(file));
  }

  Future<void> _toggleCommentLike(CommentItem comment) async {
    if (_pendingLikeCommentIds.contains(comment.id)) {
      return;
    }

    final bool nextLiked = !comment.isLikedByMe;
    final int nextCount = nextLiked
        ? comment.likeCount + 1
        : (comment.likeCount > 0 ? comment.likeCount - 1 : 0);

    _pendingLikeCommentIds.add(comment.id);
    _replaceComment(
      comment.id,
      (item) => item.copyWith(likedByMe: nextLiked, likeCount: nextCount),
    );

    try {
      final CommentLikeResult result = await CommentsApi.instance.toggleLike(
        comment.id,
      );
      _replaceComment(
        result.commentId,
        (item) =>
            item.copyWith(likedByMe: result.liked, likeCount: result.likeCount),
      );
    } on ApiException catch (error) {
      _replaceComment(
        comment.id,
        (item) => item.copyWith(
          likedByMe: comment.isLikedByMe,
          likeCount: comment.likeCount,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      _replaceComment(
        comment.id,
        (item) => item.copyWith(
          likedByMe: comment.isLikedByMe,
          likeCount: comment.likeCount,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _pendingLikeCommentIds.remove(comment.id);
    }
  }

  void _replaceComment(
    String commentId,
    CommentItem Function(CommentItem comment) update,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      _comments = _comments.map((comment) {
        if (comment.id == commentId) {
          return update(comment);
        }

        final List<CommentItem> replies = comment.replies
            .map((reply) => reply.id == commentId ? update(reply) : reply)
            .toList();
        return comment.copyWith(replies: replies);
      }).toList();
    });
  }

  void _handleCommentChanged(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final String postId = (payload['postId'] ?? '').toString();
    if (postId != widget.postId) {
      return;
    }

    _loadComments();
  }

  void _handleCommentLiked(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final String postId = (payload['postId'] ?? '').toString();
    final String commentId = (payload['commentId'] ?? '').toString();
    final int? likeCount = (payload['likeCount'] as num?)?.toInt();
    if (postId != widget.postId || commentId.isEmpty || likeCount == null) {
      return;
    }

    final String currentUserId = (AuthSession.instance.user?['id'] ?? '')
        .toString();
    final String eventUserId = (payload['userId'] ?? '').toString();

    _replaceComment(
      commentId,
      (comment) => comment.copyWith(
        likeCount: likeCount,
        likedByMe: eventUserId == currentUserId
            ? payload['liked'] == true
            : comment.isLikedByMe,
      ),
    );
  }

  bool _isMine(CommentItem comment) {
    final String myId = (AuthSession.instance.user?['id'] ?? '').toString();
    return myId.isNotEmpty && comment.authorId == myId;
  }

  Future<void> _editComment(CommentItem comment) async {
    final TextEditingController controller = TextEditingController(
      text: comment.content,
    );
    final String? content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Comment content'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (content == null || content.isEmpty) {
      return;
    }

    try {
      await CommentsApi.instance.updateComment(
        commentId: comment.id,
        content: content,
      );
      await _loadComments();
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
      ).showSnackBar(SnackBar(content: Text(error.toString())));
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
        content: const Text('This comment will be removed from the thread.'),
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
      await CommentsApi.instance.deleteComment(comment.id);
      await _loadComments();
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
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final String replyHint = _replyTargetCommentId == null
        ? 'Write a comment...'
        : 'Reply to ${_replyTargetAuthor ?? 'friend'}...';

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.appHeading),
        title: Text(
          'Comment Thread',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.appHeading,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadComments,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE59E), Color(0xFFBEEAFF)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.forum_rounded, color: Color(0xFF1A3D7C)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.postAuthor}: ${widget.postTitle}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                ),
                Text(
                  '${_comments.length} comments',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadComments,
              child: _isLoading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _comments.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Icon(
                          Icons.forum_outlined,
                          size: 56,
                          color: Color(0xFF9AA7C7),
                        ),
                        SizedBox(height: 8),
                        Center(
                          child: Text(
                            'No comments yet. Be the first to reply!',
                            style: TextStyle(color: Color(0xFF7A8BBF)),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final CommentItem comment = _comments[index];
                        final String authorName = _displayName(
                          comment.authorDisplayName,
                          fallback: comment.authorUsername,
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
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
                                  UserAvatar(
                                    avatarUrl: comment.authorAvatarUrl,
                                    initials: _initials(authorName),
                                    radius: 16,
                                    backgroundColor: const Color(0xFFBEEAFF),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            DateTimeFormatter.format(
                                              comment.createdAt,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF9AA7C7),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_isMine(comment))
                                    _CommentMenu(
                                      onEdit: () => _editComment(comment),
                                      onDelete: () => _deleteComment(comment),
                                    )
                                  else
                                    IconButton(
                                      tooltip: 'Report',
                                      onPressed: () => _reportComment(comment),
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
                              const SizedBox(height: 8),
                              if (comment.content.isNotEmpty)
                                Text(
                                  comment.content,
                                  style: TextStyle(color: context.appHeading),
                                ),
                              if (comment.mediaUrls.isNotEmpty) ...[
                                if (comment.content.isNotEmpty)
                                  const SizedBox(height: 8),
                                MediaPreviewGrid(
                                  urls: comment.mediaUrls,
                                  compact: true,
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        _toggleCommentLike(comment),
                                    icon:
                                        _pendingLikeCommentIds.contains(
                                          comment.id,
                                        )
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Icon(
                                            comment.isLikedByMe
                                                ? Icons.favorite
                                                : Icons.favorite_border_rounded,
                                            size: 18,
                                          ),
                                    label: Text('${comment.likeCount} Like'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        _replyTargetCommentId = comment.id;
                                        _replyTargetAuthor = authorName;
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.reply_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Reply'),
                                  ),
                                  if (comment.replies.isNotEmpty)
                                    Text(
                                      '${comment.replies.length} replies',
                                      style: const TextStyle(
                                        color: Color(0xFF5A74A6),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              if (comment.replies.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ...comment.replies.map(
                                  (CommentItem reply) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F8FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        UserAvatar(
                                          avatarUrl: reply.authorAvatarUrl,
                                          initials: _initials(
                                            _displayName(
                                              reply.authorDisplayName,
                                              fallback: reply.authorUsername,
                                            ),
                                          ),
                                          radius: 13,
                                          backgroundColor: const Color(
                                            0xFFFFE59E,
                                          ),
                                          foregroundColor: const Color(
                                            0xFF7A2E5A,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      _displayName(
                                                        reply.authorDisplayName,
                                                        fallback: reply
                                                            .authorUsername,
                                                      ),
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                        color: Color(
                                                          0xFF2A4474,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  if (_isMine(reply))
                                                    _CommentMenu(
                                                      onEdit: () =>
                                                          _editComment(reply),
                                                      onDelete: () =>
                                                          _deleteComment(reply),
                                                    )
                                                  else
                                                    IconButton(
                                                      tooltip: 'Report',
                                                      onPressed: () =>
                                                          _reportComment(reply),
                                                      icon: const Icon(
                                                        Icons.flag_outlined,
                                                        size: 16,
                                                        color: Color(
                                                          0xFF7A8BBF,
                                                        ),
                                                      ),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                    ),
                                                ],
                                              ),
                                              if (DateTimeFormatter.format(
                                                reply.createdAt,
                                              ).isNotEmpty)
                                                Text(
                                                  DateTimeFormatter.format(
                                                    reply.createdAt,
                                                  ),
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF9AA7C7),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              const SizedBox(height: 4),
                                              if (reply.content.isNotEmpty)
                                                Text(reply.content),
                                              if (reply
                                                  .mediaUrls
                                                  .isNotEmpty) ...[
                                                if (reply.content.isNotEmpty)
                                                  const SizedBox(height: 6),
                                                MediaPreviewGrid(
                                                  urls: reply.mediaUrls,
                                                  compact: true,
                                                ),
                                              ],
                                              const SizedBox(height: 4),
                                              TextButton.icon(
                                                onPressed: () =>
                                                    _toggleCommentLike(reply),
                                                icon:
                                                    _pendingLikeCommentIds
                                                        .contains(reply.id)
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      )
                                                    : Icon(
                                                        reply.isLikedByMe
                                                            ? Icons.favorite
                                                            : Icons
                                                                  .favorite_border_rounded,
                                                        size: 16,
                                                      ),
                                                label: Text(
                                                  '${reply.likeCount} Like',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          Container(
            color: context.appSurface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pickedMedia.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final XFile file in _pickedMedia)
                          Chip(
                            label: Text(file.name),
                            onDeleted: _isSending
                                ? null
                                : () =>
                                      setState(() => _pickedMedia.remove(file)),
                          ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _isSending
                          ? null
                          : () => _pickMedia(video: false),
                      icon: const Icon(Icons.photo_library_rounded),
                      color: const Color(0xFF33B8FF),
                    ),
                    IconButton(
                      onPressed: _isSending
                          ? null
                          : () => _pickMedia(video: true),
                      icon: const Icon(Icons.video_library_rounded),
                      color: const Color(0xFF7A5CFF),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: InputDecoration(
                          hintText: replyHint,
                          filled: true,
                          fillColor: context.appChip,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: const Color(0xFF33B8FF),
                      child: IconButton(
                        onPressed: _send,
                        icon: _isSending
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(Object? source) {
    final String text = (source ?? '').toString().trim();
    if (text.isEmpty) {
      return '?';
    }

    final List<String> parts = text
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  String _displayName(Object? value, {Object? fallback}) {
    final String primary = (value ?? '').toString().trim();
    if (primary.isNotEmpty) {
      return primary;
    }
    final String secondary = (fallback ?? '').toString().trim();
    return secondary.isNotEmpty ? secondary : 'Member';
  }
}

class _CommentMenu extends StatelessWidget {
  const _CommentMenu({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz_rounded, size: 18),
      onSelected: (value) {
        if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          onDelete();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
