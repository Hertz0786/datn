import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/scaffold_with_bottom_nav.dart';
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

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final TextEditingController _queryController = TextEditingController();

  final List<String> _topics = const [
    'Drawing',
    'Science',
    'Music',
    'Coding',
    'Sports',
    'Story',
  ];

  Timer? _debounce;
  bool _isLoading = true;
  RangeValues _ageRange = const RangeValues(8, 13);
  final Set<String> _selectedTopics = <String>{};
  String _contentType = 'All';
  bool _safeOnly = true;
  SearchResults _results = const SearchResults(
    users: <PublicUser>[],
    groups: <GroupInfo>[],
    posts: <FeedPost>[],
  );

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    setState(() => _isLoading = true);

    final int searchAge = ((_ageRange.start + _ageRange.end) / 2).round();

    try {
      final SearchResults results = await SearchApi.instance.search(
        query: _queryController.text,
        type: _typeParam,
        age: searchAge,
        ageMin: _ageRange.start.round(),
        ageMax: _ageRange.end.round(),
        topics: _selectedTopics.toList(),
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
    switch (_contentType) {
      case 'Friend':
        return 'friend';
      case 'Group':
        return 'group';
      case 'Post':
        return 'post';
      default:
        return 'all';
    }
  }

  List<PublicUser> get _users {
    return _results.users.where((user) {
      final bool matchesTopic =
          _selectedTopics.length <= 1 ||
          user.favoriteTopics.any((topic) => _selectedTopics.contains(topic));
      return matchesTopic &&
          user.age >= _ageRange.start &&
          user.age <= _ageRange.end;
    }).toList();
  }

  List<GroupInfo> get _groups {
    return _results.groups.where((group) {
      final bool matchesTopic =
          _selectedTopics.length <= 1 || _selectedTopics.contains(group.topic);
      return matchesTopic &&
          group.maxAge >= _ageRange.start &&
          group.minAge <= _ageRange.end;
    }).toList();
  }

  List<FeedPost> get _posts {
    return _results.posts.where((post) {
      return _selectedTopics.length <= 1 ||
          post.topics.any((topic) => _selectedTopics.contains(topic));
    }).toList();
  }

  bool get _hasResults =>
      _users.isNotEmpty || _groups.isNotEmpty || _posts.isNotEmpty;

  void _resetFilters() {
    setState(() {
      _queryController.clear();
      _ageRange = const RangeValues(8, 13);
      _selectedTopics.clear();
      _contentType = 'All';
      _safeOnly = true;
    });
    _search();
  }

  void _openUser(PublicUser user) {
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
    final List<PublicUser> users = _users;
    final List<GroupInfo> groups = _groups;
    final List<FeedPost> posts = _posts;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'Advanced Search',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        actions: [
          TextButton(onPressed: _resetFilters, child: const Text('Reset')),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _search,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9BE7FF), Color(0xFFFFD9F0)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tune_rounded, color: Color(0xFF1A3D7C), size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Find safer and fun content by topic and age range.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _queryController,
              onChanged: (_) => _scheduleSearch(),
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search friends, groups, posts...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionHeader(
              title: 'Topic filter',
              actionText: 'Groups',
              onAction: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GroupListScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _topics.map((topic) {
                final bool selected = _selectedTopics.contains(topic);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (selected) {
                        _selectedTopics.remove(topic);
                      } else {
                        _selectedTopics.add(topic);
                      }
                    });
                    _search();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF33B8FF)
                          : const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      topic,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF1A3D7C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Age range',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_ageRange.start.round()} - ${_ageRange.end.round()} years old',
                    style: const TextStyle(color: Color(0xFF5A74A6)),
                  ),
                  RangeSlider(
                    min: 7,
                    max: 14,
                    divisions: 7,
                    values: _ageRange,
                    activeColor: const Color(0xFF33B8FF),
                    labels: RangeLabels(
                      _ageRange.start.round().toString(),
                      _ageRange.end.round().toString(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _ageRange = value;
                      });
                    },
                    onChangeEnd: (_) => _search(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _TypeChoice(
                    label: 'All',
                    selected: _contentType == 'All',
                    onTap: () {
                      setState(() => _contentType = 'All');
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChoice(
                    label: 'Friend',
                    selected: _contentType == 'Friend',
                    onTap: () {
                      setState(() => _contentType = 'Friend');
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChoice(
                    label: 'Group',
                    selected: _contentType == 'Group',
                    onTap: () {
                      setState(() => _contentType = 'Group');
                      _search();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TypeChoice(
                    label: 'Post',
                    selected: _contentType == 'Post',
                    onTap: () {
                      setState(() => _contentType = 'Post');
                      _search();
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _safeOnly,
              onChanged: (value) => setState(() => _safeOnly = value),
              activeThumbColor: const Color(0xFF33B8FF),
              title: const Text(
                'Kid-safe results only',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Backend search already applies age filters.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            SectionHeader(
              title: 'Results',
              actionText: 'Refresh',
              onAction: _search,
            ),
            const SizedBox(height: 10),
            if (_isLoading)
              const LoadingStateView(title: 'Searching...')
            else if (!_hasResults)
              const EmptyStateView(
                icon: Icons.search_off_rounded,
                title: 'No results with current filters',
                message: 'Try a wider age range or add more topics.',
              )
            else ...[
              if (users.isNotEmpty) ...[
                const _ResultSection(title: 'Friends'),
                ...users.map(
                  (user) => _ResultTile(
                    icon: Icons.person_rounded,
                    color: const Color(0xFFFFE59E),
                    title: user.displayName.isEmpty
                        ? user.username
                        : user.displayName,
                    subtitle:
                        'Age ${user.age} | ${user.favoriteTopics.isEmpty ? 'No topic yet' : user.favoriteTopics.first}',
                    buttonLabel: 'View',
                    onTap: () => _openUser(user),
                  ),
                ),
              ],
              if (groups.isNotEmpty) ...[
                const _ResultSection(title: 'Groups'),
                ...groups.map(
                  (group) => _ResultTile(
                    icon: group.icon,
                    color: group.color,
                    title: group.name,
                    subtitle:
                        '${group.topic} | ${group.minAge}-${group.maxAge} y/o',
                    buttonLabel: 'Open',
                    onTap: () => _openGroup(group),
                  ),
                ),
              ],
              if (posts.isNotEmpty) ...[
                const _ResultSection(title: 'Posts'),
                ...posts.map(
                  (post) => _ResultTile(
                    icon: Icons.article_rounded,
                    color: const Color(0xFFBEEBD0),
                    title: post.content,
                    subtitle:
                        '${post.authorDisplayName.isEmpty ? post.authorUsername : post.authorDisplayName} | ${post.commentCount} comments',
                    buttonLabel: 'Open',
                    onTap: () => _openPost(post),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A3D7C),
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                  style: const TextStyle(fontWeight: FontWeight.w800),
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
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _TypeChoice extends StatelessWidget {
  const _TypeChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33B8FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE8FF)),
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
