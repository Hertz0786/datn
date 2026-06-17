/// Heuristic helpers that decide whether a user is "online" based on the
/// last time they were active on the server.
///
/// A user is considered online if their [lastActiveAt] timestamp is within
/// the [onlineWindow] of "now". The default window is 5 minutes, matching
/// the server-side throttle we use to update `lastActiveAt`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A user is online if their last activity was within this window.
const Duration kOnlineWindow = Duration(minutes: 5);

/// Returns true if [lastActiveAt] (when non-null) is within the
/// [window] of the supplied [now] timestamp. A null [lastActiveAt] means
/// the user has never been seen and is treated as offline.
bool isUserOnline(
  DateTime? lastActiveAt, {
  Duration window = kOnlineWindow,
  DateTime? now,
}) {
  if (lastActiveAt == null) {
    return false;
  }
  final DateTime reference = now ?? DateTime.now();
  final Duration diff = reference.difference(lastActiveAt);
  // Defensive: server clocks can drift; if the timestamp is in the
  // future, treat the user as online.
  if (diff.isNegative) {
    return true;
  }
  return diff <= window;
}

String formatOfflineSince(DateTime? lastActiveAt, {DateTime? now}) {
  if (lastActiveAt == null) {
    return 'Offline';
  }

  final DateTime reference = now ?? DateTime.now();
  Duration diff = reference.difference(lastActiveAt);
  if (diff.isNegative) {
    diff = Duration.zero;
  }

  if (diff < const Duration(hours: 1)) {
    final int minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return 'Offline $minutes min ago';
  }

  if (diff < const Duration(hours: 24)) {
    final int hours = diff.inHours < 1 ? 1 : diff.inHours;
    return 'Offline ${hours}h ago';
  }

  final int days = diff.inDays < 1 ? 1 : diff.inDays;
  return 'Offline $days day${days == 1 ? '' : 's'} ago';
}

/// A 30-second ticker used to recompute "online" status. Wrap an avatar
/// in a [ValueListenableBuilder] bound to [OnlineTicker.instance] so the
/// green dot appears and disappears as time passes — no manual refresh
/// needed.
class OnlineTicker extends ValueNotifier<int> {
  OnlineTicker._() : super(0) {
    Timer.periodic(const Duration(seconds: 30), (_) => value++);
  }

  static final OnlineTicker instance = OnlineTicker._();
}
