import 'package:flutter/material.dart';

/// A [Scaffold] that renders the same bottom navigation bar used by
/// [AppShell], so screens pushed from any tab keep the taskbar
/// visible (otherwise `Navigator.push` from inside the shell loses the
/// bar).
///
/// The widget is intentionally minimal — it does **not** render the
/// top-right notifications bell nor the LLM assistant FAB. Those live
/// in [AppShell] and are not relevant on pushed screens.
class ScaffoldWithBottomNav extends StatelessWidget {
  const ScaffoldWithBottomNav({
    super.key,
    required this.child,
    this.currentIndex = -1,
    this.onTabSelected,
  });

  /// Body to render above the bottom navigation bar.
  final Widget child;

  /// Optional tab to highlight as "active". Pass `-1` (default) to
  /// show no tab as selected — appropriate for full-screen pushes
  /// like a friend's profile where no tab is the source.
  final int currentIndex;

  /// Optional callback when the user taps a tab. When `null` the
  /// tab bar is rendered read-only (taps do nothing).
  final ValueChanged<int>? onTabSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex < 0 ? 0 : currentIndex,
          onTap: onTabSelected == null
              ? null
              : (value) => onTabSelected!(value),
          selectedItemColor: const Color(0xFF33B8FF),
          unselectedItemColor: const Color(0xFF9AA7C7),
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.add_rounded, size: 30),
              label: 'Post',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience that wraps [child] in [ScaffoldWithBottomNav] with no
/// tab highlighted. Suitable for pushes that originate from anywhere
/// inside the app where the taskbar should stay visible but no tab is
/// the natural parent (e.g. viewing another user's profile).
class PushedScreenShell extends StatelessWidget {
  const PushedScreenShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScaffoldWithBottomNav(child: child);
  }
}