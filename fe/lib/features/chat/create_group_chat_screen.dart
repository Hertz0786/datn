import 'package:flutter/material.dart';

import '../../core/models/chat_summary.dart';
import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/chats_api.dart';
import '../../core/services/friends_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/user_avatar.dart';

class CreateGroupChatScreen extends StatefulWidget {
  const CreateGroupChatScreen({super.key});

  @override
  State<CreateGroupChatScreen> createState() => _CreateGroupChatScreenState();
}

class _CreateGroupChatScreenState extends State<CreateGroupChatScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Set<String> _selectedIds = <String>{};

  bool _isLoading = true;
  bool _isCreating = false;
  List<PublicUser> _friends = const <PublicUser>[];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);
    try {
      final FriendsPage page = await FriendsApi.instance.listFriends(limit: 50);
      if (!mounted) {
        return;
      }
      setState(() => _friends = page.items);
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleFriend(PublicUser friend) {
    setState(() {
      if (_selectedIds.contains(friend.id)) {
        _selectedIds.remove(friend.id);
      } else {
        _selectedIds.add(friend.id);
      }
    });
  }

  Future<void> _createGroupChat() async {
    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Please enter a group chat name.');
      return;
    }
    if (_selectedIds.isEmpty) {
      _showError('Choose at least one friend.');
      return;
    }
    if (_isCreating) {
      return;
    }

    setState(() => _isCreating = true);
    try {
      final ChatSummary chat = await ChatsApi.instance.createGroupChat(
        title: title,
        memberIds: _selectedIds.toList(),
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, chat);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      _showError(error.message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showError('Create group chat failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'New group chat',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroupChat,
            child: _isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFriends,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Group chat name',
                hintText: 'Study buddies, Art crew...',
                prefixIcon: const Icon(Icons.groups_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${_selectedIds.length} selected',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A3D7C),
              ),
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const LoadingStateView(title: 'Loading friends...')
            else if (_friends.isEmpty)
              const EmptyStateView(
                icon: Icons.group_outlined,
                title: 'No friends yet',
                message: 'Add friends before creating a group chat.',
              )
            else
              ..._friends.map((PublicUser friend) {
                final bool selected = _selectedIds.contains(friend.id);
                return _FriendCheckTile(
                  friend: friend,
                  selected: selected,
                  onTap: () => _toggleFriend(friend),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _FriendCheckTile extends StatelessWidget {
  const _FriendCheckTile({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  final PublicUser friend;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = friend.displayName.trim().isNotEmpty
        ? friend.displayName
        : friend.username;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF0F8) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFFF9AD5) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            UserAvatar(
              avatarUrl: friend.avatarUrl,
              initials: friend.initials,
              radius: 22,
              backgroundColor: const Color(0xFFBEEAFF),
              lastActiveAt: friend.lastActiveAt,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${friend.username}',
                    style: const TextStyle(color: Color(0xFF7A8BBF)),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? const Color(0xFFFF5A9E)
                  : const Color(0xFF9AA7C7),
            ),
          ],
        ),
      ),
    );
  }
}
