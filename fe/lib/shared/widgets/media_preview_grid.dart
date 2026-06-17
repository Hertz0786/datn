import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MediaPreviewGrid extends StatelessWidget {
  const MediaPreviewGrid({super.key, required this.urls, this.compact = false});

  final List<String> urls;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final List<String> visibleUrls = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();

    if (visibleUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: visibleUrls
            .take(4)
            .map(
              (url) => Padding(
                padding: EdgeInsets.only(
                  bottom: url == visibleUrls.last ? 0 : 8,
                ),
                child: _MediaTile(url: url, compact: compact),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.url, required this.compact});

  final String url;
  final bool compact;

  bool get _isVideo {
    final String lower = url.toLowerCase();
    return lower.contains('/video/upload/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.m3u8');
  }

  @override
  Widget build(BuildContext context) {
    final double height = compact ? 120 : 190;

    if (_isVideo) {
      return _VideoTile(url: url, height: height);
    }

    return Image.network(
      url,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFFEFF7FF),
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_rounded, color: Color(0xFF5A74A6)),
      ),
    );
  }
}

class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.url, required this.height});

  final String url;
  final double height;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  VideoPlayerController? _controller;
  bool _initialised = false;
  bool _failed = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    try {
      final VideoPlayerController controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller
        ..setLooping(true)
        ..setVolume(_muted ? 0 : 1);
      setState(() {
        _controller = controller;
        _initialised = true;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      return;
    }
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  void _toggleMute() {
    final VideoPlayerController? controller = _controller;
    if (controller == null) {
      return;
    }
    setState(() {
      _muted = !_muted;
      controller.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = _controller;
    final bool isPlaying = controller?.value.isPlaying ?? false;

    return Container(
      height: widget.height,
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && _initialised)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            )
          else if (_failed)
            const _VideoFallback(message: 'Video unavailable')
          else
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          if (_initialised)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _togglePlay,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: isPlaying ? 0 : 0.95,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_initialised)
            Positioned(
              right: 6,
              bottom: 6,
              child: Material(
                color: Colors.black.withValues(alpha: 0.35),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggleMute,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoFallback extends StatelessWidget {
  const _VideoFallback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFBEEAFF), Color(0xFFD7C8FF)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            color: Color(0xFF1A3D7C),
            size: 46,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF1A3D7C),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
