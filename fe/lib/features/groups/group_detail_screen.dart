import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_theme.dart';
import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/chat_summary.dart';
import '../../core/models/feed_post.dart';
import '../../core/models/group_detail_data.dart';
import '../../core/models/media_asset.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/groups_api.dart';
import '../../core/services/media_api.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/user_avatar.dart';
import '../chat/chat_detail_screen.dart';
import '../feed/create_post_screen.dart';
import '../feed/post_detail_screen.dart';
import '../friends/friend_profile_screen.dart';
import 'group_avatar.dart';
import 'group_info.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({super.key, required this.group});

  final GroupInfo group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _joined = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isUploadingAvatar = false;
  bool _isOpeningChat = false;
  bool _isPostsLoading = false;
  bool _isLoadingMore = false;

  late GroupInfo _group;
  List<PublicUser> _members = const <PublicUser>[];
  List<PublicUser> _pendingMembers = const <PublicUser>[];
  List<FeedPost> _posts = const <FeedPost>[];
  final Set<String> _removingMemberIds = <String>{};
  final Set<String> _respondingJoinUserIds = <String>{};
  String? _postsNextBefore;
  bool _postsHasMore = false;
  bool _isPending = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _loadDetail();
  }

  bool _isMongoObjectId(String value) {
    return RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(value);
  }

  String get _currentUserId {
    return (AuthSession.instance.user?['id'] ??
            AuthSession.instance.user?['_id'] ??
            '')
        .toString();
  }

  bool get _isOwner {
    final String ownerId = _group.ownerId.trim();
    final String currentUserId = _currentUserId.trim();
    return ownerId.isNotEmpty &&
        currentUserId.isNotEmpty &&
        ownerId == currentUserId;
  }

  Future<void> _loadDetail() async {
    if (_group.id.isEmpty || !_isMongoObjectId(_group.id)) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final GroupDetailData detail = await GroupsApi.instance.getGroup(
        _group.id,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _group = detail.group;
        _members = detail.members;
        _pendingMembers = detail.pendingMembers;
        _joined = detail.isJoined;
        _isPending = detail.isPending;
      });

      if (_joined) {
        await _loadGroupPosts();
      }
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

  Future<void> _loadGroupPosts({bool loadMore = false}) async {
    if (_group.id.isEmpty || !_isMongoObjectId(_group.id)) {
      return;
    }
    if (loadMore && (_isLoadingMore || !_postsHasMore)) {
      return;
    }

    setState(() {
      if (loadMore) {
        _isLoadingMore = true;
      } else {
        _isPostsLoading = true;
      }
    });

    try {
      final GroupPostsPage page = await GroupsApi.instance.listGroupPosts(
        groupId: _group.id,
        limit: 20,
        before: loadMore ? _postsNextBefore : null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (loadMore) {
          _posts = <FeedPost>[..._posts, ...page.items];
        } else {
          _posts = page.items;
        }
        _postsNextBefore = page.nextBefore;
        _postsHasMore = page.hasMore;
      });
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
        setState(() {
          _isPostsLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _toggleJoin() async {
    if (_group.id.isEmpty || _isSubmitting || _isOwner) {
      return;
    }

    setState(() => _isSubmitting = true);
    final bool wasJoined = _joined;

    try {
      if (_joined) {
        await GroupsApi.instance.leaveGroup(_group.id);
      } else {
        await GroupsApi.instance.joinGroup(_group.id);
      }

      await _loadDetail();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasJoined
                ? 'Left group successfully.'
                : 'Join request sent. Waiting for owner approval.',
          ),
        ),
      );
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _openCreatePost() async {
    if (!_joined) {
      return;
    }
    final bool? created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreatePostScreen(groupId: _group.id, groupName: _group.name),
      ),
    );
    if (!mounted) {
      return;
    }
    if (created == true) {
      await _loadGroupPosts();
    }
  }

  Future<void> _openGroupChat() async {
    if (!_joined || _group.id.isEmpty || _isOpeningChat) {
      return;
    }

    setState(() => _isOpeningChat = true);

    try {
      final ChatSummary chat = await ChatsApi.instance.openSocialGroupChat(
        _group.id,
      );
      if (!mounted) {
        return;
      }

      final String title = chat.title.trim().isNotEmpty
          ? chat.title.trim()
          : _group.name;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chat.id,
            title: title,
            avatarUrl: chat.avatarUrl.trim().isNotEmpty
                ? chat.avatarUrl
                : _group.avatarUrl,
            avatarLabel: _groupInitials(title),
            isGroup: true,
            isSocialGroup: true,
            members: chat.memberUsers.isNotEmpty ? chat.memberUsers : _members,
            createdBy: chat.createdBy,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Failed to open group chat: $error');
    } finally {
      if (mounted) {
        setState(() => _isOpeningChat = false);
      }
    }
  }

  String _groupInitials(String title) {
    final List<String> parts = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'GR';
    }
    if (parts.length == 1) {
      final String first = parts.first;
      return first.length >= 2
          ? first.substring(0, 2).toUpperCase()
          : first.toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  void _openPost(FeedPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      ),
    );
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

  Future<void> _changeGroupAvatar() async {
    if (!_isOwner || _isUploadingAvatar || _group.id.isEmpty) {
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 84,
    );
    if (image == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isUploadingAvatar = true);

    try {
      final MediaAsset media = await MediaApi.instance.upload(
        filePath: image.path,
        sourceType: 'GROUP',
        sourceId: _group.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _group = _group.copyWith(avatarUrl: media.url);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Group avatar updated.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Failed to update group avatar: $error');
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _removeMember(PublicUser user) async {
    if (!_isOwner || user.id.isEmpty || user.id == _currentUserId) {
      return;
    }

    final String name = user.displayName.isNotEmpty
        ? user.displayName
        : user.username;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove $name from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _removingMemberIds.add(user.id));

    try {
      await GroupsApi.instance.removeMember(
        groupId: _group.id,
        userId: user.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _members = _members
            .where((PublicUser member) => member.id != user.id)
            .toList();
        final int nextCount = _group.memberCount > 1
            ? _group.memberCount - 1
            : 1;
        _group = _group.copyWith(memberCount: nextCount);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name was removed from the group.')),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Failed to remove member: $error');
    } finally {
      if (mounted) {
        setState(() => _removingMemberIds.remove(user.id));
      }
    }
  }

  Future<void> _reviewJoinRequest({
    required PublicUser user,
    required String action,
  }) async {
    if (!_isOwner ||
        user.id.isEmpty ||
        _respondingJoinUserIds.contains(user.id)) {
      return;
    }

    setState(() => _respondingJoinUserIds.add(user.id));

    try {
      await GroupsApi.instance.updateJoinRequest(
        groupId: _group.id,
        userId: user.id,
        action: action,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingMembers = _pendingMembers
            .where((PublicUser member) => member.id != user.id)
            .toList();
        if (action == 'accept') {
          _members = <PublicUser>[..._members, user];
          _group = _group.copyWith(memberCount: _group.memberCount + 1);
        }
      });

      final String name = user.displayName.isNotEmpty
          ? user.displayName
          : user.username;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accept'
                ? '$name was added to the group.'
                : '$name request was declined.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Failed to review request: $error');
    } finally {
      if (mounted) {
        setState(() => _respondingJoinUserIds.remove(user.id));
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final GroupInfo group = _group;

    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.appHeading),
        title: Text(
          group.name,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.appHeading,
          ),
        ),
      ),
      floatingActionButton: _joined
          ? FloatingActionButton.extended(
              onPressed: _openCreatePost,
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_rounded),
              label: const Text('New post'),
            )
          : null,
      body: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: LoadingStateView(title: 'Loading group detail...'),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await _loadDetail();
                if (_joined) {
                  await _loadGroupPosts();
                }
              },
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildGroupHeader(group),
                  const SizedBox(height: 16),
                  _buildMetricsRow(group),
                  const SizedBox(height: 12),
                  _buildMembersBlock(),
                  if (_isOwner && _pendingMembers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildJoinRequestsBlock(),
                  ],
                  const SizedBox(height: 16),
                  _buildJoinButton(),
                  if (_joined) ...[
                    const SizedBox(height: 10),
                    _buildGroupChatButton(),
                  ],
                  const SizedBox(height: 24),
                  if (_joined) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Group posts',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: context.appHeading,
                            ),
                          ),
                        ),
                        if (_isPostsLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildPostsList(),
                    if (_postsHasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: _isLoadingMore
                              ? const CircularProgressIndicator()
                              : TextButton(
                                  onPressed: () =>
                                      _loadGroupPosts(loadMore: true),
                                  child: const Text('Load more'),
                                ),
                        ),
                      ),
                  ] else if (_members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: EmptyStateView(
                        icon: Icons.groups_rounded,
                        title: 'No members yet',
                        message: 'Be the first to join this group!',
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupHeader(GroupInfo group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [group.color, const Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: GroupAvatar(group: group, size: 46, isCircle: true),
                  ),
                  if (_isOwner)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Material(
                        color: const Color(0xFF33B8FF),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _isUploadingAvatar ? null : _changeGroupAvatar,
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: _isUploadingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(7),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${group.memberCount} members | ${group.minAge}-${group.maxAge} y/o',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            group.description,
            style: const TextStyle(
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2A4474),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Today mission: ${group.dailyMission}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A3D7C),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsRow(GroupInfo group) {
    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: 'Members',
            value: group.memberCount.toString(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(title: 'Min age', value: group.minAge.toString()),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(title: 'Max age', value: group.maxAge.toString()),
        ),
      ],
    );
  }

  Widget _buildMembersBlock() {
    final Iterable<PublicUser> visibleMembers = _isOwner
        ? _members
        : _members.take(12);

    return _Block(
      title: _isOwner ? 'Members' : 'Members preview',
      child: _members.isEmpty
          ? const Text('No members loaded yet.')
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleMembers.map((PublicUser user) {
                final String name = user.displayName.isNotEmpty
                    ? user.displayName
                    : user.username;
                final bool canRemove = _isOwner && user.id != _currentUserId;
                return _MemberChip(
                  name: name,
                  user: user,
                  canRemove: canRemove,
                  isRemoving: _removingMemberIds.contains(user.id),
                  onRemove: () => _removeMember(user),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildJoinRequestsBlock() {
    return _Block(
      title: 'Join requests',
      child: Column(
        children: [
          for (final PublicUser user in _pendingMembers) ...[
            _JoinRequestRow(
              user: user,
              isResponding: _respondingJoinUserIds.contains(user.id),
              onAccept: () => _reviewJoinRequest(user: user, action: 'accept'),
              onReject: () => _reviewJoinRequest(user: user, action: 'reject'),
            ),
            if (user != _pendingMembers.last) const Divider(height: 18),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupChatButton() {
    return ElevatedButton.icon(
      onPressed: _isOpeningChat ? null : _openGroupChat,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7A5CFF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _isOpeningChat
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.forum_rounded),
      label: const Text(
        'Open group chat',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildJoinButton() {
    if (_isOwner) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.verified_user_rounded),
        label: const Text(
          'You own this group',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    if (_isPending) {
      return OutlinedButton.icon(
        onPressed: null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: const Icon(Icons.hourglass_top_rounded),
        label: const Text(
          'Request pending',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _isSubmitting ? null : _toggleJoin,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF33B8FF),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: _isSubmitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(_joined ? Icons.exit_to_app_rounded : Icons.person_add_alt_1),
      label: Text(
        _joined ? 'Leave Group' : 'Request to Join',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPostsList() {
    if (_isPostsLoading && _posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.post_add_rounded, size: 40, color: Color(0xFF9AA7C7)),
            SizedBox(height: 8),
            Text(
              'No posts yet. Tap "New post" to share something!',
              style: TextStyle(color: Color(0xFF7A8BBF)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final FeedPost post in _posts) ...[
          _GroupPostCard(
            post: post,
            onTap: () => _openPost(post),
            onAuthorTap: () => _openPostAuthor(post),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: context.appHeading,
            ),
          ),
          Text(title, style: TextStyle(color: context.appMuted)),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.appHeading,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.name,
    required this.user,
    required this.canRemove,
    required this.isRemoving,
    required this.onRemove,
  });

  final String name;
  final PublicUser user;
  final bool canRemove;
  final bool isRemoving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: canRemove ? 4 : 10,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: context.appChip,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            avatarUrl: user.avatarUrl,
            initials: user.initials,
            radius: 12,
            backgroundColor: const Color(0xFFBEEBD0),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A3D7C),
              ),
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 2),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: isRemoving ? null : onRemove,
              child: SizedBox(
                width: 26,
                height: 26,
                child: isRemoving
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(
                        Icons.person_remove_rounded,
                        size: 16,
                        color: Color(0xFFE05A78),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JoinRequestRow extends StatelessWidget {
  const _JoinRequestRow({
    required this.user,
    required this.isResponding,
    required this.onAccept,
    required this.onReject,
  });

  final PublicUser user;
  final bool isResponding;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final String name = user.displayName.isNotEmpty
        ? user.displayName
        : user.username;

    return Row(
      children: [
        UserAvatar(
          avatarUrl: user.avatarUrl,
          initials: user.initials,
          radius: 18,
          backgroundColor: const Color(0xFFFFC5E6),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Decline',
          onPressed: isResponding ? null : onReject,
          icon: const Icon(Icons.close_rounded, color: Color(0xFFE05A78)),
        ),
        IconButton(
          tooltip: 'Accept',
          onPressed: isResponding ? null : onAccept,
          icon: isResponding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, color: Color(0xFF27AE60)),
        ),
      ],
    );
  }
}

class _GroupPostCard extends StatelessWidget {
  const _GroupPostCard({
    required this.post,
    required this.onTap,
    required this.onAuthorTap,
  });

  final FeedPost post;
  final VoidCallback onTap;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
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
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onAuthorTap,
                  child: UserAvatar(
                    avatarUrl: post.authorAvatarUrl,
                    initials: post.authorDisplayName.isNotEmpty
                        ? post.authorDisplayName.substring(0, 1).toUpperCase()
                        : (post.authorUsername.isNotEmpty
                              ? post.authorUsername
                                    .substring(0, 1)
                                    .toUpperCase()
                              : '?'),
                    radius: 16,
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
                          post.authorDisplayName.isNotEmpty
                              ? post.authorDisplayName
                              : post.authorUsername,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A3D7C),
                          ),
                        ),
                        if (DateTimeFormatter.format(post.createdAt).isNotEmpty)
                          Text(
                            DateTimeFormatter.format(post.createdAt),
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
              ],
            ),
            const SizedBox(height: 8),
            Text(
              post.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF1A3D7C)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  post.allowReactions
                      ? Icons.favorite_border_rounded
                      : Icons.lock_outline_rounded,
                  size: 14,
                  color: const Color(0xFF7A8BBF),
                ),
                const SizedBox(width: 4),
                Text(
                  post.allowReactions ? '${post.reactionCount}' : 'off',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7A8BBF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  post.allowComments
                      ? Icons.chat_bubble_outline
                      : Icons.lock_outline_rounded,
                  size: 14,
                  color: const Color(0xFF7A8BBF),
                ),
                const SizedBox(width: 4),
                Text(
                  post.allowComments ? '${post.commentCount}' : 'off',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7A8BBF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
