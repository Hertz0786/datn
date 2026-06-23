import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum VoiceRecorderState {
  idle,
  recording,
  recorded,
  uploading,
}

class VoiceRecorderWidget extends StatefulWidget {
  const VoiceRecorderWidget({
    super.key,
    required this.onRecorded,
    this.maxDurationSeconds = 60,
    this.compact = false,
  });

  final void Function(String filePath, int durationSeconds) onRecorded;
  final int maxDurationSeconds;
  final bool compact;

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Timer? _maxDurationTimer;

  int _recordedSeconds = 0;
  VoiceRecorderState _state = VoiceRecorderState.idle;
  String? _recordedPath;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _maxDurationTimer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final bool hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
        return;
      }

      final String dir = (await getTemporaryDirectory()).path;
      final String path = '$dir/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _state = VoiceRecorderState.recording;
        _recordedSeconds = 0;
        _recordedPath = path;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordedSeconds++);
        }
      });

      _maxDurationTimer = Timer(
        Duration(seconds: widget.maxDurationSeconds),
        _stopRecording,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (_state != VoiceRecorderState.recording) return;

    _timer?.cancel();
    _maxDurationTimer?.cancel();

    try {
      final String? path = await _recorder.stop();
      if (path == null || path.isEmpty) return;

      if (mounted) {
        setState(() {
          _state = VoiceRecorderState.recorded;
          _recordedPath = path;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop recording: $e')),
      );
      setState(() => _state = VoiceRecorderState.idle);
    }
  }

  void _cancelRecording() {
    _timer?.cancel();
    _maxDurationTimer?.cancel();
    _recorder.stop();
    if (_recordedPath != null) {
      final file = File(_recordedPath!);
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }
    setState(() {
      _state = VoiceRecorderState.idle;
      _recordedSeconds = 0;
      _recordedPath = null;
    });
  }

  void _confirmRecording() {
    if (_recordedPath == null) return;
    widget.onRecorded(_recordedPath!, _recordedSeconds);
    setState(() {
      _state = VoiceRecorderState.idle;
      _recordedSeconds = 0;
      _recordedPath = null;
    });
  }

  String _formatDuration(int seconds) {
    final int m = seconds ~/ 60;
    final int s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_state == VoiceRecorderState.idle) {
      return _buildIdleButton();
    }
    if (_state == VoiceRecorderState.recording) {
      return _buildRecordingView();
    }
    if (_state == VoiceRecorderState.recorded) {
      return _buildRecordedView();
    }
    return const SizedBox.shrink();
  }

  Widget _buildIdleButton() {
    if (widget.compact) {
      return IconButton(
        onPressed: _startRecording,
        icon: const Icon(Icons.mic_rounded),
        color: const Color(0xFF33B8FF),
        tooltip: 'Record voice message',
      );
    }

    return OutlinedButton.icon(
      onPressed: _startRecording,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF33B8FF),
        side: const BorderSide(color: Color(0xFF33B8FF), width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: const Icon(Icons.mic_rounded, size: 18),
      label: const Text('Record'),
    );
  }

  Widget _buildRecordingView() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(_recordedSeconds),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.red,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _cancelRecording,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _stopRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  minimumSize: const Size(0, 28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.stop_rounded, size: 16),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordedView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF33B8FF).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF33B8FF),
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatDuration(_recordedSeconds)} recorded',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A3D7C),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _cancelRecording,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF7A8BBF),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
            ),
            child: const Text('Discard'),
          ),
          const SizedBox(width: 4),
          ElevatedButton(
            onPressed: _confirmRecording,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: const Size(0, 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.send_rounded, size: 14),
                SizedBox(width: 4),
                Text('Send'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
