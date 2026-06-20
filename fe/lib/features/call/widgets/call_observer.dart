import 'package:flutter/material.dart';

import '../../../core/services/realtime_service.dart';
import '../models/call_session.dart';
import '../screens/incoming_call_screen.dart';
import '../services/call_service.dart';

/// Wraps a child screen and listens for incoming call events on the
/// realtime socket. When an event arrives it shows the [IncomingCallScreen]
/// on top of the current navigation stack.
///
/// Place this as the body of `MaterialApp` (or as a child of the navigator
/// root) so it stays alive for the entire authenticated session.
class CallObserver extends StatefulWidget {
  const CallObserver({super.key, required this.child});

  final Widget child;

  @override
  State<CallObserver> createState() => _CallObserverState();
}

class _CallObserverState extends State<CallObserver> {
  void Function(dynamic)? _incomingHandler;
  void Function(dynamic)? _endedHandler;
  void Function(dynamic)? _missedHandler;
  void Function(dynamic)? _cancelledHandler;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void dispose() {
    final RealtimeService realtime = RealtimeService.instance;
    if (_incomingHandler != null) {
      realtime.off('call:incoming', _incomingHandler);
    }
    if (_endedHandler != null) {
      realtime.off('call:ended', _endedHandler);
    }
    if (_missedHandler != null) {
      realtime.off('call:missed', _missedHandler);
    }
    if (_cancelledHandler != null) {
      realtime.off('call:cancelled', _cancelledHandler);
    }
    super.dispose();
  }

  void _attach() {
    final RealtimeService realtime = RealtimeService.instance;
    _incomingHandler = (dynamic payload) {
      if (payload is! Map) return;
      final IncomingCall incoming = IncomingCall.fromJson(
        Map<String, dynamic>.from(payload),
      );
      // If the user is already in a call, ignore the new invite.
      if (CallService.instance.isInCall) return;
      CallService.instance.registerIncoming(incoming);
      _showIncomingScreen(incoming);
    };
    realtime.on('call:incoming', _incomingHandler!);

    _endedHandler = (dynamic payload) {
      if (CallService.instance.isInCall) {
        CallService.instance.hangUp();
      }
    };
    realtime.on('call:ended', _endedHandler!);

    _missedHandler = (dynamic payload) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missed call')),
      );
    };
    realtime.on('call:missed', _missedHandler!);

    _cancelledHandler = (dynamic payload) {
      if (CallService.instance.isInCall) {
        CallService.instance.hangUp();
      }
    };
    realtime.on('call:cancelled', _cancelledHandler!);
  }

  Future<void> _showIncomingScreen(IncomingCall incoming) async {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    await navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(incoming: incoming),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
