import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../app/app_theme.dart';

/// Inline summary of a past voice/video call, rendered in place of a regular
/// chat bubble when the message has `type: 'CALL'`. Shows:
///   - "Missed call · 22:41"        when the call was never answered
///   - "Video call · 12s · 22:41"   when the call connected briefly
///   - "Voice call · 02:13 · 22:41" for longer calls
///   - "Cancelled call · 22:41"     when caller hung up before pickup
///
/// The banner is intentionally non-interactive and centered, mirroring
/// Messenger/Zalo's "system message" pattern.
class CallBanner extends StatelessWidget {
  const CallBanner({
    super.key,
    required this.message,
    required this.isOutgoing,
  });

  final ChatMessage message;
  final bool isOutgoing;

  @override
  Widget build(BuildContext context) {
    final CallMeta? meta = message.callMeta;
    if (meta == null) {
      return const SizedBox.shrink();
    }

    final String timeText = DateTimeFormatter.format(message.createdAt);
    final Color mutedText = context.appMuted;
    final Color accent = _accentFor(meta);

    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(_iconFor(meta), size: 18, color: accent),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _titleFor(meta, isOutgoing),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.appHeading,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (_subtitleFor(meta, isOutgoing).isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _subtitleFor(meta, isOutgoing),
                  style: TextStyle(fontSize: 11, color: mutedText),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (timeText.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            timeText,
            style: TextStyle(fontSize: 10, color: mutedText),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.appSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  IconData _iconFor(CallMeta meta) {
    if (meta.isMissed) return Icons.call_missed_rounded;
    if (meta.isRejected) return Icons.call_end_rounded;
    if (meta.isCancelled) return Icons.call_made_rounded;
    if (meta.isVideo) return Icons.videocam_rounded;
    return Icons.call_rounded;
  }

  Color _accentFor(CallMeta meta) {
    if (meta.isMissed) return const Color(0xFFE85A75);
    if (meta.isRejected) return const Color(0xFFE85A75);
    if (meta.isCancelled) return const Color(0xFFB58A2A);
    if (meta.isVideo) return const Color(0xFF3B82F6);
    return const Color(0xFF22C55E);
  }

  String _callTypeLabel(CallMeta meta) {
    return meta.isVideo ? 'Video call' : 'Voice call';
  }

  String _titleFor(CallMeta meta, bool isOutgoing) {
    if (meta.isMissed) {
      return isOutgoing ? 'No answer' : 'Missed call';
    }
    if (meta.isRejected) {
      return isOutgoing ? 'Call declined' : 'You declined';
    }
    if (meta.isCancelled) {
      return isOutgoing ? 'Call cancelled' : 'Call cancelled before pickup';
    }
    return _callTypeLabel(meta);
  }

  String _subtitleFor(CallMeta meta, bool isOutgoing) {
    if (meta.isMissed) {
      return isOutgoing
          ? 'They didn’t pick up'
          : 'Tap to call back';
    }
    if (meta.isRejected) {
      return isOutgoing
          ? 'They declined the call'
          : 'You declined the call';
    }
    if (meta.isCancelled) {
      return isOutgoing
          ? 'You hung up before they answered'
          : 'The caller hung up';
    }
    final int seconds = meta.durationSeconds;
    if (seconds <= 0) {
      return 'No one connected';
    }
    return 'Duration: ${_formatDuration(seconds)}';
  }

  String _formatDuration(int totalSeconds) {
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
