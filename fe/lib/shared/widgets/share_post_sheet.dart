import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/friends_api.dart';
import '../../shared/widgets/user_avatar.dart';

enum ShareResult {
  success,
  cancelled,
  error,
}

Future<ShareResult> showSharePostSheet({
  required BuildContext context,
  required FeedPost post,
}) async {
  final ShareResult? result = await showModalBottomSheet<ShareResult>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => SharePostSheet(post: post),
  );
  return result ?? ShareResult.cancelled;
}

class SharePostSheet extends StatefulWidget {
  const SharePostSheet({super.key, required this.post});

  final FeedPost post;

  @override
  State<SharePostSheet> createState() => _SharePostSheetState();
}

class _SharePostSheetState extends State<SharePostSheet> {
  bool _isSharingToProfile = false;
  bool _isChoosingFriend = false;
  List<PublicUser> _friends = const [];
  bool _isLoadingFriends = true;
  String? _sendingToUserId;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _shareToProfile() async {
    if (_isSharingToProfile) return;

    setState(() {
      _isSharingToProfile = true;
      _error = null;
    });

    try {
      await PostsApi.instance.sharePost(widget.post.id);
      if (!mounted) return;
      Navigator.pop(context, ShareResult.success);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post shared to your profile!')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSharingToProfile = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSharingToProfile = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoadingFriends = true;
      _isChoosingFriend = true;
    });

    try {
      final FriendsPage page = await FriendsApi.instance.listFriends();
      if (!mounted) return;
      setState(() {
        _friends = page.items;
        _isLoadingFriends = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingFriends = false);
    }
  }

  Future<void> _sendToFriend(PublicUser friend) async {
    if (_sendingToUserId != null) return;

    setState(() {
      _sendingToUserId = friend.id;
      _error = null;
    });

    try {
      final chat = await ChatsApi.instance.createDirectChat(friend.id);
      await ChatsApi.instance.sendPostShare(
        chatId: chat.id,
        postId: widget.post.id,
      );
      if (!mounted) return;
      Navigator.pop(context, ShareResult.success);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Post sent to ${friend.displayName.isNotEmpty ? friend.displayName : friend.username}!'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingToUserId = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sendingToUserId = null;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Share post',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                      fontSize: 18,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context, ShareResult.cancelled),
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF7A8BBF)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildPostPreview(),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD0D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFD04545), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFFD04545), fontSize: 13),
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close, color: Color(0xFFD04545), size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!_isChoosingFriend) ...[
              _ShareOptionTile(
                icon: Icons.person_add_rounded,
                iconColor: const Color(0xFF33B8FF),
                title: 'Share to your profile',
                subtitle: 'Post this to your own feed',
                isLoading: _isSharingToProfile,
                onTap: _shareToProfile,
              ),
              const SizedBox(height: 10),
              _ShareOptionTile(
                icon: Icons.send_rounded,
                iconColor: const Color(0xFF7A5CFF),
                title: 'Send to a friend',
                subtitle: 'Share via chat message',
                onTap: _loadFriends,
              ),
            ] else ...[
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => setState(() => _isChoosingFriend = false),
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A3D7C)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Choose a friend',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_isLoadingFriends)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_friends.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No friends yet. Add friends to share posts!',
                      style: TextStyle(color: Color(0xFF7A8BBF)),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _friends.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final friend = _friends[index];
                      final bool sending = _sendingToUserId == friend.id;
                      return _FriendShareTile(
                        friend: friend,
                        isLoading: sending,
                        onTap: sending ? null : () => _sendToFriend(friend),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPostPreview() {
    final post = widget.post;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7E7FF)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.authorDisplayName.isNotEmpty
                      ? post.authorDisplayName
                      : post.authorUsername,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  post.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7A8BBF),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (post.mediaUrls.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFE8F4FF),
              ),
              child: const Icon(
                Icons.image_rounded,
                color: Color(0xFF33B8FF),
                size: 22,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F8FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E7FF)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8BBF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isLoading ? const Color(0xFFD7E7FF) : const Color(0xFF7A8BBF),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendShareTile extends StatelessWidget {
  const _FriendShareTile({
    required this.friend,
    required this.onTap,
    required this.isLoading,
  });

  final PublicUser friend;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final String name = friend.displayName.isNotEmpty
        ? friend.displayName
        : friend.username;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: friend.avatarUrl,
              initials: friend.initials,
              radius: 20,
              backgroundColor: const Color(0xFFBEEAFF),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  if (friend.favoriteTopics.isNotEmpty)
                    Text(
                      friend.favoriteTopics.first,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7A8BBF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            if (isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.send_rounded,
                color: Color(0xFF7A5CFF),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
