import 'package:flutter/material.dart';

import '../screens/call_screen.dart';
import '../services/call_service.dart';

/// Compact buttons that start a voice or video call against a given user.
/// Tapping pushes the [CallScreen] for the active session.
class CallActionButtons extends StatefulWidget {
  const CallActionButtons({
    super.key,
    required this.calleeId,
    this.allowedCallTypes = const <String>['voice', 'video'],
    this.compact = false,
  });

  final String calleeId;
  final List<String> allowedCallTypes;
  final bool compact;

  @override
  State<CallActionButtons> createState() => _CallActionButtonsState();
}

class _CallActionButtonsState extends State<CallActionButtons> {
  bool _busy = false;

  Future<void> _startCall(String callType) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CallService.instance.startOutgoingCall(
        calleeId: widget.calleeId,
        callType: callType,
      );
      if (!mounted) return;
      await Navigator.of(context).pushNamed('/call/active');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showVoice = widget.allowedCallTypes.contains('voice');
    final bool showVideo = widget.allowedCallTypes.contains('video');
    if (!showVoice && !showVideo) {
      return const SizedBox.shrink();
    }
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showVoice)
            IconButton(
              icon: const Icon(Icons.call),
              color: const Color(0xFF22C55E),
              onPressed: _busy ? null : () => _startCall('voice'),
              tooltip: 'Voice call',
            ),
          if (showVideo)
            IconButton(
              icon: const Icon(Icons.videocam),
              color: const Color(0xFF3B82F6),
              onPressed: _busy ? null : () => _startCall('video'),
              tooltip: 'Video call',
            ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        if (showVoice)
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _startCall('voice'),
              icon: const Icon(Icons.call),
              label: const Text('Voice'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        if (showVoice && showVideo) const SizedBox(width: 12),
        if (showVideo)
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _startCall('video'),
              icon: const Icon(Icons.videocam),
              label: const Text('Video'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
      ],
    );
  }
}

/// Single primary button - shows the most appropriate call type (video if
/// available, otherwise voice). Useful for friend cards where space is tight.
class CallPrimaryButton extends StatelessWidget {
  const CallPrimaryButton({
    super.key,
    required this.calleeId,
    this.allowedCallTypes = const <String>['voice', 'video'],
  });

  final String calleeId;
  final List<String> allowedCallTypes;

  @override
  Widget build(BuildContext context) {
    final bool canVideo = allowedCallTypes.contains('video');
    final String type = canVideo ? 'video' : 'voice';
    final IconData icon = canVideo ? Icons.videocam : Icons.call;
    return FilledButton.icon(
      onPressed: () async {
        try {
          await CallService.instance.startOutgoingCall(
            calleeId: calleeId,
            callType: type,
          );
          if (!context.mounted) return;
          await Navigator.of(context).pushNamed('/call/active');
        } catch (error) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.toString())),
          );
        }
      },
      icon: Icon(icon),
      label: Text(canVideo ? 'Video call' : 'Voice call'),
      style: FilledButton.styleFrom(
        backgroundColor: canVideo
            ? const Color(0xFF3B82F6)
            : const Color(0xFF22C55E),
      ),
    );
  }
}

// Suppress unused warning for the CallScreen import - it's used by the
// navigator route name, not directly.
// ignore: unused_element
typedef _UnusedCallScreen = CallScreen;
