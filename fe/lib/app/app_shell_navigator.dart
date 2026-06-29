/// Allows any descendant widget to ask the app shell to switch to a
/// specific tab without holding a direct reference to [AppShell]. The
/// shell updates this notifier when its [BuildContext] is ready and
/// listens for changes to update its selected tab.
class AppShellNavigator {
  AppShellNavigator._();

  static final AppShellNavigator instance = AppShellNavigator._();

  /// Tab indices used by [AppShell]. Kept in sync with the order of
  /// screens in `app_shell.dart`.
  static const int tabHome = 0;
  static const int tabSearch = 1;
  static const int tabPost = 2;
  static const int tabChat = 3;
  static const int tabProfile = 4;

  void Function(int tabIndex)? _switchTab;

  /// Called by [AppShell] on init to register its tab-switch callback.
  void attach(void Function(int tabIndex) switchTab) {
    _switchTab = switchTab;
  }

  /// Called by [AppShell] on dispose to clear the callback.
  void detach() {
    _switchTab = null;
  }

  /// Returns the currently-active tab index, or `null` if the shell is
  /// not attached (e.g. before login or after logout).
  int? get currentIndex {
    // The shell stores its index privately; we don't need to surface it
    // here for the current callers. Reserved for future use.
    return null;
  }

  /// Switch the bottom navigation to the Home tab (used by flows that
  /// complete on the Home page, e.g. publishing a post from the
  /// "Post" tab).
  void switchToHome() {
    _switchTo(tabHome);
  }

  /// Switch the bottom navigation to the Profile tab. Used by flows
  /// that detect a tap on the current user's avatar (e.g. an author
  /// chip in the feed) and need to land the user on their own
  /// profile without losing the bottom navigation bar.
  void switchToProfile() {
    _switchTo(tabProfile);
  }

  void _switchTo(int tabIndex) {
    final callback = _switchTab;
    if (callback == null) {
      return;
    }
    callback(tabIndex);
  }
}