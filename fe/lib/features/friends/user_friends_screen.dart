import 'package:flutter/material.dart';

import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/friends_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/user_avatar.dart';
import 'friend_profile_screen.dart';

class UserFriendsScreen extends StatefulWidget {
  const UserFriendsScreen({
    super.key,
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  @override
  State<UserFriendsScreen> createState() => _UserFriendsScreenState();
}

class _UserFriendsScreenState extends State<UserFriendsScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  List<PublicUser> _friends = const <PublicUser>[];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 260) {
      _loadMore();
    }
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final FriendsPage page = await FriendsApi.instance.listUserFriends(
        userId: widget.userId,
        limit: 30,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = page.items;
        _nextCursor = page.nextBefore;
        _hasMore = page.hasMore;
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
      _showError('Failed to load friends: $error');
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) {
      return;
    }

    setState(() => _isLoadingMore = true);

    try {
      final FriendsPage page = await FriendsApi.instance.listUserFriends(
        userId: widget.userId,
        limit: 30,
        before: _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = <PublicUser>[..._friends, ...page.items];
        _nextCursor = page.nextBefore;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      // Pagination failures are intentionally quiet; pull-to-refresh can retry.
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _openFriend(PublicUser user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
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
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(
          '${widget.displayName}\'s Friends',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(showLoading: false),
        child: _isLoading
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [LoadingStateView(title: 'Loading friends...')],
              )
            : ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  if (_friends.isEmpty)
                    EmptyStateView(
                      icon: Icons.group_outlined,
                      title: 'No friends yet',
                      message:
                          '${widget.displayName} has not added friends yet.',
                    )
                  else
                    ..._friends.map(
                      (PublicUser user) => _FriendRow(
                        user: user,
                        onTap: () => _openFriend(user),
                      ),
                    ),
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.user, required this.onTap});

  final PublicUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String topic = user.favoriteTopics.isEmpty
        ? 'No favorite topic yet'
        : 'Loves ${user.favoriteTopics.first}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
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
            UserAvatar(
              avatarUrl: user.avatarUrl,
              initials: user.initials,
              radius: 22,
              backgroundColor: const Color(0xFFFFE59E),
              lastActiveAt: user.lastActiveAt,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Age ${user.age} | $topic',
                    style: const TextStyle(color: Color(0xFF5A74A6)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF7A8BBF)),
          ],
        ),
      ),
    );
  }
}
