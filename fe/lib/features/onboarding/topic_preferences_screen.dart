import 'package:flutter/material.dart';

import '../../core/services/users_api.dart';
import '../../shared/widgets/empty_state_view.dart';

/// Asks the user to pick favorite topics after signup. The result is persisted
/// via [UsersApi.updateMe] so the backend can drive the feed and search
/// filters from day one.
class TopicPreferencesScreen extends StatefulWidget {
  const TopicPreferencesScreen({
    super.key,
    required this.initialTopics,
    required this.isFirstTime,
  });

  final List<String> initialTopics;
  final bool isFirstTime;

  @override
  State<TopicPreferencesScreen> createState() => _TopicPreferencesScreenState();
}

class _TopicPreferencesScreenState extends State<TopicPreferencesScreen> {
  final List<String> _topics = <String>[];
  bool _isSubmitting = false;

  static const List<String> _allTopics = <String>[
    'Drawing',
    'Science',
    'Music',
    'Coding',
    'Sports',
    'Story',
    'Math',
    'Reading',
  ];

  @override
  void initState() {
    super.initState();
    _topics.addAll(widget.initialTopics);
  }

  void _toggleTopic(String topic) {
    setState(() {
      if (_topics.contains(topic)) {
        _topics.remove(topic);
      } else {
        _topics.add(topic);
      }
    });
  }

  Future<void> _save() async {
    if (_isSubmitting) {
      return;
    }
    if (_topics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one topic to continue.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await UsersApi.instance.updateMe(favoriteTopics: _topics);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(_topics);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: widget.isFirstTime
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
              title: const Text(
                'Your favorite topics',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1A3D7C),
                ),
              ),
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9BE7FF), Color(0xFFFFD9F0)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'What do you love?',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Pick a few topics so we can show fun content and friends who like the same things.',
                      style: TextStyle(
                        color: Color(0xFF1A3D7C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _allTopics.map((topic) {
                      final bool selected = _topics.contains(topic);
                      return GestureDetector(
                        onTap: () => _toggleTopic(topic),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF33B8FF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFF33B8FF),
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                topic,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF1A3D7C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_topics.isEmpty)
                const EmptyStateView(
                  icon: Icons.tips_and_updates_rounded,
                  title: 'No topics yet',
                  message: 'Tap a topic above to add it.',
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF33B8FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.isFirstTime ? 'Continue' : 'Save changes',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
