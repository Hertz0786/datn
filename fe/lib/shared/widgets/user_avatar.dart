import 'package:flutter/material.dart';

import '../../core/utils/presence.dart';

/// Circular avatar.
///
/// - When [avatarUrl] is empty the initials are shown.
/// - When [avatarUrl] is non-empty the network image is rendered with
///   [BoxFit.cover] and clipped to a perfect circle via [ClipOval], so the
///   image never shows the rectangular edges that [CircleAvatar] can
///   sometimes expose when the child has a non-circular intrinsic size.
/// - Loading and error states fall back to the initials without touching
///   the parent Element, avoiding Flutter framework assertion errors.
/// - Pass [isOnline] = true to render a small green dot at the bottom-right
///   of the avatar. The dot is positioned in absolute coordinates so it
///   does not push siblings around.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.avatarUrl,
    required this.initials,
    this.radius = 20,
    this.backgroundColor = const Color(0xFFBEEAFF),
    this.foregroundColor = const Color(0xFF1A3D7C),
    this.lastActiveAt,
  });

  final String avatarUrl;
  final String initials;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final DateTime? lastActiveAt;

  @override
  Widget build(BuildContext context) {
    final double size = radius * 2;
    final Widget fallback = _InitialsText(
      initials: initials,
      color: foregroundColor,
    );

    return ValueListenableBuilder<int>(
      valueListenable: OnlineTicker.instance,
      builder: (context, value, child) {
        final bool online = isUserOnline(lastActiveAt);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: ColoredBox(
                  color: backgroundColor,
                  child: avatarUrl.trim().isEmpty
                      ? Center(child: fallback)
                      : _NetworkAvatar(
                          url: avatarUrl.trim(),
                          size: size,
                          fallback: fallback,
                          foregroundColor: foregroundColor,
                        ),
                ),
              ),
              if (online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: OnlineDot(radius: radius),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A small green status dot, sized relative to the parent avatar radius.
/// The dot is the same green used by most major chat apps so it reads
/// as "online" without any text. It is wrapped in a 2px white border so
/// it remains visible on top of any avatar background.
class OnlineDot extends StatelessWidget {
  const OnlineDot({
    super.key,
    this.radius = 20,
    this.color = const Color(0xFF22C55E),
  });

  /// Parent avatar radius. The dot diameter is roughly 35% of the avatar
  /// diameter and never smaller than 9 logical pixels.
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final double avatarDiameter = radius * 2;
    final double dotDiameter = avatarDiameter * 0.35;
    final double finalDiameter = dotDiameter < 9 ? 9 : dotDiameter;
    final double borderWidth = finalDiameter * 0.18;

    return Container(
      width: finalDiameter,
      height: finalDiameter,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: borderWidth),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: finalDiameter * 0.4,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}

class _InitialsText extends StatelessWidget {
  const _InitialsText({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      initials,
      style: TextStyle(fontWeight: FontWeight.w800, color: color),
    );
  }
}

class _NetworkAvatar extends StatefulWidget {
  const _NetworkAvatar({
    required this.url,
    required this.size,
    required this.fallback,
    required this.foregroundColor,
  });

  final String url;
  final double size;
  final Widget fallback;
  final Color foregroundColor;

  @override
  State<_NetworkAvatar> createState() => _NetworkAvatarState();
}

class _NetworkAvatarState extends State<_NetworkAvatar> {
  bool _errored = false;

  @override
  void didUpdateWidget(covariant _NetworkAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && _errored) {
      _errored = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errored) {
      return Center(child: widget.fallback);
    }
    return Image.network(
      widget.url,
      key: ValueKey<String>('avatar:${widget.url}'),
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _errored) return;
          setState(() => _errored = true);
        });
        return Center(child: widget.fallback);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(child: widget.fallback);
      },
    );
  }
}
