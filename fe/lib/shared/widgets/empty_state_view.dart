import 'package:flutter/material.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accentColor,
    this.actionLabel,
    this.onAction,
    this.illustration,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional illustration drawn around the icon (e.g. floating shapes).
  final Widget? illustration;

  /// When true the widget renders without the white card background and with
  /// reduced padding, so it can be embedded inside scrollable content.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = accentColor ?? const Color(0xFF33B8FF);
    final EdgeInsets padding = compact
        ? const EdgeInsets.symmetric(vertical: 24, horizontal: 16)
        : const EdgeInsets.all(18);

    final Widget iconWrap = Container(
      padding: EdgeInsets.all(compact ? 16 : 18),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (illustration != null) ...[
            Positioned.fill(child: illustration!),
          ],
          Icon(icon, color: iconColor, size: compact ? 36 : 32),
        ],
      ),
    );

    return Container(
      padding: padding,
      decoration: compact
          ? null
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWrap,
          SizedBox(height: compact ? 12 : 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5A74A6), height: 1.4),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Decorative blob shapes painted around the empty-state icon.
class FloatingShapesIllustration extends StatelessWidget {
  const FloatingShapesIllustration({super.key, this.color = const Color(0xFF33B8FF)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FloatingShapesPainter(color: color),
      size: const Size.square(120),
    );
  }
}

class _FloatingShapesPainter extends CustomPainter {
  _FloatingShapesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint base = Paint()..color = color.withValues(alpha: 0.18);
    final Paint accent = Paint()..color = color.withValues(alpha: 0.32);

    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.22),
      10,
      base,
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.32),
      14,
      accent,
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.78),
      8,
      base,
    );
    canvas.drawCircle(
      Offset(size.width * 0.20, size.height * 0.80),
      12,
      accent,
    );

    final RRect rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.55, 16, 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, base);
  }

  @override
  bool shouldRepaint(covariant _FloatingShapesPainter oldDelegate) =>
      oldDelegate.color != color;
}
