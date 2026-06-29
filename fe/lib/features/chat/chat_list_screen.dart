import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/chat_summary.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/realtime_service.dart';
import '../../core/session/auth_session.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/user_avatar.dart';
import '../friends/friend_list_screen.dart';
import '../friends/friend_profile_screen.dart';
import 'create_group_chat_screen.dart';
import 'chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  List<ChatSummary> _chats = const <ChatSummary>[];

  @override
  void initState() {
    super.initState();
    _loadChats();
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_onScroll);
    RealtimeService.instance.on('chat:message', _handleRealtimeMessage);
    RealtimeService.instance.on('chat:read', _handleRealtimeRead);
  }

  @override
  void dispose() {
    RealtimeService.instance.off('chat:message', _handleRealtimeMessage);
    RealtimeService.instance.off('chat:read', _handleRealtimeRead);
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Fired by the backend right after it processes [markChatRead] (e.g.
  /// from [ChatDetailScreen]'s auto-mark on open). Use it to flip the
  /// unread badge on the matching conversation to zero immediately.
  void _handleRealtimeRead(dynamic payload) {
    if (payload is! Map) {
      return;
    }
    final String chatId = (payload['chatId'] ?? '').toString();
    if (chatId.isEmpty) {
      return;
    }
    _clearUnread(chatId);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final double extent =
        _scrollController.position.maxScrollExtent -
        _scrollController.position.pixels;
    if (extent < 300) {
      _loadMore();
    }
  }

  Future<void> _loadChats({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _hasMore = true;
        _nextCursor = null;
      });
    }

    try {
      final ChatsPage page = await ChatsApi.instance.listChats();

      if (!mounted) {
        return;
      }

      setState(() {
        _chats = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
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
      ).showSnackBar(SnackBar(content: Text('Failed to load chats: $error')));
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore || _nextCursor == null) {
      return;
    }

    setState(() => _isLoadingMore = true);
    try {
      final ChatsPage page = await ChatsApi.instance.listChats(
        before: _nextCursor,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final List<ChatSummary> next = List<ChatSummary>.from(_chats);
        for (final ChatSummary chat in page.items) {
          if (!next.any((item) => item.id == chat.id)) {
            next.add(chat);
          }
        }
        _chats = next;
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

  void _handleSearchChanged() {
    setState(() {});
  }

  void _handleRealtimeMessage(dynamic payload) {
    if (payload is! Map) {
      return;
    }

    final String chatId = (payload['chatId'] ?? '').toString();
    final dynamic rawMessage = payload['message'];
    if (chatId.isEmpty || rawMessage is! Map) {
      return;
    }

    final ChatMessage message = ChatMessage.fromJson(
      Map<String, dynamic>.from(rawMessage),
    );

    final String myId =
        (AuthSession.instance.user?['id'] ?? '').toString();
    final bool fromOther = myId.isNotEmpty && message.senderId != myId;

    final int index = _chats.indexWhere(
      (ChatSummary chat) => chat.id == chatId,
    );
    if (index == -1) {
      _loadChats(showLoading: false);
      return;
    }

    final List<ChatSummary> updated = List<ChatSummary>.from(_chats);
    final ChatSummary current = updated[index];
    // Inbox messages arrive on every chat the user is a member of.
    // A message authored by anyone else bumps the unread counter (unless
    // the user is already viewing this chat, which clears it below).
    final int nextUnread = current.unreadCount + (fromOther ? 1 : 0);
    updated[index] = current.copyWith(
      lastMessage: message,
      updatedAt: message.createdAt ?? DateTime.now(),
      unreadCount: nextUnread,
    );
    updated.sort((a, b) {
      final DateTime aTime =
          a.lastMessage?.createdAt ?? a.updatedAt ?? DateTime(0);
      final DateTime bTime =
          b.lastMessage?.createdAt ?? b.updatedAt ?? DateTime(0);
      return bTime.compareTo(aTime);
    });

    if (!mounted) {
      return;
    }

    setState(() => _chats = updated);
  }

  /// Local helper called after the user returns from [ChatDetailScreen].
  /// Server already cleared the unread marker via [markChatRead]; we mirror
  /// that on the cached list so the badge disappears immediately.
  void _clearUnread(String chatId) {
    final int index = _chats.indexWhere(
      (ChatSummary chat) => chat.id == chatId,
    );
    if (index == -1 || _chats[index].unreadCount == 0) {
      return;
    }
    final List<ChatSummary> updated = List<ChatSummary>.from(_chats);
    updated[index] = updated[index].copyWith(unreadCount: 0);
    setState(() => _chats = updated);
  }

  List<ChatSummary> get _filteredChats {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _chats;
    }

    return _chats.where((ChatSummary chat) {
      if (chat.isGroup) {
        final String title = chat.title.toLowerCase();
        final String members = chat.memberUsers
            .map((PublicUser user) => '${user.displayName} ${user.username}')
            .join(' ')
            .toLowerCase();
        final String message = (chat.lastMessage?.content ?? '').toLowerCase();
        return title.contains(query) ||
            members.contains(query) ||
            message.contains(query);
      }

      final PublicUser? otherUser = chat.otherUser;
      final String name = (otherUser?.displayName ?? '').toLowerCase();
      final String username = (otherUser?.username ?? '').toLowerCase();
      final String message = (chat.lastMessage?.content ?? '').toLowerCase();
      return name.contains(query) ||
          username.contains(query) ||
          message.contains(query);
    }).toList();
  }

  Future<void> _showNewChatOptions(BuildContext context) async {
    final String? result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _NewChatOption(
                  icon: Icons.chat_bubble_rounded,
                  color: const Color(0xFF33B8FF),
                  label: 'New Chat',
                  subtitle: 'Message a friend privately',
                  onTap: () => Navigator.pop(ctx, 'direct'),
                ),
                const SizedBox(height: 12),
                _NewChatOption(
                  icon: Icons.group_add_rounded,
                  color: const Color(0xFF7A5CFF),
                  label: 'New Group',
                  subtitle: 'Create a group chat',
                  onTap: () => Navigator.pop(ctx, 'group'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;
    if (result == 'direct') {
      _openNewChat();
    } else if (result == 'group') {
      await _openNewGroupChat();
    }
  }

  void _openNewChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FriendListScreen(selectForChat: true),
      ),
    ).then((_) => _loadChats(showLoading: false));
  }

  Future<void> _openNewGroupChat() async {
    final ChatSummary? chat = await Navigator.push<ChatSummary>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupChatScreen()),
    );
    if (!mounted || chat == null) {
      return;
    }

    setState(() {
      _chats = <ChatSummary>[
        chat,
        ..._chats.where((item) => item.id != chat.id),
      ];
    });
    _openChat(chat);
  }

  void _openProfile(PublicUser user) {
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

  void _openChat(ChatSummary chat) {
    final PublicUser? otherUser = chat.otherUser;
    final String title = _chatTitle(chat);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chatId: chat.id,
          title: title,
          avatarUrl: chat.isGroup ? chat.avatarUrl : otherUser?.avatarUrl ?? '',
          avatarLabel: chat.isGroup
              ? _groupInitials(title)
              : otherUser?.initials ?? '?',
          isGroup: chat.isGroup,
          isSocialGroup: chat.isSocialGroup,
          members: chat.memberUsers,
          createdBy: chat.createdBy,
        ),
      ),
    ).then((_) {
      // Server marks the conversation as read when the detail screen
      // mounts; mirror that here so the inbox badge clears instantly.
      _clearUnread(chat.id);
      _loadChats(showLoading: false);
    });
  }

  String _chatTitle(ChatSummary chat) {
    if (chat.isGroup) {
      return chat.title.trim().isNotEmpty ? chat.title.trim() : 'Group chat';
    }
    final PublicUser? otherUser = chat.otherUser;
    return otherUser?.displayName.trim().isNotEmpty == true
        ? otherUser!.displayName
        : 'Chat';
  }

  String _groupInitials(String title) {
    final List<String> parts = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'GC';
    }
    if (parts.length == 1) {
      return parts.first.length >= 2
          ? parts.first.substring(0, 2).toUpperCase()
          : parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatSummary> filteredChats = _filteredChats;
    final List<ChatSummary> besties = _chats
        .where((ChatSummary chat) => !chat.isGroup && chat.otherUser != null)
        .take(8)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatOptions(context),
        backgroundColor: const Color(0xFF33B8FF),
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      body: RefreshIndicator(
        onRefresh: _loadChats,
        child: _isLoading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  LoadingStateView(title: 'Loading chats...'),
                ],
              )
            : ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Besties',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (besties.isEmpty)
                    const EmptyStateView(
                      icon: Icons.people_outline_rounded,
                      title: 'No besties yet',
                      message: 'Start chatting with a friend to see them here.',
                    )
                  else
                    SizedBox(
                      height: 84,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: besties.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final PublicUser user = besties[index].otherUser!;
                          return InkWell(
                            onTap: () => _openProfile(user),
                            borderRadius: BorderRadius.circular(26),
                            child: Column(
                              children: [
                                UserAvatar(
                                  avatarUrl: user.avatarUrl,
                                  initials: user.initials,
                                  radius: 26,
                                  backgroundColor: const Color(0xFFBEEAFF),
                                  lastActiveAt: user.lastActiveAt,
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    user.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Recent chats',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (filteredChats.isEmpty)
                    EmptyStateView(
                      icon: Icons.chat_bubble_rounded,
                      title: _chats.isEmpty
                          ? 'No chats yet'
                          : 'No matching chats',
                      message: _chats.isEmpty
                          ? 'Say hi to a friend and start a conversation.'
                          : 'Try another keyword.',
                    )
                  else
                    ...filteredChats.map(
                      (ChatSummary chat) => _ChatTile(
                        chat: chat,
                        onOpenChat: () => _openChat(chat),
                        onOpenProfile: chat.otherUser == null
                            ? null
                            : () => _openProfile(chat.otherUser!),
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

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.onOpenChat,
    required this.onOpenProfile,
  });

  final ChatSummary chat;
  final VoidCallback onOpenChat;
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final PublicUser? otherUser = chat.otherUser;
    final bool isGroup = chat.isGroup;
    final String title = isGroup
        ? (chat.title.trim().isNotEmpty ? chat.title.trim() : 'Group chat')
        : (otherUser?.displayName.trim().isNotEmpty == true
              ? otherUser!.displayName
              : 'Unknown friend');
    final String subtitle = chat.lastMessage?.content.trim().isNotEmpty == true
        ? chat.lastMessage!.content
        : (chat.isSocialGroup
              ? '${chat.memberCount} group members'
              : isGroup
              ? '${chat.memberCount} members'
              : 'No messages yet');

    // Conversations with unread messages get a stronger title and preview
    // so the user can spot them at a glance. Senders' own messages do not
    // contribute to the unread count, so this naturally highlights chats
    // where someone else has something to read.
    final bool hasUnread = chat.hasUnread;
    final Color previewColor =
        hasUnread ? const Color(0xFF1A3D7C) : const Color(0xFF7A8BBF);
    final FontWeight titleWeight =
        hasUnread ? FontWeight.w900 : FontWeight.w700;
    final FontWeight subtitleWeight =
        hasUnread ? FontWeight.w800 : FontWeight.w500;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasUnread
            ? const Color(0xFFEFF7FF)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: hasUnread
            ? Border.all(
                color: const Color(0xFF33B8FF).withValues(alpha: 0.45),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: isGroup ? onOpenChat : onOpenProfile,
            borderRadius: BorderRadius.circular(24),
            child: isGroup
                ? _GroupChatAvatar(chat: chat, title: title)
                : UserAvatar(
                    avatarUrl: otherUser?.avatarUrl ?? '',
                    initials: otherUser?.initials ?? '?',
                    radius: 24,
                    backgroundColor: const Color(0xFFBEEAFF),
                    lastActiveAt: otherUser?.lastActiveAt,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onOpenChat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: titleWeight,
                            fontSize: 15,
                            color: const Color(0xFF1A3D7C),
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _UnreadBadge(count: chat.unreadCount),
                        ),
                    ],
                  ),
                  if (chat.isSocialGroup) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Group room',
                      style: TextStyle(
                        color: Color(0xFF7A5CFF),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    isGroup &&
                            chat.lastMessage?.content.trim().isNotEmpty == true
                        ? '${chat.memberCount} members • $subtitle'
                        : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: subtitleWeight,
                      color: previewColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateTimeFormatter.format(
              chat.lastMessage?.createdAt ?? chat.updatedAt,
            ),
            style: TextStyle(
              color: hasUnread
                  ? const Color(0xFF33B8FF)
                  : const Color(0xFF9AA7C7),
              fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final String label = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF4D67),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _GroupChatAvatar extends StatelessWidget {
  const _GroupChatAvatar({required this.chat, required this.title});

  final ChatSummary chat;
  final String title;

  @override
  Widget build(BuildContext context) {
    final String avatarUrl = chat.avatarUrl.trim();
    if (avatarUrl.isNotEmpty) {
      return UserAvatar(
        avatarUrl: avatarUrl,
        initials: _initials,
        radius: 24,
        backgroundColor: const Color(0xFFFFC5E6),
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFD8C9FF),
      child: Text(
        _initials,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFF1A3D7C),
        ),
      ),
    );
  }

  String get _initials {
    final List<String> parts = title
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'GC';
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
}

class _NewChatOption extends StatelessWidget {
  const _NewChatOption({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8BBF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 22),
          ],
        ),
      ),
    );
  }
}
