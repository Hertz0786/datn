import 'package:flutter/material.dart';

import '../core/models/app_notification.dart';
import '../core/models/chat_message.dart';
import '../core/services/notifications_api.dart';
import '../core/services/realtime_service.dart';
import '../core/session/auth_session.dart';
import 'app_shell_navigator.dart';
import '../features/assistant/llm_assistant_button.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/feed/create_post_screen.dart';
import '../features/feed/home_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/search/search_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _unreadNotifications = 0;
  final int _notificationsRefreshSignal = 0;
  int _unreadChatMessages = 0;

  @override
  void initState() {
    super.initState();
    AppShellNavigator.instance.attach(_switchToTab);
    RealtimeService.instance.on(
      'notification:created',
      _handleNotificationCreated,
    );
    RealtimeService.instance.on('chat:message', _handleChatMessage);
    RealtimeService.instance.on(
      'post:moderation_decided',
      _handlePostModerationDecided,
    );
    RealtimeService.instance.on(
      'post:pending_media_review',
      _handlePostPendingMediaReview,
    );
    _loadUnreadNotifications();
  }

  @override
  void dispose() {
    AppShellNavigator.instance.detach();
    RealtimeService.instance.off(
      'notification:created',
      _handleNotificationCreated,
    );
    RealtimeService.instance.off('chat:message', _handleChatMessage);
    RealtimeService.instance.off(
      'post:moderation_decided',
      _handlePostModerationDecided,
    );
    RealtimeService.instance.off(
      'post:pending_media_review',
      _handlePostPendingMediaReview,
    );
    super.dispose();
  }

  void _switchToTab(int tabIndex) {
    if (!mounted) {
      return;
    }
    setState(() {
      _index = tabIndex;
      if (tabIndex == 3) {
        _unreadChatMessages = 0;
      }
    });
  }

  Future<void> _loadUnreadNotifications() async {
    try {
      final List<AppNotification> items = await NotificationsApi.instance
          .listNotifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _unreadNotifications = items.where((item) => !item.isRead).length;
      });
    } catch (_) {}
  }

  void _handleNotificationCreated(dynamic payload) {
    if (!mounted) {
      return;
    }
    setState(() {
      _unreadNotifications += 1;
    });

    if (payload is! Map) {
      return;
    }

    final dynamic rawNotification = payload['notification'];
    if (rawNotification is! Map) {
      return;
    }

    final AppNotification notification = AppNotification.fromJson(
      Map<String, dynamic>.from(rawNotification),
    );
    if (notification.type == 'FRIEND_REQUEST_RECEIVED') {
      // User responds to friend requests from the notifications tab.
    }
  }

  void _handleChatMessage(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final dynamic rawMessage = payload['message'];
    if (rawMessage is! Map) {
      return;
    }

    final ChatMessage message = ChatMessage.fromJson(
      Map<String, dynamic>.from(rawMessage),
    );
    final String myId = (AuthSession.instance.user?['id'] ?? '').toString();
    if (message.senderId == myId || _index == 3 || !mounted) {
      return;
    }

    setState(() {
      _unreadChatMessages = _unreadChatMessages >= 99
          ? 99
          : _unreadChatMessages + 1;
    });
  }

  void _handlePostPendingMediaReview(dynamic payload) {
    // Fired the moment the user publishes a post that the AI flagged
    // as sensitive. We surface an immediate SnackBar so they know
    // it has been held back and a moderator will look at it.
    if (!mounted || payload is! Map) {
      return;
    }
    final String message =
        'Bài đăng của bạn đã được gửi. Hình ảnh đang chờ admin duyệt, bạn sẽ nhận được thông báo khi có kết quả.';
    _showGlobalSnack(message, color: const Color(0xFF874800));
  }

  void _handlePostModerationDecided(dynamic payload) {
    // The admin has approved or deleted a previously-flagged post.
    // We surface the verdict (in Vietnamese) so the user knows what
    // happened without having to pull-to-refresh the feed.
    if (!mounted || payload is! Map) {
      return;
    }
    final String status = (payload['status'] ?? '').toString().toUpperCase();
    String message = (payload['message'] ?? '').toString();
    if (message.isEmpty) {
      if (status == 'PUBLISHED') {
        message = 'Bài đăng của bạn đã được admin duyệt và hiển thị trên bảng tin.';
      } else if (status == 'DELETED') {
        message = 'Bài đăng của bạn đã bị xóa vì chứa hình ảnh không phù hợp.';
      } else {
        message = 'Bài đăng của bạn đã được cập nhật trạng thái.';
      }
    }
    final bool approved = status == 'PUBLISHED';
    _showGlobalSnack(
      message,
      color: approved ? const Color(0xFF0A7550) : const Color(0xFFA01843),
    );
  }

  void _showGlobalSnack(String message, {required Color color}) {
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _setUnreadNotifications(int count) {
    if (_unreadNotifications == count) {
      return;
    }
    setState(() {
      _unreadNotifications = count;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          refreshSignal: _notificationsRefreshSignal,
          onUnreadCountChanged: _setUnreadNotifications,
        ),
      ),
    );
    await _loadUnreadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const HomeScreen(),
      const SearchScreen(),
      const CreatePostScreen(),
      const ChatListScreen(),
      const ProfileScreen(),
    ];

    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double navBarHeight = kBottomNavigationBarHeight;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _index, children: screens),
          Positioned(
            right: 64,
            top: MediaQuery.paddingOf(context).top + 8,
            child: _TopAlertButton(
              count: _unreadNotifications,
              onTap: _openNotifications,
            ),
          ),
          Positioned(
            right: 16,
            bottom: bottomInset + navBarHeight + 12,
            child: const LlmAssistantButton(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (value) {
            setState(() {
              _index = value;
              if (value == 3) {
                _unreadChatMessages = 0;
              }
            });
          },
          selectedItemColor: const Color(0xFF33B8FF),
          unselectedItemColor: const Color(0xFF9AA7C7),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Search',
            ),
            const BottomNavigationBarItem(icon: _PostNavIcon(), label: 'Post'),
            BottomNavigationBarItem(
              icon: _ChatNavIcon(unreadCount: _unreadChatMessages),
              label: 'Chat',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _TopAlertButton extends StatelessWidget {
  const _TopAlertButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: _BadgeIcon(
            icon: Icons.notifications_rounded,
            count: count,
            dotOnly: false,
          ),
        ),
      ),
    );
  }
}

class _PostNavIcon extends StatelessWidget {
  const _PostNavIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9AD5), Color(0xFF7A5CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF9AD5).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
    );
  }
}

class _ChatNavIcon extends StatelessWidget {
  const _ChatNavIcon({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return _BadgeIcon(
      icon: Icons.chat_bubble_rounded,
      count: unreadCount,
      dotOnly: false,
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.count,
    required this.dotOnly,
  });

  final IconData icon;
  final int count;
  final bool dotOnly;

  @override
  Widget build(BuildContext context) {
    final String countLabel = count > 99 ? '99+' : '$count';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            right: dotOnly ? -3 : -8,
            top: dotOnly ? -3 : -6,
            child: Container(
              constraints: BoxConstraints(
                minWidth: dotOnly ? 9 : 18,
                minHeight: dotOnly ? 9 : 16,
              ),
              padding: dotOnly
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A9E),
                shape: dotOnly ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: dotOnly ? null : BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: dotOnly
                  ? const SizedBox.shrink()
                  : Text(
                      countLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}
