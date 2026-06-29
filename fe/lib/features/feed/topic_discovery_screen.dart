import 'package:flutter/material.dart';

import '../../core/models/trending_topic.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/posts_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import 'topic_feed_screen.dart';

class TopicDiscoveryScreen extends StatefulWidget {
  const TopicDiscoveryScreen({super.key});

  @override
  State<TopicDiscoveryScreen> createState() => _TopicDiscoveryScreenState();
}

class _TopicDiscoveryScreenState extends State<TopicDiscoveryScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  List<TrendingTopic> _topics = <TrendingTopic>[];

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final List<TrendingTopic> items = await PostsApi.instance.trendingTopics(limit: 20);
      if (!mounted) return;
      setState(() => _topics = items);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A3D7C)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Topics',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadTopics,
        child: _isLoading
            ? const Center(child: LoadingStateView(title: 'Loading topics...'))
            : _hasError
                ? Center(
                    child: EmptyStateView(
                      icon: Icons.error_outline_rounded,
                      title: 'Something went wrong',
                      message: 'Pull to refresh and try again.',
                      actionLabel: 'Retry',
                      onAction: _loadTopics,
                    ),
                  )
                : _topics.isEmpty
                    ? const Center(
                        child: EmptyStateView(
                          icon: Icons.tag_rounded,
                          title: 'No topics yet',
                          message: 'Topics will appear here when people start using them.',
                        ),
                      )
                    : _buildTopicGrid(),
      ),
    );
  }

  Widget _buildTopicGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: _topics.length,
      itemBuilder: (context, index) {
        final TrendingTopic item = _topics[index];
        return _TopicCard(
          topic: item.topic,
          postCount: item.postCount,
          color: _topicColor(index),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TopicFeedScreen(topic: item.topic),
              ),
            );
          },
        );
      },
    );
  }

  Color _topicColor(int index) {
    const List<Color> colors = [
      Color(0xFF33B8FF),
      Color(0xFF7A5CFF),
      Color(0xFFFF7188),
      Color(0xFFFFA94D),
      Color(0xFF22C55E),
      Color(0xFFFFE59E),
      Color(0xFF06B6D4),
      Color(0xFFF472B6),
    ];
    return colors[index % colors.length];
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({
    required this.topic,
    required this.postCount,
    required this.color,
    required this.onTap,
  });

  final String topic;
  final int postCount;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.tag_rounded,
                color: color,
                size: 20,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  topic,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$postCount posts',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
