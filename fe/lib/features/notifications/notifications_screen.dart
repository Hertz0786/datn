import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/app_notification.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/groups_api.dart';
import '../../core/services/notifications_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../features/chat/chat_detail_screen.dart';
import '../../features/feed/post_detail_screen.dart';
import '../../features/friends/friend_profile_screen.dart';
import '../../features/groups/group_detail_screen.dart';
import '../../features/groups/group_info.dart';
import '../../core/models/group_detail_data.dart';
import '../../features/profile/support_chat_screen.dart';

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
  bool _isDeletingAll = false;
  bool _isSelectionMode = false;
  String? _respondingRequestId;
  final Set<String> _deletingIds = <String>{};
  final Set<String> _selectedIds = <String>{};
  List<AppNotification> _notifications = const <AppNotification>[];

  // Notification types that should never surface in the user-visible
  // list. Removing a friend is intentionally silent — surfacing it
  // creates an awkward, confrontational UX. Keep this list small and
  // intentional; add new entries only with a clear product reason.
  static const Set<String> _hiddenTypes = <String>{'FRIEND_REMOVED'};

  List<AppNotification> _filterVisible(List<AppNotification> items) {
    return items.where((item) => !_hiddenTypes.contains(item.type)).toList();
  }

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

      setState(() => _notifications = _filterVisible(items));
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

  Future<void> _deleteNotification(AppNotification item) async {
    if (_deletingIds.contains(item.id)) {
      return;
    }

    setState(() => _deletingIds.add(item.id));

    try {
      await NotificationsApi.instance.deleteNotification(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = _notifications
            .where((n) => n.id != item.id)
            .toList();
        _deletingIds.remove(item.id);
      });
      _notifyUnreadCount();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _deletingIds.remove(item.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _deletingIds.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $error')),
      );
    }
  }

  Future<void> _deleteAllNotifications() async {
    if (_isDeletingAll || _notifications.isEmpty) {
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text(
          'This action cannot be undone. All notifications will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isDeletingAll = true);
    try {
      await NotificationsApi.instance.deleteAllNotifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _notifications = [];
        _isDeletingAll = false;
      });
      _notifyUnreadCount();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeletingAll = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isDeletingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete all: $error')),
      );
    }
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(AppNotification item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_notifications.map((n) => n.id));
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selectedIds.length} notification(s)?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeletingAll = true);
    try {
      await NotificationsApi.instance.deleteNotifications(_selectedIds.toList());
      if (!mounted) return;
      setState(() {
        _notifications =
            _notifications.where((n) => !_selectedIds.contains(n.id)).toList();
        _selectedIds.clear();
        _isSelectionMode = false;
        _isDeletingAll = false;
      });
      _notifyUnreadCount();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isDeletingAll = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeletingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $error')),
      );
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

    if (_hiddenTypes.contains(notification.type)) {
      // Silently drop — never rendered, never counts toward unread.
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
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Color(0xFF1A3D7C)),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: Text(
          _isSelectionMode
              ? '${_selectedIds.length} selected'
              : 'Notifications',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        actions: [
          if (_isSelectionMode) ...[
            if (_selectedIds.length < _notifications.length && !_isDeletingAll)
              IconButton(
                icon: const Icon(Icons.select_all_rounded),
                color: const Color(0xFF1A3D7C),
                tooltip: 'Select all',
                onPressed: _selectAll,
              ),
            if (_selectedIds.isNotEmpty && !_isDeletingAll)
              IconButton(
                icon: const Icon(Icons.delete_rounded),
                color: const Color(0xFFFF5A9E),
                tooltip: 'Delete selected',
                onPressed: _deleteSelected,
              ),
            if (_isDeletingAll)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ] else ...[
            if (_notifications.isNotEmpty && !_isDeletingAll)
              IconButton(
                icon: const Icon(Icons.checklist_rounded),
                color: const Color(0xFF1A3D7C),
                tooltip: 'Select',
                onPressed: _enterSelectionMode,
              ),
            if (_notifications.isNotEmpty && !_isDeletingAll)
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                color: const Color(0xFFFF5A9E),
                tooltip: 'Delete all',
                onPressed: _deleteAllNotifications,
              ),
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

  Future<void> _navigateByTarget(AppNotification item) async {
    final Map<String, dynamic> payload = item.payload;
    final Map<String, dynamic>? target =
        payload['navigationTarget'] is Map
            ? Map<String, dynamic>.from(payload['navigationTarget'])
            : null;
    if (target == null) return;

    final String route = (target['route'] ?? '').toString().toUpperCase();
    if (!mounted) return;

    switch (route) {
      case 'POST_DETAIL': {
        final String postId = (target['postId'] ?? '').toString();
        if (postId.isEmpty) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: postId),
          ),
        );
        break;
      }
      case 'CHAT_DETAIL': {
        final String chatId = (target['chatId'] ?? '').toString();
        if (chatId.isEmpty) return;
        final String title = (payload['chatName'] ?? 'Chat').toString();
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: chatId,
              title: title,
            ),
          ),
        );
        break;
      }
      case 'GROUP_DETAIL': {
        final String groupId = (target['groupId'] ?? '').toString();
        if (groupId.isEmpty) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _GroupDetailLoader(groupId: groupId),
          ),
        );
        break;
      }
      case 'PROFILE': {
        final String userId = (target['userId'] ?? '').toString();
        if (userId.isEmpty) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PushedScreenShell(
              child: FriendProfileScreen(
                userId: userId,
                name: (item.payload['actorName'] ?? 'User').toString(),
                age: 10,
                favoriteTopic: '',
              ),
            ),
          ),
        );
        break;
      }
      case 'SUPPORT': {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SupportChatScreen(),
          ),
        );
        break;
      }
      case 'MESSAGES':
      case 'CHATS':
        break;
    }
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
    final bool isDeleting = _deletingIds.contains(item.id);

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (isDeleting) return false;
        await _deleteNotification(item);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF5A9E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: isDeleting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: InkWell(
        onTap: _isSelectionMode
            ? () => _toggleSelection(item)
            : (canRespond
                ? null
                : () async {
                    await _markRead(item);
                    await _navigateByTarget(item);
                  }),
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
                if (_isSelectionMode) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _toggleSelection(item),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedIds.contains(item.id)
                              ? const Color(0xFFFF5A9E)
                              : const Color(0xFF9AA7C7),
                          width: 2,
                        ),
                        color: _selectedIds.contains(item.id)
                            ? const Color(0xFFFF5A9E)
                            : Colors.transparent,
                      ),
                      child: _selectedIds.contains(item.id)
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ],
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
      case 'FRIEND_REQUEST_REJECTED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.person_remove_rounded,
          color: Color(0xFFFFC5E6),
          message: '$actorName declined your friend request.',
        );
      }
      case 'FRIEND_REMOVED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.person_remove_rounded,
          color: Color(0xFFFFC5E6),
          message: '$actorName removed you from their friends.',
        );
      }
      case 'USER_BLOCKED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.block_rounded,
          color: Color(0xFFFFE59E),
          message: '$actorName blocked you.',
        );
      }
      case 'USER_UNBLOCKED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.check_circle_outline_rounded,
          color: Color(0xFFBEEBD0),
          message: '$actorName unblocked you.',
        );
      }
      case 'REPORT_SUBMITTED':
        return const _NotificationPresentation(
          icon: Icons.shield_rounded,
          color: Color(0xFFFFE59E),
          message: 'Your report was submitted.',
        );
      case 'REPORT_STATUS_UPDATED': {
        final String status = (item.payload['status'] ?? '').toString();
        return _NotificationPresentation(
          icon: Icons.verified_rounded,
          color: const Color(0xFFBEEBD0),
          message: status.isEmpty
              ? 'Your report status was updated.'
              : 'Your report status is now $status.',
        );
      }
      case 'GROUP_CREATED': {
        final String groupName = (item.payload['groupName'] ?? 'a group').toString();
        return _NotificationPresentation(
          icon: Icons.group_add_rounded,
          color: const Color(0xFFBEEAFF),
          message: 'You created the group "$groupName".',
        );
      }
      case 'GROUP_JOIN_REQUEST': {
        final String requesterName =
            (item.payload['actorName'] ?? 'Someone').toString();
        final String groupName = (item.payload['groupName'] ?? 'your group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.group_add_rounded,
          color: const Color(0xFFFFE59E),
          message: '$requesterName requested to join $groupName.',
        );
      }
      case 'GROUP_JOIN_REQUEST_ACCEPTED': {
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.check_circle_rounded,
          color: const Color(0xFFBEEBD0),
          message: 'Your request to join $groupName was accepted.',
        );
      }
      case 'GROUP_JOIN_REQUEST_REJECTED': {
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFFFC5E6),
          message: 'Your request to join $groupName was declined.',
        );
      }
      case 'GROUP_MEMBER_JOINED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.person_add_rounded,
          color: const Color(0xFFBEEBD0),
          message: '$actorName joined $groupName.',
        );
      }
      case 'GROUP_MEMBER_LEFT': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        final String groupName = (item.payload['groupName'] ?? 'the group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.exit_to_app_rounded,
          color: const Color(0xFFFFC5E6),
          message: '$actorName left $groupName.',
        );
      }
      case 'GROUP_MEMBER_REMOVED': {
        final String groupName = (item.payload['groupName'] ?? 'a group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.remove_circle_outline_rounded,
          color: const Color(0xFFFFC5E6),
          message: 'You were removed from "$groupName".',
        );
      }
      case 'GROUP_POST_CREATED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        final String groupName = (item.payload['groupName'] ?? 'a group')
            .toString();
        return _NotificationPresentation(
          icon: Icons.article_rounded,
          color: const Color(0xFFBEEAFF),
          message: '$actorName posted in $groupName.',
        );
      }
      case 'POST_LIKED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.favorite_rounded,
          color: const Color(0xFFFFC5E6),
          message: '$actorName liked your post.',
        );
      }
      case 'POST_PENDING_MEDIA_REVIEW':
        return const _NotificationPresentation(
          icon: Icons.hourglass_empty_rounded,
          color: Color(0xFFFFE59E),
          message: 'Your post is pending admin review.',
        );
      case 'POST_MODERATION_DECIDED': {
        final String status = (item.payload['status'] ?? '').toString();
        final String message = status == 'PUBLISHED'
            ? 'Your post was approved by admin.'
            : status == 'DELETED'
                ? 'Your post was removed by admin.'
                : status == 'HIDDEN'
                    ? 'Your post has been put back into pending review.'
                    : 'Your post was reviewed by admin.';
        return _NotificationPresentation(
          icon: status == 'PUBLISHED'
              ? Icons.check_circle_rounded
              : Icons.cancel_rounded,
          color: status == 'PUBLISHED'
              ? const Color(0xFFBEEBD0)
              : const Color(0xFFFFC5E6),
          message: message,
        );
      }
      case 'POST_SHARED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.share_rounded,
          color: const Color(0xFFBEEAFF),
          message: '$actorName shared your post.',
        );
      }
      case 'COMMENT_CREATED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.comment_rounded,
          color: const Color(0xFFBEEAFF),
          message: '$actorName commented on your post.',
        );
      }
      case 'COMMENT_REPLIED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.reply_rounded,
          color: const Color(0xFFBEEAFF),
          message: '$actorName replied to your comment.',
        );
      }
      case 'COMMENT_LIKED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.favorite_rounded,
          color: const Color(0xFFFFC5E6),
          message: '$actorName liked your comment.',
        );
      }
      case 'COMMENT_DELETED':
        return const _NotificationPresentation(
          icon: Icons.delete_outline_rounded,
          color: Color(0xFFFFC5E6),
          message: 'Your comment has been moderated by admin.',
        );
      case 'CHAT_MEMBER_ADDED': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        final String chatName = (item.payload['chatName'] ?? 'a chat').toString();
        return _NotificationPresentation(
          icon: Icons.person_add_rounded,
          color: const Color(0xFFBEEAFF),
          message: '$actorName added you to "$chatName".',
        );
      }
      case 'CHAT_MEMBER_REMOVED': {
        final String chatName = (item.payload['chatName'] ?? 'a chat').toString();
        return _NotificationPresentation(
          icon: Icons.remove_circle_outline_rounded,
          color: const Color(0xFFFFC5E6),
          message: 'You were removed from "$chatName".',
        );
      }
      case 'CHAT_MESSAGE_READ': {
        final String actorName =
            (item.payload['actorName'] ?? 'Someone').toString();
        return _NotificationPresentation(
          icon: Icons.done_all_rounded,
          color: const Color(0xFFBEEBD0),
          message: '$actorName read your message.',
        );
      }
      case 'SUPPORT_MESSAGE_RECEIVED':
        return const _NotificationPresentation(
          icon: Icons.support_agent_rounded,
          color: Color(0xFFBEEAFF),
          message: 'You received a reply from support.',
        );
      case 'SUPPORT_STATUS_UPDATED':
        return const _NotificationPresentation(
          icon: Icons.support_agent_rounded,
          color: Color(0xFFFFE59E),
          message: 'Your support request was updated.',
        );
      case 'ADMIN_BROADCAST': {
        final String body = (item.payload['body'] ?? '').toString();
        return _NotificationPresentation(
          icon: Icons.campaign_rounded,
          color: const Color(0xFFFFE59E),
          message: body.isNotEmpty ? body : 'You have a new announcement.',
        );
      }
      case 'ADMIN_MODERATION_ALERT':
        return const _NotificationPresentation(
          icon: Icons.warning_amber_rounded,
          color: Color(0xFFFFE59E),
          message: 'A content alert needs your attention.',
        );
      case 'ACCOUNT_WARNING':
        return const _NotificationPresentation(
          icon: Icons.warning_rounded,
          color: Color(0xFFFFC5E6),
          message: 'Your account received a warning.',
        );
      case 'PROFILE_UPDATED':
        return const _NotificationPresentation(
          icon: Icons.person_rounded,
          color: Color(0xFFBEEAFF),
          message: 'Your profile has been updated.',
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

class _GroupDetailLoader extends StatefulWidget {
  const _GroupDetailLoader({required this.groupId});

  final String groupId;

  @override
  State<_GroupDetailLoader> createState() => _GroupDetailLoaderState();
}

class _GroupDetailLoaderState extends State<_GroupDetailLoader> {
  GroupInfo? _groupInfo;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGroup();
  }

  Future<void> _loadGroup() async {
    try {
      final GroupDetailData data = await GroupsApi.instance
          .getGroup(widget.groupId);
      if (!mounted) return;
      setState(() {
        _groupInfo = data.group;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _groupInfo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: Center(child: Text(_error ?? 'Group not found')),
      );
    }
    return GroupDetailScreen(group: _groupInfo!);
  }
}
