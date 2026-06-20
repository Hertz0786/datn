import 'package:flutter/material.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../services/call_service.dart';

/// Full-screen "calling..." state shown after a user starts an outgoing call
/// but before the callee picks up. The user can cancel from here.
class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({super.key});

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> {
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    CallService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    CallService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    // If the callee accepted, navigate to the active call screen.
    if (CallService.instance.state == CallState.connecting ||
        CallService.instance.state == CallState.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/call/active');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final CallService service = CallService.instance;
    final String name = service.activeSession?.peer?.label ?? 'Calling…';
    final String avatar = service.activeSession?.peer?.avatarUrl ?? '';

    return PopScope(
      canPop: !_cancelling,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1729),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    UserAvatar(
                      avatarUrl: avatar,
                      initials: _initials(name),
                      radius: 72,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Calling…',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Material(
                    shape: const CircleBorder(),
                    color: const Color(0xFFFF5C5C),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _cancelling ? null : _cancel,
                      child: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    try {
      await CallService.instance.cancelOutgoingCall();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _initials(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return trimmed.length >= 2
          ? trimmed.substring(0, 2).toUpperCase()
          : trimmed.toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}
