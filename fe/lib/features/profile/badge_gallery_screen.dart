import 'package:flutter/material.dart';

import '../../core/models/user_badge.dart';
import '../../core/services/badges_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';

class BadgeGalleryScreen extends StatefulWidget {
  const BadgeGalleryScreen({super.key, this.userId, this.title = 'My Badges'});

  final String? userId;
  final String title;

  @override
  State<BadgeGalleryScreen> createState() => _BadgeGalleryScreenState();
}

class _BadgeGalleryScreenState extends State<BadgeGalleryScreen> {
  bool _isLoading = true;
  List<UserBadge> _badges = const <UserBadge>[];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    setState(() => _isLoading = true);

    try {
      final String? userId = widget.userId?.trim();
      final List<UserBadge> items = userId == null || userId.isEmpty
          ? await BadgesApi.instance.myBadges()
          : await BadgesApi.instance.userBadges(userId);
      if (!mounted) {
        return;
      }
      setState(() => _badges = items);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(
          widget.title,
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
        onRefresh: _loadBadges,
        child: _isLoading
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [LoadingStateView(title: 'Loading badges...')],
              )
            : _badges.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  EmptyStateView(
                    icon: Icons.workspace_premium_outlined,
                    title: 'No badges available',
                    message: 'Badge progress will appear here.',
                  ),
                ],
              )
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.05,
                ),
                itemCount: _badges.length,
                itemBuilder: (context, index) {
                  final UserBadge badge = _badges[index];
                  return _BadgeCard(badge: badge);
                },
              ),
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final UserBadge badge;

  @override
  Widget build(BuildContext context) {
    final double progress = badge.target <= 0
        ? 0
        : (badge.progress / badge.target).clamp(0, 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: badge.earned ? const Color(0xFFFFE59E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: badge.earned
              ? const Color(0xFFFFC145)
              : const Color(0xFFE1E8F8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            badge.earned
                ? Icons.workspace_premium_rounded
                : Icons.workspace_premium_outlined,
            color: const Color(0xFF1A3D7C),
          ),
          const SizedBox(height: 10),
          Text(
            badge.title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            badge.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const Spacer(),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 6),
          Text('${badge.progress}/${badge.target}'),
        ],
      ),
    );
  }
}
