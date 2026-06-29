import 'package:flutter/material.dart';

import '../../profile/support_chat_screen.dart';

enum ModerationDecisionKind { post, comment }

class ModerationDecisionDialog extends StatelessWidget {
  const ModerationDecisionDialog({
    super.key,
    required this.kind,
    required this.status,
    this.serverMessage,
  });

  final ModerationDecisionKind kind;
  final String status;
  final String? serverMessage;

  String get _title {
    switch (kind) {
      case ModerationDecisionKind.post:
        return 'Your post has been moderated';
      case ModerationDecisionKind.comment:
        return 'Your comment has been moderated';
    }
  }

  String get _body {
    final String fallback = kind == ModerationDecisionKind.post
        ? 'Your post has been moderated. Please contact admin if you need support.'
        : 'Your comment has been moderated. Please contact admin if you need support.';
    final String? message = serverMessage;
    if (message == null || message.trim().isEmpty) {
      return fallback;
    }
    return message;
  }

  Color get _accent {
    final String normalized = status.toUpperCase();
    if (normalized == 'PUBLISHED') {
      return const Color(0xFF0A7550);
    }
    return const Color(0xFFA01843);
  }

  IconData get _icon {
    final String normalized = status.toUpperCase();
    if (normalized == 'PUBLISHED') {
      return Icons.check_circle_rounded;
    }
    return Icons.block_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final String trimmed = _body.trim();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(_icon, color: _accent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              trimmed,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF33405C),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A3D7C),
                      side: const BorderSide(color: Color(0xFFD7DEEE)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Close',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF33B8FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                    label: const Text(
                      'Contact admin',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SupportChatScreen(),
                        ),
                      );
                    },
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

bool shouldShowModerationDialog(String status) {
  final String normalized = status.toUpperCase();
  return normalized == 'HIDDEN' || normalized == 'DELETED';
}