import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';
import '../../core/models/public_user.dart';
import '../../core/models/user_badge.dart';
import '../../core/models/user_photo.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/badges_api.dart';
import '../../core/services/friends_api.dart';
import '../../core/services/photos_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/services/users_api.dart';
import '../../core/session/auth_session.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/user_avatar.dart';
import '../feed/bookmarks_screen.dart';
import '../feed/my_posts_screen.dart';
import '../friends/friend_list_screen.dart';
import '../groups/group_list_screen.dart';
import '../safety/community_rules_screen.dart';
import 'badge_gallery_screen.dart';
import 'edit_profile_screen.dart';
import 'photo_gallery_screen.dart';
import 'profile_settings_screen.dart';
import 'privacy_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  PublicUser? _user;
  int _friendCount = 0;
  int _postCount = 0;
  int _badgeCount = 0;
  List<UserPhoto> _photos = const <UserPhoto>[];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final List<dynamic> result = await Future.wait<dynamic>(<Future<dynamic>>[
        UsersApi.instance.getMe(),
        FriendsApi.instance.listFriends(),
        PostsApi.instance.myPosts(),
        BadgesApi.instance.myBadges(),
        PhotosApi.instance.myPhotos(),
      ]);

      final PublicUser user = result[0] as PublicUser;
      final FriendsPage friendsPage = result[1] as FriendsPage;
      final List<FeedPost> posts = result[2] as List<FeedPost>;
      final List<UserBadge> badges = result[3] as List<UserBadge>;
      final List<UserPhoto> photos = result[4] is List<UserPhoto>
          ? result[4] as List<UserPhoto>
          : const <UserPhoto>[];

      await AuthSession.instance.updateUser(<String, dynamic>{
        'id': user.id,
        'displayName': user.displayName,
        'username': user.username,
        'age': user.age,
        'role': user.role,
        'avatarUrl': user.avatarUrl,
        'coverUrl': user.coverUrl,
        'bio': user.bio,
        'favoriteTopics': user.favoriteTopics,
        'privacy': user.privacy.toJson(),
      });

      if (!mounted) {
        return;
      }

      setState(() {
        _user = user;
        _friendCount = friendsPage.items.length;
        _postCount = posts.length;
        _badgeCount = badges.where((UserBadge badge) => badge.earned).length;
        _photos = photos;
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
      ).showSnackBar(SnackBar(content: Text('Failed to load profile: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openEditProfile() async {
    final PublicUser? user = _user;
    if (user == null) {
      return;
    }

    final bool? updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)),
    );

    if (updated == true) {
      await _loadProfile();
    }
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
    );
  }

  Future<void> _openFriendList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendListScreen()),
    );
    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openMyPosts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyPostsScreen()),
    );
    if (mounted) {
      await _loadProfile();
    }
  }

  Future<void> _openBadgeGallery() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BadgeGalleryScreen()),
    );
    if (mounted) {
      await _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PublicUser? user = _user;

    return Scaffold(
      backgroundColor: const Color(0xFFF6FBF8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfile,
          child: _isLoading && user == null
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [LoadingStateView(title: 'Loading profile...')],
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (user == null)
                      const EmptyStateView(
                        icon: Icons.person_off_rounded,
                        title: 'Profile unavailable',
                        message: 'Please login again to refresh your profile.',
                      )
                    else ...[
                      _ProfileHeader(user: user, onSettings: _openSettings),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openEditProfile,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF33B8FF),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.edit),
                              label: const Text('Edit profile'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PrivacyScreen(),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF1A3D7C),
                                side: const BorderSide(
                                  color: Color(0xFFBEEAFF),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.shield_rounded),
                              label: const Text('Privacy'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StatCard(
                            title: 'Friends',
                            value: '$_friendCount',
                            onTap: _openFriendList,
                          ),
                          _StatCard(
                            title: 'Posts',
                            value: '$_postCount',
                            onTap: _openMyPosts,
                          ),
                          _StatCard(
                            title: 'Badges',
                            value: '$_badgeCount',
                            onTap: _openBadgeGallery,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick access',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.shield_rounded,
                              label: 'Rules',
                              color: const Color(0xFFFFE59E),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CommunityRulesScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.groups_rounded,
                              label: 'Groups',
                              color: const Color(0xFF9BE7FF),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const GroupListScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.bookmark_rounded,
                              label: 'Bookmarks',
                              color: const Color(0xFFFFD8A8),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const BookmarksScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _QuickActionCard(
                              icon: Icons.photo_library_rounded,
                              label: 'Photos',
                              color: const Color(0xFFC6E2FF),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PhotoGalleryScreen(
                                      initialPhotos: _photos,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SectionHeader(
                        title: 'My badges',
                        actionText: 'See more',
                        onAction: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BadgeGalleryScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      EmptyStateView(
                        icon: Icons.workspace_premium_outlined,
                        title: _badgeCount == 0
                            ? 'No badges yet'
                            : '$_badgeCount badges earned',
                        message: 'Open the gallery to view badge progress.',
                      ),
                      const SizedBox(height: 20),
                      SectionHeader(
                        title: 'Shared photos',
                        actionText: 'Open',
                        onAction: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PhotoGalleryScreen(initialPhotos: _photos),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      if (_photos.isEmpty)
                        const EmptyStateView(
                          icon: Icons.photo_library_outlined,
                          title: 'No shared photos yet',
                          message:
                              'Attach images to your posts to show photos here.',
                        )
                      else
                        _PhotoPreviewGrid(photos: _photos),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.onSettings});

  final PublicUser user;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final String subtitleParts = <String>[
      if (user.bio.trim().isNotEmpty) user.bio.trim(),
      if (user.age > 0) 'age ${user.age}',
    ].join(' | ');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 118,
            width: double.infinity,
            child: user.coverUrl.trim().isEmpty
                ? Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF9BE7FF), Color(0xFFFFD6EC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  )
                : Image.network(
                    user.coverUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Container(color: const Color(0xFFC6E2FF)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: UserAvatar(
                      avatarUrl: user.avatarUrl,
                      initials: user.initials,
                      radius: 38,
                      backgroundColor: const Color(0xFFBEEBD0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitleParts.isEmpty
                              ? '@${user.username}'
                              : subtitleParts,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user.favoriteTopics.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            user.favoriteTopics.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF7A8BBF)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_rounded),
                  tooltip: 'Settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: Color(0xFF7A8BBF))),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: const Color(0xFF1A3D7C), size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A3D7C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPreviewGrid extends StatelessWidget {
  const _PhotoPreviewGrid({required this.photos});

  final List<UserPhoto> photos;

  @override
  Widget build(BuildContext context) {
    final List<UserPhoto> preview = photos.length > 6
        ? photos.sublist(0, 6)
        : photos;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: preview.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final UserPhoto photo = preview[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            photo.url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: const Color(0xFFEFF7FF),
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF7A8BBF),
              ),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }
              return Container(
                color: const Color(0xFFEFF7FF),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
