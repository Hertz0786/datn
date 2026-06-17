import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';
import '../../core/models/public_user.dart';
import '../../core/models/search_results.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/search_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/section_header.dart';
import '../feed/post_detail_screen.dart';
import '../friends/friend_profile_screen.dart';
import '../groups/group_detail_screen.dart';
import '../groups/group_info.dart';
import '../groups/group_list_screen.dart';
import 'advanced_search_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _queryController = TextEditingController();

  Timer? _debounce;
  bool _isLoading = true;
  String _selectedQuickZone = 'All';
  SearchResults _results = const SearchResults(
    users: <PublicUser>[],
    groups: <GroupInfo>[],
    posts: <FeedPost>[],
  );

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _openAdvancedSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdvancedSearchScreen()),
    );
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadResults);
  }

  Future<void> _loadResults() async {
    setState(() => _isLoading = true);

    try {
      final SearchResults results = await SearchApi.instance.search(
        query: _queryController.text,
        type: _typeParam,
      );

      if (!mounted) {
        return;
      }

      setState(() => _results = results);
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
      ).showSnackBar(SnackBar(content: Text('Search failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String get _typeParam {
    switch (_selectedQuickZone) {
      case 'Friends':
        return 'friend';
      case 'Groups':
        return 'group';
      case 'Posts':
        return 'post';
      default:
        return 'all';
    }
  }

  bool get _hasResults =>
      _results.users.isNotEmpty ||
      _results.groups.isNotEmpty ||
      _results.posts.isNotEmpty;

  void _selectZone(String zone) {
    setState(() => _selectedQuickZone = zone);
    _loadResults();
  }

  void _openUser(PublicUser user) {
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

  void _openGroup(GroupInfo group) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupDetailScreen(group: group)),
    );
  }

  void _openPost(FeedPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: post.id, initialPost: post),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Search',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openAdvancedSearch,
            icon: const Icon(Icons.tune_rounded),
            color: const Color(0xFF1A3D7C),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadResults,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9BE7FF), Color(0xFFFFD9F0)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Need better filters? Use Advanced Search for age and topic.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _openAdvancedSearch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1A3D7C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _queryController,
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _loadResults(),
              decoration: InputDecoration(
                hintText: 'Find friends, topics, groups...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _queryController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _queryController.clear();
                          _loadResults();
                        },
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
            const SizedBox(height: 18),
            SectionHeader(
              title: 'Quick search',
              actionText: 'Advanced',
              onAction: _openAdvancedSearch,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TopicChip(
                  label: 'All',
                  color: const Color(0xFFD5C6FF),
                  selected: _selectedQuickZone == 'All',
                  onTap: () => _selectZone('All'),
                ),
                _TopicChip(
                  label: 'Friends',
                  color: const Color(0xFF9BE7FF),
                  selected: _selectedQuickZone == 'Friends',
                  onTap: () => _selectZone('Friends'),
                ),
                _TopicChip(
                  label: 'Groups',
                  color: const Color(0xFFFFC5E6),
                  selected: _selectedQuickZone == 'Groups',
                  onTap: () => _selectZone('Groups'),
                ),
                _TopicChip(
                  label: 'Posts',
                  color: const Color(0xFFFFE59E),
                  selected: _selectedQuickZone == 'Posts',
                  onTap: () => _selectZone('Posts'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Trending topics',
              actionText: 'See more',
              onAction: _openAdvancedSearch,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                _TopicChip(label: 'Science', color: Color(0xFF9BE7FF)),
                _TopicChip(label: 'Drawing', color: Color(0xFFFFC5E6)),
                _TopicChip(label: 'Coding', color: Color(0xFFFFE59E)),
                _TopicChip(label: 'Music', color: Color(0xFFBEEBD0)),
                _TopicChip(label: 'Story', color: Color(0xFFD5C6FF)),
              ],
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupListScreen()),
                );
              },
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.groups_rounded, color: Color(0xFF33B8FF)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Explore kid-friendly groups by age and topic',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SectionHeader(
              title: 'Results',
              actionText: 'Refresh',
              onAction: _loadResults,
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const LoadingStateView(title: 'Searching...')
            else if (!_hasResults)
              const EmptyStateView(
                icon: Icons.search_rounded,
                title: 'No results yet',
                message: 'Try searching for friends, groups, or posts.',
              )
            else ...[
              if (_results.users.isNotEmpty) ...[
                const _SectionTitle(title: 'Friends'),
                const SizedBox(height: 8),
                ..._results.users.map(
                  (user) => _UserTile(user: user, onTap: () => _openUser(user)),
                ),
              ],
              if (_results.groups.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionTitle(title: 'Groups'),
                const SizedBox(height: 8),
                ..._results.groups.map(
                  (group) =>
                      _GroupTile(group: group, onTap: () => _openGroup(group)),
                ),
              ],
              if (_results.posts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionTitle(title: 'Posts'),
                const SizedBox(height: 8),
                ..._results.posts.map(
                  (post) => _PostTile(post: post, onTap: () => _openPost(post)),
                ),
              ],
            ],
          ],
        ),
      ),
    );
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

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap});

  final PublicUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ResultTile(
      icon: Icons.person_rounded,
      color: const Color(0xFFFFE59E),
      title: user.displayName.isEmpty ? user.username : user.displayName,
      subtitle:
          'Age ${user.age} | ${user.favoriteTopics.isEmpty ? 'No topic yet' : user.favoriteTopics.first}',
      actionLabel: 'View',
      onTap: onTap,
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onTap});

  final GroupInfo group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ResultTile(
      icon: group.icon,
      color: group.color,
      title: group.name,
      subtitle: '${group.topic} | ${group.memberCount} members',
      actionLabel: 'Open',
      onTap: onTap,
    );
  }
}

class _PostTile extends StatelessWidget {
  const _PostTile({required this.post, required this.onTap});

  final FeedPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String author = post.authorDisplayName.isEmpty
        ? post.authorUsername
        : post.authorDisplayName;

    return _ResultTile(
      icon: Icons.article_rounded,
      color: const Color(0xFFBEEBD0),
      title: post.content,
      subtitle:
          '${author.isEmpty ? 'Unknown author' : author} | ${post.commentCount} comments',
      actionLabel: 'Open',
      onTap: onTap,
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
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
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Icon(icon, color: const Color(0xFF1A3D7C)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF33B8FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.label,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF33B8FF)
              : color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF1A3D7C),
          ),
        ),
      ),
    );
  }
}
