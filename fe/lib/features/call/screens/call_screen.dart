import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';

import '../../../shared/widgets/user_avatar.dart';
import '../models/call_session.dart';
import '../services/call_service.dart';

/// Renders the active voice/video call. Supports both incoming (after accept)
/// and outgoing flows because the call metadata lives on [CallService].
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallService get _service => CallService.instance;
  bool _isSpeakerOn = true;
  bool _hasReportedError = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final String? error = _service.errorMessage;
    if (error != null && !_hasReportedError) {
      _hasReportedError = true;
      debugPrint('[CallScreen] reporting error to user: $error');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      });
    }
    if (_service.state == CallState.ended || _service.state == CallState.idle) {
      // Reset error flag so next call can report its own errors.
      _hasReportedError = false;
      debugPrint('[CallScreen] call ended/idle — _hasReportedError reset to false');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final CallService service = _service;
    final CallSession? session = service.activeSession;
    final bool isVideo = session?.isVideo ?? false;
    final String name = session?.peer?.label ?? 'Call';
    final String avatar = session?.peer?.avatarUrl ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B1729),
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (full screen) when in a video call.
            if (isVideo && service.remoteUid != 0)
              Positioned.fill(
                child: _RemoteVideo(uid: service.remoteUid),
              )
            else
              Positioned.fill(
                child: _AvatarBackground(
                  name: name,
                  avatarUrl: avatar,
                  status: _statusLabel(service.state),
                  duration: service.callDuration,
                ),
              ),
            // Local video preview (PiP) for video calls.
            if (isVideo)
              Positioned(
                top: 16,
                right: 16,
                child: SizedBox(
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black,
                      child: service.isCameraOff
                          ? const Center(
                              child: Icon(
                                Icons.videocam_off,
                                color: Colors.white70,
                              ),
                            )
                          : AgoraVideoView(
                              controller: VideoViewController(
                                rtcEngine: service.engine!,
                                canvas: const VideoCanvas(uid: 0),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            // Top bar with status and duration.
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: _CallHeader(
                name: name,
                status: _statusLabel(service.state),
                duration: service.callDuration,
              ),
            ),
            // Bottom controls.
            Positioned(
              bottom: 36,
              left: 0,
              right: 0,
              child: _CallControls(
                isVideo: isVideo,
                isMuted: service.isMuted,
                isCameraOff: service.isCameraOff,
                isSpeakerOn: _isSpeakerOn,
                onMute: () => service.toggleMute(),
                onCamera: () => service.toggleCamera(),
                onSwitchCamera: () => service.switchCamera(),
                onSpeaker: () async {
                  setState(() => _isSpeakerOn = !_isSpeakerOn);
                  await service.setSpeaker(_isSpeakerOn);
                },
                onHangUp: _confirmHangUp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmHangUp() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End call?'),
        content: const Text('Are you sure you want to hang up?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End call'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.hangUp();
    }
  }

  String _statusLabel(CallState state) {
    switch (state) {
      case CallState.initiating:
        return 'Starting…';
      case CallState.ringing:
        return 'Ringing…';
      case CallState.connecting:
        return 'Connecting…';
      case CallState.connected:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
      case CallState.failed:
        return 'Call failed';
      case CallState.idle:
        return '';
    }
  }
}

class _CallHeader extends StatelessWidget {
  const _CallHeader({
    required this.name,
    required this.status,
    required this.duration,
  });

  final String name;
  final String status;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final bool showDuration = duration > Duration.zero;
    return Column(
      children: <Widget>[
        Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          showDuration ? _format(duration) : status,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }

  String _format(Duration d) {
    final String mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _RemoteVideo extends StatelessWidget {
  const _RemoteVideo({required this.uid});

  final int uid;

  @override
  Widget build(BuildContext context) {
    final RtcEngine? engine = CallService.instance.engine;
    if (engine == null) {
      debugPrint('[CallScreen] _RemoteVideo: engine is null, showing black');
      return const ColoredBox(color: Colors.black);
    }
    final String channelName = CallService.instance.activeSession?.channelName ?? '';
    if (channelName.isEmpty) {
      debugPrint('[CallScreen] _RemoteVideo: channelName is empty, showing black');
      return const ColoredBox(color: Colors.black);
    }
    debugPrint('[CallScreen] _RemoteVideo: rendering uid=$uid channel=$channelName');
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(uid: uid),
        connection: RtcConnection(channelId: channelName),
      ),
    );
  }
}

class _AvatarBackground extends StatelessWidget {
  const _AvatarBackground({
    required this.name,
    required this.avatarUrl,
    required this.status,
    required this.duration,
  });

  final String name;
  final String avatarUrl;
  final String status;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final String showStatus =
        duration > Duration.zero ? _format(duration) : status;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF14253F), Color(0xFF0B1729)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            UserAvatar(
              avatarUrl: avatarUrl,
              initials: _initials(name),
              radius: 64,
            ),
            const SizedBox(height: 24),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              showStatus,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  String _format(Duration d) {
    final String mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final String ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
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

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.isVideo,
    required this.isMuted,
    required this.isCameraOff,
    required this.isSpeakerOn,
    required this.onMute,
    required this.onCamera,
    required this.onSwitchCamera,
    required this.onSpeaker,
    required this.onHangUp,
  });

  final bool isVideo;
  final bool isMuted;
  final bool isCameraOff;
  final bool isSpeakerOn;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSwitchCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _ControlButton(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            active: !isMuted,
            onPressed: onMute,
          ),
          if (isVideo)
            _ControlButton(
              icon: isCameraOff ? Icons.videocam_off : Icons.videocam,
              active: !isCameraOff,
              onPressed: onCamera,
            ),
          _HangUpButton(onPressed: onHangUp),
          if (isVideo)
            _ControlButton(
              icon: Icons.cameraswitch,
              active: true,
              onPressed: onSwitchCamera,
            )
          else
            _ControlButton(
              icon: isSpeakerOn ? Icons.volume_up : Icons.volume_off,
              active: isSpeakerOn,
              onPressed: onSpeaker,
            ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: active
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.06),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(
            icon,
            color: active ? Colors.white : Colors.white60,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: const Color(0xFFFF5C5C),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 72,
          height: 72,
          child: Icon(
            Icons.call_end,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }
}
