import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/friend_request_item.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/realtime_service.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/user_avatar.dart';
import '../chat/chat_detail_screen.dart';
import 'friend_profile_screen.dart';

class FriendListScreen extends StatefulWidget {
  const FriendListScreen({super.key, this.selectForChat = false});

  final bool selectForChat;

  @override
  State<FriendListScreen> createState() => _FriendListScreenState();
}

class _FriendListScreenState extends State<FriendListScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _startingChatUserId;
  String? _nextCursor;
  List<FriendRequestItem> _incoming = const <FriendRequestItem>[];
  List<PublicUser> _friends = const <PublicUser>[];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.on(
      'notification:created',
      _handleNotificationCreated,
    );
    _scrollController.addListener(_onScroll);
    _loadData();
    // Refresh the friend list every minute so the online dot reflects
    // the latest server state. We keep it light: no spinner.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) {
        if (!mounted) {
          return;
        }
        _loadFriends();
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    final double extent = _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (extent < 300) {
      _loadMore();
    }
  }

  void _handleNotificationCreated(dynamic payload) {
    if (widget.selectForChat || payload is! Map) {
      return;
    }

    final dynamic rawNotification = payload['notification'];
    if (rawNotification is! Map) {
      return;
    }

    final String type = (rawNotification['type'] ?? '').toString();
    if (type == 'FRIEND_REQUEST_RECEIVED') {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _nextCursor = null;
    });

    try {
      final List<dynamic> result = await Future.wait<dynamic>(<Future<dynamic>>[
        FriendsApi.instance.incomingRequests(),
        FriendsApi.instance.listFriends(),
      ]);

      final FriendRequestsPage requestsPage =
          result[0] as FriendRequestsPage;
      final FriendsPage friendsPage = result[1] as FriendsPage;

      if (!mounted) {
        return;
      }

      setState(() {
        _incoming = requestsPage.items;
        _friends = friendsPage.items;
        _hasMore = friendsPage.hasMore;
        _nextCursor = friendsPage.nextBefore;
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
      ).showSnackBar(SnackBar(content: Text('Failed to load friends: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Silent re-fetch of just the friend list. Used by the periodic
  /// refresh so we can keep the online dot fresh without showing a
  /// spinner or resetting the user's scroll position.
  Future<void> _loadFriends() async {
    try {
      final FriendsPage page = await FriendsApi.instance.listFriends();
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } catch (_) {
      // Silent failure — we only lose one tick of online updates.
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final FriendsPage page = await FriendsApi.instance.listFriends(
        before: _nextCursor,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final List<PublicUser> next = List<PublicUser>.from(_friends);
        for (final PublicUser user in page.items) {
          if (!next.any((item) => item.id == user.id)) {
            next.add(user);
          }
        }
        _friends = next;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } on ApiException {
      // Silent failure for background pagination.
    } catch (_) {
      // Silent failure for background pagination.
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _acceptRequest(FriendRequestItem request) async {
    final String requesterName = _resolveSender(request).displayName.isNotEmpty
        ? _resolveSender(request).displayName
        : 'Friend request';
    try {
      await FriendsApi.instance.updateRequest(
        requestId: request.id,
        action: 'accept',
      );
      if (!mounted) {
        return;
      }
      _showSnack('You and $requesterName are now friends.');
    } on ApiException catch (error) {
      if (!mounted) {
        await _loadData();
        return;
      }
      final String msg = error.message.toLowerCase();
      if (msg.contains('already')) {
        _showSnack('Friend request already accepted.');
      } else {
        _showSnack(error.message);
      }
      await _loadData();
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Accept request failed: $error');
      return;
    }
    await _loadData();
  }

  Future<void> _rejectRequest(FriendRequestItem request) async {
    final String requesterName = _resolveSender(request).displayName.isNotEmpty
        ? _resolveSender(request).displayName
        : 'Friend request';
    try {
      await FriendsApi.instance.updateRequest(
        requestId: request.id,
        action: 'reject',
      );
      if (!mounted) {
        return;
      }
      _showSnack('Friend request from $requesterName declined.');
    } on ApiException catch (error) {
      if (!mounted) {
        await _loadData();
        return;
      }
      final String msg = error.message.toLowerCase();
      if (msg.contains('already')) {
        _showSnack('Friend request already processed.');
      } else {
        _showSnack(error.message);
      }
      await _loadData();
      return;
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Reject request failed: $error');
      return;
    }
    await _loadData();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openChat(PublicUser user) async {
    if (_startingChatUserId != null) {
      return;
    }

    setState(() => _startingChatUserId = user.id);

    try {
      final chat = await ChatsApi.instance.createDirectChat(user.id);

      if (!mounted) {
        return;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: chat.id,
            title: user.displayName,
            avatarUrl: user.avatarUrl,
            avatarLabel: user.initials,
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
        setState(() => _startingChatUserId = null);
      }
    }
  }

  PublicUser _resolveSender(FriendRequestItem request) {
    final dynamic raw = request.sender;
    if (raw is Map<String, dynamic>) {
      try {
        return PublicUser.fromJson(raw);
      } catch (_) {
        // Fall through to fetching.
      }
    }
    // Backwards-compat: older responses do not embed the sender payload.
    return PublicUser(
      id: request.senderId,
      displayName: '',
      username: '',
      age: 0,
      role: 'CHILD',
      avatarUrl: '',
      bio: '',
      favoriteTopics: const <String>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(
          widget.selectForChat ? 'Choose a friend to chat' : 'Friends',
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
        onRefresh: _loadData,
        child: _isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  LoadingStateView(title: 'Loading friends...'),
                ],
              )
            : ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (!widget.selectForChat) ...[
                    const Text(
                      'Friend requests',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_incoming.isEmpty)
                      const EmptyStateView(
                        icon: Icons.person_add_disabled_rounded,
                        title: 'No friend requests',
                        message: 'New friend requests will appear here.',
                      )
                    else
                      ..._incoming.map((FriendRequestItem request) {
                        final PublicUser sender = _resolveSender(request);
                        return _RequestTile(
                          name: sender.displayName.isNotEmpty
                              ? sender.displayName
                              : 'Friend request',
                          age: sender.age,
                          avatarUrl: sender.avatarUrl,
                          avatarLabel: sender.initials,
                          onView: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PushedScreenShell(
                                  child: FriendProfileScreen(
                                    userId: sender.id,
                                    name: sender.displayName,
                                    age: sender.age,
                                    favoriteTopic: sender
                                            .favoriteTopics.isEmpty
                                        ? 'Drawing'
                                        : sender.favoriteTopics.first,
                                    avatarLabel: sender.initials,
                                    avatarUrl: sender.avatarUrl,
                                  ),
                                ),
                              ),
                            );
                          },
                          onAccept: () => _acceptRequest(request),
                          onReject: () => _rejectRequest(request),
                        );
                      }),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    widget.selectForChat ? 'Choose a friend' : 'My friends',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_friends.isEmpty)
                    EmptyStateView(
                      icon: Icons.group_outlined,
                      title: 'No friends yet',
                      message: widget.selectForChat
                          ? 'Add friends before starting a chat.'
                          : 'Add friends to start chatting.',
                    )
                  else
                    ..._friends.map(
                      (PublicUser user) => _FriendTile(
                        name: user.displayName,
                        age: user.age,
                        avatar: user.initials,
                        avatarUrl: user.avatarUrl,
                        isLoading: _startingChatUserId == user.id,
                        lastActiveAt: user.lastActiveAt,
                        trailingIcon: widget.selectForChat
                            ? Icons.chat_bubble_outline_rounded
                            : Icons.chevron_right_rounded,
                        onTap: () {
                          if (widget.selectForChat) {
                            _openChat(user);
                            return;
                          }

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
                        },
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

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.name,
    required this.age,
    required this.avatarUrl,
    required this.avatarLabel,
    required this.onView,
    required this.onAccept,
    required this.onReject,
  });

  final String name;
  final int age;
  final String avatarUrl;
  final String avatarLabel;
  final VoidCallback onView;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onView,
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
              avatarUrl: avatarUrl,
              initials: avatarLabel,
              radius: 22,
              backgroundColor: const Color(0xFFFFE59E),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Age $age'),
                ],
              ),
            ),
            Column(
              children: [
                ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF33B8FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Accept'),
                ),
                TextButton(onPressed: onReject, child: const Text('Decline')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.name,
    required this.age,
    required this.avatar,
    required this.avatarUrl,
    required this.onTap,
    required this.trailingIcon,
    this.isLoading = false,
    this.lastActiveAt,
  });

  final String name;
  final int age;
  final String avatar;
  final String avatarUrl;
  final VoidCallback onTap;
  final IconData trailingIcon;
  final bool isLoading;
  final DateTime? lastActiveAt;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: avatarUrl,
              initials: avatar,
              radius: 22,
              backgroundColor: const Color(0xFFBEEAFF),
              lastActiveAt: lastActiveAt,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text('Age $age'),
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
              Icon(trailingIcon),
          ],
        ),
      ),
    );
  }
}
