import 'package:flutter/material.dart';

import '../../core/models/feed_post.dart';

class PostAudienceBadge extends StatelessWidget {
  const PostAudienceBadge({
    super.key,
    required this.audience,
    this.groupId,
    this.compact = false,
  });

  factory PostAudienceBadge.forPost(
    FeedPost post, {
    Key? key,
    bool compact = false,
  }) {
    return PostAudienceBadge(
      key: key,
      audience: post.audience,
      groupId: post.groupId,
      compact: compact,
    );
  }

  final String audience;
  final String? groupId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final _AudienceStyle style = _styleForAudience(audience, groupId);

    return Tooltip(
      message: style.tooltip,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: style.backgroundColor,
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: compact ? 12 : 14, color: style.color),
            SizedBox(width: compact ? 3 : 5),
            Text(
              style.label,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w800,
                color: style.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_AudienceStyle _styleForAudience(String audience, String? groupId) {
  final String normalized = audience.toUpperCase();
  if (normalized == 'GROUP' || (groupId != null && groupId.isNotEmpty)) {
    return const _AudienceStyle(
      label: 'Group',
      tooltip: 'Visible in this group',
      icon: Icons.groups_rounded,
      color: Color(0xFF7A2E5A),
      backgroundColor: Color(0xFFFFE59E),
    );
  }
  if (normalized == 'PUBLIC') {
    return const _AudienceStyle(
      label: 'Public',
      tooltip: 'Visible to everyone',
      icon: Icons.public_rounded,
      color: Color(0xFF0F766E),
      backgroundColor: Color(0xFFD7FBE8),
    );
  }
  return const _AudienceStyle(
    label: 'Friends',
    tooltip: 'Visible to friends only',
    icon: Icons.people_alt_rounded,
    color: Color(0xFF1A3D7C),
    backgroundColor: Color(0xFFBEEAFF),
  );
}

class _AudienceStyle {
  const _AudienceStyle({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
}
