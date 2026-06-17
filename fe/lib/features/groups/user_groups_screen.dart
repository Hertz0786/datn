import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/groups_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import 'group_avatar.dart';
import 'group_detail_screen.dart';
import 'group_info.dart';

class UserGroupsScreen extends StatefulWidget {
  const UserGroupsScreen({
    super.key,
    required this.userId,
    required this.displayName,
  });

  final String userId;
  final String displayName;

  @override
  State<UserGroupsScreen> createState() => _UserGroupsScreenState();
}

class _UserGroupsScreenState extends State<UserGroupsScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _nextCursor;
  List<GroupInfo> _groups = const <GroupInfo>[];

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
      final GroupsPage page = await GroupsApi.instance.listUserGroups(
        userId: widget.userId,
        limit: 30,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = page.items;
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
      _showError('Failed to load groups: $error');
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
      final GroupsPage page = await GroupsApi.instance.listUserGroups(
        userId: widget.userId,
        limit: 30,
        before: _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _groups = <GroupInfo>[..._groups, ...page.items];
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

  void _openGroup(GroupInfo group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
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
          '${widget.displayName}\'s Groups',
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
                children: [LoadingStateView(title: 'Loading groups...')],
              )
            : ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  if (_groups.isEmpty)
                    EmptyStateView(
                      icon: Icons.groups_2_outlined,
                      title: 'No groups yet',
                      message:
                          '${widget.displayName} has not joined any group yet.',
                    )
                  else
                    ..._groups.map(
                      (GroupInfo group) => _GroupRow(
                        group: group,
                        onTap: () => _openGroup(group),
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

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onTap});

  final GroupInfo group;
  final VoidCallback onTap;

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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF5A74A6)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${group.memberCount} members | ${group.minAge}-${group.maxAge} y/o',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A8BBF),
                      fontWeight: FontWeight.w600,
                    ),
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
