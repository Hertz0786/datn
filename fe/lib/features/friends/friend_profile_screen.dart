import 'package:flutter/material.dart';

import '../../core/models/friendship_status.dart';
import '../../core/models/feed_post.dart';
import '../../core/models/public_user.dart';
import '../../core/models/user_badge.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/badges_api.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/groups_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/users_api.dart';
import '../../core/session/auth_session.dart';
import '../../app/app_shell_navigator.dart';
import '../../app/scaffold_with_bottom_nav.dart';
import '../../shared/widgets/user_avatar.dart';
import '../chat/chat_detail_screen.dart';
import '../feed/friend_bookmarks_screen.dart';
import '../feed/friend_posts_screen.dart';
import '../groups/user_groups_screen.dart';
import '../profile/badge_gallery_screen.dart';
import 'user_friends_screen.dart';

class FriendProfileScreen extends StatefulWidget {
  const FriendProfileScreen({
    super.key,
    this.userId,
    required this.name,
    required this.age,
    required this.favoriteTopic,
    this.avatarLabel = 'B1',
    this.avatarColor = const Color(0xFFBEEAFF),
    this.avatarUrl = '',
  });

  final String? userId;
  final String name;
  final int age;
  final String favoriteTopic;
  final String avatarLabel;
  final Color avatarColor;
  final String avatarUrl;

  @override
  State<FriendProfileScreen> createState() => _FriendProfileScreenState();
}

class _FriendProfileScreenState extends State<FriendProfileScreen> {
  FriendshipStatus? _friendshipStatus;
  bool _isLoadingStatus = false;
  bool _isLoadingProfileStats = false;
  bool _isLoadingMutualFriends = false;
  bool _isSubmittingRequest = false;
  bool _isOpeningChat = false;
  int _friendCount = 0;
  int _groupCount = 0;
  int _badgeCount = 0;
  PublicUser? _profileUser;
  List<PublicUser> _mutualFriends = const <PublicUser>[];

  bool _isLoadingPosts = false;
  bool _hasPostsError = false;
  bool _isLoadingBookmarks = false;
  bool _hasBookmarksError = false;
  List<FeedPost> _friendPosts = const <FeedPost>[];
  List<FeedPost> _friendBookmarks = const <FeedPost>[];

  String get _targetUserId => widget.userId?.trim() ?? '';
  bool get _hasRealUser => _targetUserId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // If the caller navigated here with the current user's id (a post
    // author or commenter who is actually me), the friend-screen layout
    // is wrong: it has no friendship controls and hides my own actions.
    // Pop back to the root (AppShell) and switch to the Profile tab so
    // the taskbar stays visible. A single `pop()` is not enough when
    // the caller is several pushes deep (e.g. notification → post
    // detail → friend profile), so we walk all the way back to the
    // first route before switching tabs.
    final String myId = (AuthSession.instance.user?['id'] ?? '').toString();
    if (_targetUserId.isNotEmpty && myId.isNotEmpty && _targetUserId == myId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final NavigatorState navigator = Navigator.of(context);
        navigator.popUntil((route) => route.isFirst);
        AppShellNavigator.instance.switchToProfile();
      });
      return;
    }
    _loadProfileUser();
    _loadFriendshipStatus();
    _loadProfileStats();
    _loadMutualFriends();
    _loadFriendPosts();
    _loadFriendBookmarks();
  }

  String get _displayName {
    final String value = (_profileUser?.displayName ?? widget.name).trim();
    return value.isEmpty ? 'Friend' : value;
  }

  int get _displayAge => _profileUser?.age ?? widget.age;

  String get _favoriteTopic {
    final List<String> topics = _profileUser?.favoriteTopics ?? const [];
    if (topics.isNotEmpty) {
      return topics.first;
    }
    return widget.favoriteTopic.trim().isEmpty ? 'Music' : widget.favoriteTopic;
  }

  String get _avatarUrl {
    final String value = (_profileUser?.avatarUrl ?? widget.avatarUrl).trim();
    return value;
  }

  String get _avatarLabel {
    final String value = _profileUser?.initials ?? widget.avatarLabel;
    return value.trim().isEmpty ? 'FR' : value;
  }

  Future<void> _loadProfileUser() async {
    if (!_hasRealUser) {
      return;
    }

    try {
      final PublicUser user = await UsersApi.instance.getById(_targetUserId);
      if (!mounted) {
        return;
      }
      setState(() => _profileUser = user);
    } catch (_) {
      // Keep the lightweight data passed by the caller if profile fetch fails.
    }
  }

  Future<void> _loadProfileStats() async {
    if (!_hasRealUser) {
      return;
    }

    setState(() => _isLoadingProfileStats = true);

    try {
      final List<dynamic> result = await Future.wait<dynamic>(<Future<dynamic>>[
        FriendsApi.instance.listUserFriends(userId: _targetUserId, limit: 50),
        GroupsApi.instance.listUserGroups(userId: _targetUserId, limit: 50),
        BadgesApi.instance.userBadges(_targetUserId),
      ]);

      final FriendsPage friendsPage = result[0] as FriendsPage;
      final GroupsPage groupsPage = result[1] as GroupsPage;
      final List<UserBadge> badges = result[2] as List<UserBadge>;

      if (!mounted) {
        return;
      }
      setState(() {
        _friendCount = friendsPage.items.length;
        _groupCount = groupsPage.items.length;
        _badgeCount = badges.where((UserBadge badge) => badge.earned).length;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Failed to load profile details: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfileStats = false);
      }
    }
  }

  Future<void> _loadMutualFriends({bool showLoading = true}) async {
    if (!_hasRealUser) {
      return;
    }

    if (showLoading) {
      setState(() => _isLoadingMutualFriends = true);
    }

    try {
      final List<PublicUser> items = await FriendsApi.instance.mutualFriends(
        userId: _targetUserId,
        limit: 12,
      );
      if (!mounted) {
        return;
      }
      setState(() => _mutualFriends = items);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Failed to load mutual friends: $error');
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoadingMutualFriends = false);
      }
    }
  }

  Future<void> _loadFriendPosts() async {
    if (!_hasRealUser) {
      return;
    }

    setState(() {
      _isLoadingPosts = true;
      _hasPostsError = false;
    });

    try {
      final FeedPage page = await PostsApi.instance.userPosts(_targetUserId, limit: 3);
      if (!mounted) return;
      setState(() => _friendPosts = page.items);
    } on ApiException catch (error) {
      // 401/403 means the visitor is not allowed to see this user's
      // posts (or isn't authenticated). Treat it as "nothing to show"
      // instead of an error — the profile may still be reachable for
      // public information.
      if (!mounted) return;
      if (error.statusCode == 401 || error.statusCode == 403) {
        setState(() => _friendPosts = const <FeedPost>[]);
      } else {
        setState(() => _hasPostsError = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasPostsError = true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingPosts = false);
      }
    }
  }

  Future<void> _loadFriendBookmarks() async {
    if (!_hasRealUser) {
      return;
    }

    setState(() {
      _isLoadingBookmarks = true;
      _hasBookmarksError = false;
    });

    try {
      final FeedPage page = await PostsApi.instance.userBookmarks(_targetUserId, limit: 6);
      if (!mounted) return;
      setState(() => _friendBookmarks = page.items);
    } on ApiException catch (error) {
      // Bookmarks are private — 401/403 just means "no bookmarks to
      // show" for this viewer. Surface as empty, not as an error.
      if (!mounted) return;
      if (error.statusCode == 401 || error.statusCode == 403) {
        setState(() => _friendBookmarks = const <FeedPost>[]);
      } else {
        setState(() => _hasBookmarksError = true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasBookmarksError = true);
    } finally {
      if (mounted) {
        setState(() => _isLoadingBookmarks = false);
      }
    }
  }

  Future<void> _loadFriendshipStatus({bool showLoading = true}) async {
    if (!_hasRealUser) {
      return;
    }

    if (showLoading) {
      setState(() => _isLoadingStatus = true);
    }

    try {
      final FriendshipStatus status = await FriendsApi.instance
          .friendshipStatus(_targetUserId);
      if (!mounted) {
        return;
      }
      setState(() => _friendshipStatus = status);
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
        SnackBar(content: Text('Failed to load friendship status: $error')),
      );
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  Future<void> _sendFriendRequest() async {
    if (!_hasRealUser ||
        _isLoadingStatus ||
        _isSubmittingRequest ||
        _friendshipStatus?.isSelf == true ||
        _friendshipStatus?.isFriend == true ||
        _friendshipStatus?.isOutgoingPending == true) {
      return;
    }

    setState(() => _isSubmittingRequest = true);

    try {
      if (_friendshipStatus?.isIncomingPending == true) {
        final String requestId = _friendshipStatus?.request?.id ?? '';
        if (requestId.isEmpty) {
          await _loadFriendshipStatus(showLoading: false);
          return;
        }
        await FriendsApi.instance.updateRequest(
          requestId: requestId,
          action: 'accept',
        );
        _showSnackBar('Friend request accepted.');
      } else {
        await FriendsApi.instance.sendRequest(_targetUserId);
        _showSnackBar('Friend request sent.');
      }

      await _loadFriendshipStatus(showLoading: false);
      await Future.wait<void>([
        _loadProfileStats(),
        _loadMutualFriends(showLoading: false),
      ]);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      final String msg = error.message.toLowerCase();
      if (msg.contains('already')) {
        _showSnackBar(
          _friendshipStatus?.isIncomingPending == true
              ? 'Friend request already accepted.'
              : 'Friend request already processed.',
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      await _loadFriendshipStatus(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Friend request failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequest = false);
      }
    }
  }

  Future<void> _handleFriendAction() async {
    if (_friendshipStatus?.isFriend == true) {
      await _confirmRemoveFriend();
      return;
    }
    await _sendFriendRequest();
  }

  Future<void> _confirmRemoveFriend() async {
    if (!_hasRealUser || _isSubmittingRequest || _isLoadingStatus) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          'You and $_displayName will no longer be friends. You can send a friend request again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.person_remove_rounded),
            label: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isSubmittingRequest = true);

    try {
      await FriendsApi.instance.removeFriend(_targetUserId);
      if (!mounted) {
        return;
      }
      _showSnackBar('Friend removed.');
      await Future.wait<void>([
        _loadFriendshipStatus(showLoading: false),
        _loadProfileStats(),
        _loadMutualFriends(showLoading: false),
      ]);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar(error.message);
      await _loadFriendshipStatus(showLoading: false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Remove friend failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isSubmittingRequest = false);
      }
    }
  }

  Future<void> _openChat() async {
    if (!_hasRealUser || _isOpeningChat || _friendshipStatus?.isSelf == true) {
      return;
    }

    setState(() => _isOpeningChat = true);

    try {
      final chat = await ChatsApi.instance.createDirectChat(_targetUserId);
      if (!mounted) {
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chat.id,
            title: _displayName,
            avatarUrl: _avatarUrl,
            avatarLabel: _avatarLabel,
            members: chat.memberUsers,
          ),
        ),
      );
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
      ).showSnackBar(SnackBar(content: Text('Open chat failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isOpeningChat = false);
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _actionLabel {
    if (!_hasRealUser) {
      return 'Unavailable';
    }
    if (_isLoadingStatus) {
      return 'Checking...';
    }
    if (_friendshipStatus?.isSelf == true) {
      return 'Your profile';
    }
    if (_friendshipStatus?.isFriend == true) {
      return 'Friends';
    }
    if (_friendshipStatus?.isIncomingPending == true) {
      return 'Accept request';
    }
    if (_friendshipStatus?.isOutgoingPending == true) {
      return 'Request sent';
    }
    return 'Send request';
  }

  IconData get _actionIcon {
    if (_isSubmittingRequest) {
      return Icons.hourglass_empty_rounded;
    }
    if (_friendshipStatus?.isFriend == true) {
      return Icons.check_circle_rounded;
    }
    if (_friendshipStatus?.isOutgoingPending == true) {
      return Icons.schedule_rounded;
    }
    if (_friendshipStatus?.isIncomingPending == true) {
      return Icons.person_add_alt_1_rounded;
    }
    return Icons.person_add_alt_1;
  }

  bool get _canPressAction {
    return _hasRealUser &&
        !_isLoadingStatus &&
        !_isSubmittingRequest &&
        _friendshipStatus?.isSelf != true &&
        _friendshipStatus?.isOutgoingPending != true;
  }

  bool get _canOpenChat {
    return _hasRealUser &&
        !_isLoadingStatus &&
        !_isOpeningChat &&
        _friendshipStatus?.isFriend == true;
  }

  String _statValue(int value) {
    return _isLoadingProfileStats ? '...' : '$value';
  }

  void _openFriends() {
    if (!_hasRealUser) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UserFriendsScreen(userId: _targetUserId, displayName: _displayName),
      ),
    );
  }

  void _openGroups() {
    if (!_hasRealUser) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UserGroupsScreen(userId: _targetUserId, displayName: _displayName),
      ),
    );
  }

  void _openBadges() {
    if (!_hasRealUser) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BadgeGalleryScreen(
          userId: _targetUserId,
          title: '$_displayName\'s Badges',
        ),
      ),
    );
  }

  void _openMutualFriend(PublicUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PushedScreenShell(
          child: FriendProfileScreen(
            userId: user.id,
            name: user.displayName,
            age: user.age,
            favoriteTopic: user.favoriteTopics.isEmpty
                ? 'Music'
                : user.favoriteTopics.first,
            avatarLabel: user.initials,
            avatarUrl: user.avatarUrl,
          ),
        ),
      ),
    );
  }

  Widget _buildMutualFriendsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mutual friends',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingMutualFriends)
          const SizedBox(
            height: 92,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_mutualFriends.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No mutual friends yet.',
              style: TextStyle(
                color: Color(0xFF5A74A6),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _mutualFriends.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final PublicUser user = _mutualFriends[index];
                return InkWell(
                  onTap: () => _openMutualFriend(user),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        UserAvatar(
                          avatarUrl: user.avatarUrl,
                          initials: user.initials,
                          radius: 24,
                          backgroundColor: index.isEven
                              ? const Color(0xFFFFE59E)
                              : const Color(0xFFBEEBD0),
                          lastActiveAt: user.lastActiveAt,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          user.displayName.isEmpty
                              ? user.username
                              : user.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A3D7C),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFriendPostsSection() {
    return _FriendPostSection(
      posts: _friendPosts,
      isLoading: _isLoadingPosts,
      hasError: _hasPostsError,
      displayName: _displayName,
      onTap: _friendPosts.isNotEmpty ? _openAllFriendPosts : () {},
    );
  }

  Widget _buildFriendBookmarksSection() {
    if (_friendBookmarks.isEmpty && !_isLoadingBookmarks && !_hasBookmarksError) {
      return const SizedBox.shrink();
    }
    return _FriendBookmarksSection(
      bookmarks: _friendBookmarks,
      isLoading: _isLoadingBookmarks,
      hasError: _hasBookmarksError,
      displayName: _displayName,
      onTap: _friendBookmarks.isNotEmpty ? _openAllFriendBookmarks : () {},
    );
  }

  void _openAllFriendPosts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendPostsScreen(
          userId: _targetUserId,
          displayName: _displayName,
        ),
      ),
    );
  }

  void _openAllFriendBookmarks() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendBookmarksScreen(
          userId: _targetUserId,
          displayName: _displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'Friend Profile',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9BE7FF), Color(0xFFDCC8FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                UserAvatar(
                  avatarUrl: _avatarUrl,
                  initials: _avatarLabel,
                  radius: 38,
                  backgroundColor: widget.avatarColor,
                ),
                const SizedBox(height: 10),
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Age $_displayAge | Loves $_favoriteTopic',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2B4F84),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _canPressAction ? _handleFriendAction : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF33B8FF),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFDCE8FF),
                          disabledForegroundColor: const Color(0xFF5A74A6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isSubmittingRequest
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(_actionIcon),
                        label: Text(_actionLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _canOpenChat ? _openChat : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1A3D7C),
                          side: const BorderSide(color: Color(0xFFBEEAFF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isOpeningChat
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Message'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'Friends',
                  value: _statValue(_friendCount),
                  onTap: _openFriends,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  title: 'Groups',
                  value: _statValue(_groupCount),
                  onTap: _openGroups,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatCard(
                  title: 'Badges',
                  value: _statValue(_badgeCount),
                  onTap: _openBadges,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_displayName likes ${_favoriteTopic.toLowerCase()}, bright stickers, and fun group challenges.',
                  style: const TextStyle(color: Color(0xFF4E6696), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildMutualFriendsSection(),
          const SizedBox(height: 16),
          _buildFriendPostsSection(),
          const SizedBox(height: 16),
          _buildFriendBookmarksSection(),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Color(0xFF1A3D7C),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF5A74A6)),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: Color(0xFF7A8BBF),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendPostSection extends StatelessWidget {
  const _FriendPostSection({
    required this.posts,
    required this.isLoading,
    required this.hasError,
    required this.displayName,
    required this.onTap,
  });

  final List<FeedPost> posts;
  final bool isLoading;
  final bool hasError;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$displayName\'s posts',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A3D7C),
                ),
              ),
            ),
            if (posts.isNotEmpty)
              TextButton(
                onPressed: onTap,
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoading)
          const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (hasError)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Could not load posts.',
              style: TextStyle(color: Color(0xFFA01843)),
            ),
          )
        else if (posts.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No posts yet.',
              style: TextStyle(color: Color(0xFF5A74A6)),
            ),
          )
        else
          Column(
            children: posts.take(3).map((post) {
              final String preview = post.content.length > 100
                  ? '${post.content.substring(0, 100)}...'
                  : post.content;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              preview.isEmpty ? '(post)' : preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.3),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (post.mediaUrls.isNotEmpty) ...[
                                  const Icon(Icons.image_outlined,
                                      size: 13, color: Color(0xFF7A8BBF)),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${post.mediaUrls.length}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF7A8BBF)),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                const Icon(Icons.favorite_rounded,
                                    size: 13, color: Color(0xFFFF5A9E)),
                                const SizedBox(width: 2),
                                Text(
                                  '${post.reactionCount}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7A8BBF)),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.comment_outlined,
                                    size: 13, color: Color(0xFF7A8BBF)),
                                const SizedBox(width: 2),
                                Text(
                                  '${post.commentCount}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7A8BBF)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (post.mediaUrls.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              post.mediaUrls.first,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const SizedBox(width: 56, height: 56),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class _FriendBookmarksSection extends StatelessWidget {
  const _FriendBookmarksSection({
    required this.bookmarks,
    required this.isLoading,
    required this.hasError,
    required this.displayName,
    required this.onTap,
  });

  final List<FeedPost> bookmarks;
  final bool isLoading;
  final bool hasError;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$displayName\'s bookmarks',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A3D7C),
                ),
              ),
            ),
            if (bookmarks.isNotEmpty)
              TextButton(
                onPressed: onTap,
                child: const Text('See all'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (isLoading)
          const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (hasError)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0F8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Could not load bookmarks.',
              style: TextStyle(color: Color(0xFFA01843)),
            ),
          )
        else if (bookmarks.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'No bookmarks yet.',
              style: TextStyle(color: Color(0xFF5A74A6)),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bookmarks.take(6).length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final post = bookmarks[index];
                return InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorDisplayName.isNotEmpty
                              ? '@${post.authorDisplayName}'
                              : '@${post.authorUsername}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A3D7C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            post.content.isEmpty
                                ? '(post)'
                                : post.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF5A74A6),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.bookmark,
                                size: 12, color: Color(0xFFFF5A9E)),
                            const SizedBox(width: 2),
                            Text(
                              '${post.reactionCount}',
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF7A8BBF)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

