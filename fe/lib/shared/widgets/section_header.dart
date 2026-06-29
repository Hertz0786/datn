import 'package:flutter/material.dart';

/// Header row for a section. Optionally renders a primary trailing
/// action (e.g. "Post") and any number of additional trailing widgets
/// (e.g. a topic-discovery icon button).
///
/// Leading content is the section title. Trailing content sits on the
/// right edge so it doesn't collide with other UI elements.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
    this.trailing,
    this.onTrailingTap,
    this.trailingTooltip,
    this.trailingIcon,
  });

  /// Convenience constructor for a single trailing icon button.
  const SectionHeader.iconAction({
    super.key,
    required this.title,
    this.trailingIcon,
    this.onTrailingTap,
    this.trailingTooltip,
    this.actionText,
    this.onAction,
    this.trailing,
  }) : assert(trailing == null, 'Use either trailing or trailingIcon.');

  final String title;

  /// Optional text-only action button (rendered before any icon trailing).
  final String? actionText;
  final VoidCallback? onAction;

  /// Extra trailing widget (e.g. an icon button) that sits to the right
  /// of [actionText]. Use this when a section needs more than one tap
  /// target without depending on AppBar layout.
  final Widget? trailing;

  /// Convenience icon for the trailing tap target. When [trailingIcon] is
  /// provided, a tinted circular icon button is rendered automatically.
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;
  final String? trailingTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (actionText != null)
              TextButton(
                onPressed: onAction ?? () {},
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(actionText!),
              ),
            if (trailingIcon != null)
              _TrailingIconButton(
                icon: trailingIcon!,
                onTap: onTrailingTap,
                tooltip: trailingTooltip,
              )
            else
              ?trailing,
          ],
        ),
      ],
    );
  }
}

class _TrailingIconButton extends StatelessWidget {
  const _TrailingIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? handler = onTap;
    final Widget button = InkWell(
      onTap: handler,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF33B8FF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF33B8FF)),
      ),
    );

    if (tooltip == null || tooltip!.isEmpty || handler == null) {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: button,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(message: tooltip!, child: button),
    );
  }
}
