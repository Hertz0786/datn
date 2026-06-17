import 'package:flutter/material.dart';

import 'group_info.dart';

class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.group,
    this.size = 44,
    this.isCircle = false,
    this.borderRadius = 14,
  });

  final GroupInfo group;
  final double size;
  final bool isCircle;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final String avatarUrl = group.avatarUrl.trim();
    final BorderRadius radius = BorderRadius.circular(
      isCircle ? size / 2 : borderRadius,
    );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: avatarUrl.isEmpty
            ? _FallbackAvatar(group: group)
            : Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _FallbackAvatar(group: group),
              ),
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar({required this.group});

  final GroupInfo group;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: group.color),
      child: Icon(group.icon, color: const Color(0xFF1A3D7C)),
    );
  }
}
