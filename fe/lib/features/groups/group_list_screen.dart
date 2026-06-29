import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/services/groups_api.dart';
import '../../core/session/auth_session.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/topic_picker_field.dart';
import 'group_avatar.dart';
import 'group_detail_screen.dart';
import 'group_info.dart';

enum GroupScope { all, joined }

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key, this.initialScope = GroupScope.all});

  /// When the user navigates here from their own profile, the screen
  /// should default to groups they have already joined instead of the
  /// full directory. Pass [initialScope] = joined to opt into that
  /// behaviour.
  final GroupScope initialScope;

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  final ScrollController _scrollController = ScrollController();

  List<GroupInfo> _groups = const <GroupInfo>[];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _isCreating = false;
  bool _hasMore = true;
  String? _nextCursor;
  String _topicFilter = 'All';
  GroupScope _scope = GroupScope.all;

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _loadGroups();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _hasMore = true;
      _nextCursor = null;
    });

    try {
      final GroupsPage page = await _fetchPage();

      if (!mounted) {
        return;
      }

      setState(() {
        _groups = page.items;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
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
      final GroupsPage page = await _fetchPage(before: _nextCursor);

      if (!mounted) {
        return;
      }

      setState(() {
        final List<GroupInfo> next = List<GroupInfo>.from(_groups);
        for (final GroupInfo group in page.items) {
          if (!next.any((item) => item.id == group.id)) {
            next.add(group);
          }
        }
        _groups = next;
        _hasMore = page.hasMore;
        _nextCursor = page.nextBefore;
      });
    } catch (_) {
      // Silent failure for background pagination.
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  /// Dispatch to the right endpoint based on the currently-selected
  /// scope. The topic filter is intentionally ignored in [joined] scope
  /// because `listUserGroups` does not paginate by topic — the caller
  /// already filtered when they joined.
  Future<GroupsPage> _fetchPage({String? before}) {
    if (_scope == GroupScope.joined) {
      final String? userId = (AuthSession.instance.user?['id'])?.toString();
      if (userId == null || userId.isEmpty) {
        return Future<GroupsPage>.value(
          const GroupsPage(items: <GroupInfo>[], nextBefore: null, hasMore: false),
        );
      }
      return GroupsApi.instance.listUserGroups(
        userId: userId,
        before: before,
      );
    }

    return GroupsApi.instance.listGroups(
      topic: _topicFilter == 'All' ? null : _topicFilter,
      before: before,
    );
  }

  Widget _buildScopeChip(GroupScope scope, String label) {
    final bool selected = _scope == scope;

    return GestureDetector(
      onTap: () {
        if (_scope == scope) {
          return;
        }
        setState(() => _scope = scope);
        _loadGroups();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33B8FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? const Color(0xFF33B8FF)
                : const Color(0xFFE3ECFB),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              scope == GroupScope.joined
                  ? Icons.bookmark_rounded
                  : Icons.explore_rounded,
              size: 18,
              color: selected ? Colors.white : const Color(0xFF1A3D7C),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : const Color(0xFF1A3D7C),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String topic) {
    final bool selected = _topicFilter == topic;

    return GestureDetector(
      onTap: () {
        setState(() {
          _topicFilter = topic;
        });
        _loadGroups();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33B8FF) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          topic,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF1A3D7C),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreateGroupDialog() async {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    String topic = '';

    final bool? shouldCreate = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Create group'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Group name'),
                    ),
                    const SizedBox(height: 12),
                    SingleTopicPickerField(
                      value: topic,
                      onChanged: (String value) {
                        setDialogState(() => topic = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Description'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    final String name = nameController.text.trim();
    topic = topic.trim();
    final String description = descriptionController.text.trim();
    nameController.dispose();
    descriptionController.dispose();

    if (shouldCreate != true) {
      return;
    }
    if (name.isEmpty || topic.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name and topic are required.')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final GroupInfo group = await GroupsApi.instance.createGroup(
        name: name,
        topic: topic,
        description: description,
      );

      if (!mounted) {
        return;
      }

      setState(() => _topicFilter = 'All');
      await _loadGroups();
      if (!mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showJoined = _scope == GroupScope.joined;
    return Scaffold(
      backgroundColor: context.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: context.appHeading),
        title: Text(
          showJoined ? 'My Groups' : 'Fun Groups',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: context.appHeading,
          ),
        ),
        actions: [
          // "Create group" only makes sense when browsing the directory.
          // Hiding it in joined scope keeps the action set focused.
          if (!showJoined)
            IconButton(
              onPressed: _isCreating ? null : _openCreateGroupDialog,
              icon: _isCreating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroups,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            // Scope switcher: All groups vs groups the current user has
            // joined. Always rendered so the user can flip back to the
            // directory without leaving the screen.
            Row(
              children: [
                Expanded(child: _buildScopeChip(GroupScope.all, 'All groups')),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildScopeChip(GroupScope.joined, 'My groups'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!showJoined) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9BE7FF), Color(0xFFFFE2B5)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.groups_rounded,
                      size: 30,
                      color: Color(0xFF1A3D7C),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Join groups that match your age and favorite topics.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  'All',
                  'Drawing',
                  'Science',
                  'Music',
                  'Coding',
                ].map(_buildFilterChip).toList(),
              ),
              const SizedBox(height: 14),
            ],
            if (_isLoading)
              const LoadingStateView(title: 'Loading groups...')
            else if (_groups.isEmpty)
              EmptyStateView(
                icon: Icons.groups_2_outlined,
                title: showJoined ? 'No groups joined yet' : 'No groups found',
                message: showJoined
                    ? 'Switch to "All groups" to find one and join the fun!'
                    : 'Try another topic or refresh later.',
              )
            else ...[
              ..._groups.map(
                (group) => InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupDetailScreen(group: group),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GroupAvatar(group: group, size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: context.appHeading,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                group.description,
                                style: TextStyle(color: context.appHeading),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${group.memberCount} members | ${group.minAge}-${group.maxAge} y/o',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: context.appChip,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Mission: ${group.dailyMission}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2A4474),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
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
          ],
        ),
      ),
    );
  }
}
