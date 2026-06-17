import 'package:flutter/material.dart';

import '../../core/models/chat_message.dart';
import '../../core/models/chat_summary.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/realtime_service.dart';
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
  }

  @override
  void dispose() {
    RealtimeService.instance.off('chat:message', _handleRealtimeMessage);
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
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

    final int index = _chats.indexWhere(
      (ChatSummary chat) => chat.id == chatId,
    );
    if (index == -1) {
      _loadChats(showLoading: false);
      return;
    }

    final List<ChatSummary> updated = List<ChatSummary>.from(_chats);
    updated[index] = updated[index].copyWith(
      lastMessage: message,
      updatedAt: message.createdAt ?? DateTime.now(),
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
    ).then((_) => _loadChats(showLoading: false));
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
        actions: [
          IconButton(
            onPressed: _openNewGroupChat,
            icon: const Icon(Icons.group_add_rounded),
            tooltip: 'New group chat',
            color: const Color(0xFF1A3D7C),
          ),
          IconButton(
            onPressed: _openNewChat,
            icon: const Icon(Icons.add_comment_rounded),
            tooltip: 'New direct chat',
            color: const Color(0xFF1A3D7C),
          ),
        ],
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                  ),
                ],
              ),
            ),
          ),
          Text(
            DateTimeFormatter.format(
              chat.lastMessage?.createdAt ?? chat.updatedAt,
            ),
            style: const TextStyle(color: Color(0xFF9AA7C7)),
          ),
        ],
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
