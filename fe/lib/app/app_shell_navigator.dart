/// Allows any descendant widget to ask the app shell to switch to the
/// Home tab without holding a direct reference to [AppShell]. The shell
/// updates this notifier when its [BuildContext] is ready and listens
/// for changes to update its selected tab.
class AppShellNavigator {
  AppShellNavigator._();

  static final AppShellNavigator instance = AppShellNavigator._();

  void Function(int tabIndex)? _switchTab;

  /// Called by [AppShell] on init to register its tab-switch callback.
  void attach(void Function(int tabIndex) switchTab) {
    _switchTab = switchTab;
  }

  /// Called by [AppShell] on dispose to clear the callback.
  void detach() {
    _switchTab = null;
  }

  /// Switch the bottom navigation to a specific tab. Currently only the
  /// Home tab (0) is exposed for navigation flows that complete on a tab
  /// page (e.g. publishing a post from the "Post" tab).
  void switchToHome() {
    final callback = _switchTab;
    if (callback == null) {
      return;
    }
    callback(0);
  }
}
