import 'package:flutter/material.dart';

import '../../../core/models/public_user.dart';
import '../../../core/session/auth_session.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../models/call_peer.dart';
import '../models/call_session.dart';
import '../services/call_service.dart';

/// Full-screen prompt shown when another user is calling. Provides accept /
/// reject actions and, on accept, hands the user off to the active call UI.
class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.incoming});

  final IncomingCall incoming;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  bool _isProcessing = false;

  CallPeer get _caller => widget.incoming.caller;

  @override
  Widget build(BuildContext context) {
    final PublicUser currentUser = _currentUserSnapshot();
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1729),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    UserAvatar(
                      avatarUrl: _caller.avatarUrl,
                      initials: _initialsOf(_caller.label),
                      radius: 72,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _caller.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Incoming ${widget.incoming.callType} call',
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Calling ${currentUser.displayName}',
                      style: const TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end,
                      color: const Color(0xFFFF5C5C),
                      label: 'Decline',
                      onPressed: _isProcessing ? null : _decline,
                    ),
                    _CallActionButton(
                      icon: widget.incoming.isVideo
                          ? Icons.videocam
                          : Icons.call,
                      color: const Color(0xFF22C55E),
                      label: 'Accept',
                      onPressed: _isProcessing ? null : _accept,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _accept() async {
    setState(() => _isProcessing = true);
    try {
      await CallService.instance.acceptIncoming();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/call/active');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _isProcessing = true);
    try {
      await CallService.instance.rejectIncoming();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  PublicUser _currentUserSnapshot() {
    final Map<String, dynamic>? user = AuthSession.instance.user;
    if (user == null) {
      return PublicUser(
        id: '',
        displayName: 'You',
        username: '',
        age: 0,
        role: 'CHILD',
        avatarUrl: '',
        bio: '',
        favoriteTopics: const [],
      );
    }
    return PublicUser.fromJson(user);
  }

  String _initialsOf(String name) {
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

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: Material(
            shape: const CircleBorder(),
            color: color,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }
}
