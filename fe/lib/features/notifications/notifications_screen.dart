import 'package:flutter/material.dart';

import '../../core/models/app_notification.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/groups_api.dart';
import '../../core/services/notifications_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.refreshSignal = 0,
    this.onUnreadCountChanged,
  });

  final int refreshSignal;
  final ValueChanged<int>? onUnreadCountChanged;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  String? _respondingRequestId;
  List<AppNotification> _notifications = const <AppNotification>[];

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.on(
      'notification:created',
      _handleNotificationCreated,
    );
    _loadNotifications();
  }

  @override
  void didUpdateWidget(covariant NotificationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _loadNotifications();
    }
  }

  @override
  void dispose() {
    RealtimeService.instance.off(
      'notification:created',
      _handleNotificationCreated,
    );
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);

    try {
      final List<AppNotification> items = await NotificationsApi.instance
          .listNotifications();

      if (!mounted) {
        return;
      }

      setState(() => _notifications = items);
      _notifyUnreadCount();
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
        SnackBar(content: Text('Failed to load notifications: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markRead(AppNotification item) async {
    if (item.isRead) {
      return;
    }

    try {
      await NotificationsApi.instance.markRead(item.id);
      await _loadNotifications();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _markAllRead() async {
    if (_isMarkingAllRead || !_notifications.any((item) => !item.isRead)) {
      return;
    }

    setState(() => _isMarkingAllRead = true);
    try {
      await NotificationsApi.instance.markAllRead();
      await _loadNotifications();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _isMarkingAllRead = false);
      }
    }
  }

  Future<void> _respondToFriendRequest({
    required AppNotification notification,
    required String action,
  }) async {
    final String requestId = (notification.payload['requestId'] ?? '')
        .toString();
    if (requestId.isEmpty || _respondingRequestId != null) {
      return;
    }

    setState(() => _respondingRequestId = requestId);

    try {
      await FriendsApi.instance.updateRequest(
        requestId: requestId,
        action: action,
      );
    } catch (error) {
      if (!mounted) {
        setState(() => _respondingRequestId = null);
        return;
      }
      final String msg = error.toString().toLowerCase();
      if (msg.contains('already')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept'
                  ? 'Friend request already accepted.'
                  : 'Friend request already processed.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
      setState(() => _respondingRequestId = null);
      return;
    }

    if (!notification.isRead) {
      await NotificationsApi.instance.markRead(notification.id);
    }
    await _loadNotifications();

    setState(() => _respondingRequestId = null);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          action == 'accept'
              ? 'Friend request accepted.'
              : 'Friend request declined.',
        ),
      ),
    );
  }

  Future<void> _respondToGroupJoinRequest({
    required AppNotification notification,
    required String action,
  }) async {
    final String groupId = (notification.payload['groupId'] ?? '').toString();
    final String fromUserId = (notification.payload['fromUserId'] ?? '')
        .toString();
    final String responseKey = 'group:$groupId:$fromUserId';
    if (groupId.isEmpty || fromUserId.isEmpty || _respondingRequestId != null) {
      return;
    }

    setState(() => _respondingRequestId = responseKey);

    try {
      await GroupsApi.instance.updateJoinRequest(
        groupId: groupId,
        userId: fromUserId,
        action: action,
      );
      if (!notification.isRead) {
        await NotificationsApi.instance.markRead(notification.id);
      }
      await _loadNotifications();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accept'
                ? 'Group join request accepted.'
                : 'Group join request declined.',
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
    } finally {
      if (mounted) {
        setState(() => _respondingRequestId = null);
      }
    }
  }

  void _handleNotificationCreated(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final dynamic rawNotification = payload['notification'];
    if (rawNotification is! Map) {
      _loadNotifications();
      return;
    }

    final AppNotification notification = AppNotification.fromJson(
      Map<String, dynamic>.from(rawNotification),
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _notifications = <AppNotification>[
        notification,
        ..._notifications.where((item) => item.id != notification.id),
      ];
    });
    _notifyUnreadCount();
  }

  void _notifyUnreadCount() {
    widget.onUnreadCountChanged?.call(
      _notifications.where((item) => !item.isRead).length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasUnread = _notifications.any((item) => !item.isRead);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        actions: [
          TextButton(
            onPressed: hasUnread && !_isMarkingAllRead ? _markAllRead : null,
            child: _isMarkingAllRead
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Read all'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNotifications,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            if (_isLoading)
              const LoadingStateView(title: 'Loading notifications...')
            else if (_notifications.isEmpty)
              const EmptyStateView(
                icon: Icons.notifications_off_rounded,
                title: 'No notifications yet',
                message: 'Your updates will show up here.',
              )
            else
              ..._buildSections(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSections() {
    final DateTime now = DateTime.now();
    final List<AppNotification> today = <AppNotification>[];
    final List<AppNotification> earlier = <AppNotification>[];

    for (final AppNotification item in _notifications) {
      final DateTime? createdAt = item.createdAt;
      final bool isToday =
          createdAt != null &&
          createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day;
      if (isToday) {
        today.add(item);
      } else {
        earlier.add(item);
      }
    }

    return <Widget>[
      if (today.isNotEmpty) ...[
        const _SectionTitle(title: 'Today'),
        const SizedBox(height: 10),
        ...today.map(_buildTile),
        const SizedBox(height: 6),
      ],
      if (earlier.isNotEmpty) ...[
        const _SectionTitle(title: 'Earlier'),
        const SizedBox(height: 10),
        ...earlier.map(_buildTile),
      ],
    ];
  }

  Widget _buildTile(AppNotification item) {
    final _NotificationPresentation presentation = _present(item);
    final String requestId = (item.payload['requestId'] ?? '').toString();
    final String groupId = (item.payload['groupId'] ?? '').toString();
    final String fromUserId = (item.payload['fromUserId'] ?? '').toString();
    final String groupRequestKey = 'group:$groupId:$fromUserId';
    final bool canRespondToFriendRequest =
        item.type == 'FRIEND_REQUEST_RECEIVED' &&
        requestId.isNotEmpty &&
        !item.isRead;
    final bool canRespondToGroupJoinRequest =
        item.type == 'GROUP_JOIN_REQUEST' &&
        groupId.isNotEmpty &&
        fromUserId.isNotEmpty &&
        !item.isRead;
    final bool canRespond =
        canRespondToFriendRequest || canRespondToGroupJoinRequest;
    final bool isResponding =
        _respondingRequestId == requestId ||
        _respondingRequestId == groupRequestKey;

    return InkWell(
      onTap: canRespond ? null : () => _markRead(item),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: item.isRead ? Colors.white : const Color(0xFFFFF0F8),
          borderRadius: BorderRadius.circular(18),
          border: item.isRead
              ? null
              : Border.all(color: const Color(0xFFFF9AD5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: presentation.color,
                  child: Icon(
                    presentation.icon,
                    color: const Color(0xFF1A3D7C),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.message,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateTimeFormatter.relative(item.createdAt),
                        style: const TextStyle(color: Color(0xFF9AA7C7)),
                      ),
                    ],
                  ),
                ),
                if (!item.isRead)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5A9E),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            if (canRespond) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isResponding
                          ? null
                          : () {
                              if (canRespondToFriendRequest) {
                                _respondToFriendRequest(
                                  notification: item,
                                  action: 'reject',
                                );
                              } else {
                                _respondToGroupJoinRequest(
                                  notification: item,
                                  action: 'reject',
                                );
                              }
                            },
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isResponding
                          ? null
                          : () {
                              if (canRespondToFriendRequest) {
                                _respondToFriendRequest(
                                  notification: item,
                                  action: 'accept',
                                );
                              } else {
                                _respondToGroupJoinRequest(
                                  notification: item,
                                  action: 'accept',
                                );
                              }
                            },
                      child: isResponding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  _NotificationPresentation _present(AppNotification item) {
    switch (item.type) {
      case 'FRIEND_REQUEST_RECEIVED':
        return const _NotificationPresentation(
          icon: Icons.person_add_alt_1_rounded,
          color: Color(0xFFFFC5E6),
          message: 'You received a new friend request.',
        );
      case 'FRIEND_REQUEST_ACCEPTED':
        return const _NotificationPresentation(
          icon: Icons.group_rounded,
          color: Color(0xFFBEEAFF),
          message: 'Your friend request was accepted.',
        );
      case 'REPORT_SUBMITTED':
        return const _NotificationPresentation(
          icon: Icons.shield_rounded,
          color: Color(0xFFFFE59E),
          message: 'Your report was submitted.',
        );
      case 'REPORT_STATUS_UPDATED':
        final String status = (item.payload['status'] ?? '').toString();
        return _NotificationPresentation(
          icon: Icons.verified_rounded,
          color: const Color(0xFFBEEBD0),
          message: status.isEmpty
              ? 'Your report status was updated.'
              : 'Your report status is now $status.',
        );
      case 'GROUP_JOIN_REQUEST':
        final String requesterName =
            (item.payload['requesterName'] ?? 'Someone').toString();
        final String groupName = (item.payload['groupName'] ?? 'your group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.group_add_rounded,
          color: const Color(0xFFFFE59E),
          message: '$requesterName requested to join $groupName.',
        );
      case 'GROUP_JOIN_REQUEST_ACCEPTED':
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFFBEEBD0),
          message: 'Your request to join $groupName was accepted.',
        );
      case 'GROUP_JOIN_REQUEST_REJECTED':
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFFFC5E6),
          message: 'Your request to join $groupName was declined.',
        );
      default:
        return _NotificationPresentation(
          icon: Icons.notifications_rounded,
          color: const Color(0xFFBEEAFF),
          message: item.type.isEmpty ? 'New notification.' : item.type,
        );
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF1A3D7C),
      ),
    );
  }
}

class _NotificationPresentation {
  const _NotificationPresentation({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;
}
