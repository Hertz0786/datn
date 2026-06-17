import 'package:flutter/material.dart';

/// Centralised theming for the Kiddo Social app.
///
/// Both light and dark variants are derived from the brand seed colour so
/// the rest of the app can simply opt into [AppTheme.light] or
/// [AppTheme.dark] without having to hard-code colours.
class AppTheme {
  AppTheme._();

  static const Color _seedColor = Color(0xFF33B8FF);

  static ThemeData get light {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return _build(scheme);
  }

  static ThemeData get dark {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _build(scheme);
  }

  static ThemeData _build(ColorScheme scheme) {
    final bool isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF0F1623)
          : const Color(0xFFF6FBF8),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: isDark ? Colors.white : const Color(0xFF1A3D7C),
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : const Color(0xFF1A3D7C),
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF1B2433) : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      textTheme: _textTheme(scheme),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B2433) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    final Color textColor = scheme.brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF1A3D7C);
    return TextTheme(
      titleLarge: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w800,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontWeight: FontWeight.w800,
      ),
      bodyLarge: TextStyle(color: textColor),
      bodyMedium: TextStyle(
        color: scheme.brightness == Brightness.dark
            ? const Color(0xFFD8DEE9)
            : const Color(0xFF1A3D7C),
      ),
    );
  }
}

/// Context-aware palette helpers so screens can adapt to dark mode without
/// having to reach into the Theme each time.
extension AppPalette on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Soft background used for screens, cards, and chips.
  Color get appSurface => isDarkMode
      ? const Color(0xFF1B2433)
      : Colors.white;

  /// Page background used for Scaffolds.
  Color get appBackground => isDarkMode
      ? const Color(0xFF0F1623)
      : const Color(0xFFF6FBF8);

  /// Primary heading colour.
  Color get appHeading => isDarkMode
      ? Colors.white
      : const Color(0xFF1A3D7C);

  /// Subdued text used for metadata, counts, captions.
  Color get appMuted => isDarkMode
      ? const Color(0xFF8E9DB7)
      : const Color(0xFF7A8BBF);

  /// Subtle outline for chips and pill backgrounds.
  Color get appChip => isDarkMode
      ? const Color(0xFF22304A)
      : const Color(0xFFF0F6FF);
}
