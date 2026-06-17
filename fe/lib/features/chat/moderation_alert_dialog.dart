import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

class ModerationAlertDialog extends StatelessWidget {
  const ModerationAlertDialog({
    super.key,
    required this.categories,
    required this.originalText,
  });

  final List<String> categories;
  final String originalText;

  static const Map<String, String> _categoryLabels = <String, String>{
    'vulgar': 'Vulgar / Profane Language',
    'privacy': 'Sharing Personal Information',
    'suicide': 'Self-Harm Related Content',
  };

  static const Map<String, IconData> _categoryIcons = <String, IconData>{
    'vulgar': Icons.block_flipped,
    'privacy': Icons.person_off_outlined,
    'suicide': Icons.favorite_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final List<String> normalized = categories
        .map((String c) => c.toLowerCase().trim())
        .where((String c) => c.isNotEmpty)
        .toList();

    final String title = normalized.length == 1
        ? 'Message Blocked: ${_categoryLabels[normalized.first] ?? normalized.first}'
        : 'Message Blocked: Sensitive Content Detected';

    return Dialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE5E5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFD64545),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.appHeading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'We detected sensitive language in your message. For your safety, the message was not delivered to the other person, and a copy was sent to the moderation team for review.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: context.appHeading,
              ),
            ),
            if (normalized.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                'Reason',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.appMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final String c in normalized)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5E5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _categoryIcons[c] ?? Icons.warning_amber_rounded,
                            size: 14,
                            color: const Color(0xFFD64545),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _categoryLabels[c] ?? c,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFD64545),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appChip,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Your message',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.appMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    originalText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appHeading,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: context.appMuted),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Discard',
                      style: TextStyle(color: context.appHeading),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF33B8FF),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Edit Message',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Future<bool> show({
    required BuildContext context,
    required List<String> categories,
    required String originalText,
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) => ModerationAlertDialog(
        categories: categories,
        originalText: originalText,
      ),
    );
    return result ?? false;
  }
}
