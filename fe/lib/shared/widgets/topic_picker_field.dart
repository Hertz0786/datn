import 'package:flutter/material.dart';

import '../../core/models/trending_topic.dart';
import '../../core/services/posts_api.dart';

/// A reusable text-field-shaped topic picker. Used by forms that need
/// the user to select a known topic from a curated list (currently:
/// Create Post, Create Group) — instead of accepting free-form text
/// which leads to inconsistent values and is hard to filter by.
///
/// Tapping the field opens a modal bottom sheet with a search box and
/// a single-select list of trending topics fetched from
/// `PostsApi.trendingTopics`. When that endpoint returns nothing (or
/// the request fails) the picker falls back to [fallbackTopics].
class SingleTopicPickerField extends StatefulWidget {
  const SingleTopicPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Topic',
    this.hint = 'Select topic',
    this.fallbackTopics = const <String>[
      'Drawing',
      'Science',
      'Music',
      'Coding',
      'Sports',
      'Story',
      'Math',
      'Reading',
    ],
  });

  /// Currently selected topic. The empty string means "nothing
  /// selected yet".
  final String value;

  /// Callback when the user picks (or unselects) a topic. Will be
  /// called with the picked topic or the empty string.
  final ValueChanged<String> onChanged;

  /// Label shown above the field and inside the picker modal.
  final String label;

  /// Placeholder shown when nothing is selected.
  final String hint;

  /// Used if `PostsApi.trendingTopics` returns no items (e.g. offline).
  final List<String> fallbackTopics;

  @override
  State<SingleTopicPickerField> createState() => _SingleTopicPickerFieldState();
}

class _SingleTopicPickerFieldState extends State<SingleTopicPickerField> {
  List<TrendingTopic> _availableTopics = <TrendingTopic>[];
  bool _isLoadingTopics = true;

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final List<TrendingTopic> items =
          await PostsApi.instance.trendingTopics(limit: 50);
      if (!mounted) {
        return;
      }
      setState(() {
        _availableTopics = items;
        _isLoadingTopics = false;
      });
    } catch (_) {
      // Use fallback list on error so the picker is still usable.
      if (!mounted) {
        return;
      }
      setState(() => _isLoadingTopics = false);
    }
  }

  List<String> get _allTopicStrings {
    if (_availableTopics.isNotEmpty) {
      return _availableTopics.map((TrendingTopic t) => t.topic).toList();
    }
    return widget.fallbackTopics;
  }

  void _openPicker() {
    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, void Function(void Function()) setSheetState) {
            List<String> filterTopics() {
              final List<String> source = _allTopicStrings;
              if (searchQuery.isEmpty) {
                return source;
              }
              return source
                  .where((String t) =>
                      t.toLowerCase().contains(searchQuery.toLowerCase()))
                  .toList();
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (BuildContext _, ScrollController scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD7E7FF),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Select ${widget.label}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A3D7C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: searchController,
                          onChanged: (String value) {
                            setSheetState(() => searchQuery = value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search topics...',
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF8FA4C7)),
                            filled: true,
                            fillColor: const Color(0xFFF6FAFF),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _isLoadingTopics
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF33B8FF),
                                  ),
                                ),
                              )
                            : filterTopics().isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text(
                                        'No topics found.',
                                        style: TextStyle(color: Color(0xFF8FA4C7)),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                    itemCount: filterTopics().length,
                                    itemBuilder: (BuildContext _, int index) {
                                      final String topic = filterTopics()[index];
                                      final bool isSelected =
                                          widget.value == topic;
                                      return ListTile(
                                        onTap: () {
                                          widget.onChanged(topic);
                                          Navigator.of(sheetContext).pop();
                                        },
                                        leading: Icon(
                                          isSelected
                                              ? Icons.check_circle
                                              : Icons.circle_outlined,
                                          color: isSelected
                                              ? const Color(0xFF33B8FF)
                                              : const Color(0xFFD7E7FF),
                                        ),
                                        title: Text(
                                          topic,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? const Color(0xFF33B8FF)
                                                : const Color(0xFF1A3D7C),
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      searchController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isPlaceholder = widget.value.isEmpty;

    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E7FF)),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_outline, color: Color(0xFF33B8FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPlaceholder ? widget.hint : widget.value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isPlaceholder
                      ? const Color(0xFF8FA4C7)
                      : const Color(0xFF1A3D7C),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down, color: Color(0xFF8FA4C7)),
          ],
        ),
      ),
    );
  }
}