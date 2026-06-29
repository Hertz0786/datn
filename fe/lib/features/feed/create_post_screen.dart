import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_shell_navigator.dart';
import '../../core/models/feed_post.dart';
import '../../core/models/media_asset.dart';
import '../../core/models/trending_topic.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/media_api.dart';
import '../../core/services/posts_api.dart';
import '../../core/session/auth_session.dart';
import 'mood_picker_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.groupId, this.groupName});

  final String? groupId;
  final String? groupName;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _contentController = TextEditingController();
  final List<XFile> _pickedImages = [];
  final List<XFile> _pickedVideos = [];
  // Tracks the moderation result for each uploaded media so the
  // user sees the AI score (and the "needs review" message)
  // immediately, before they even tap publish. Keyed by file path
  // because that is the only stable identity we have at upload
  // time.
  final Map<String, MediaAsset> _uploadedMedia = <String, MediaAsset>{};
  final List<_StickerPlacement> _stickers = [];

  String _audience = 'Friends';
  bool _allowComments = true;
  bool _allowReactions = true;
  String _selectedMood = 'Happy';
  bool _isPosting = false;

  List<TrendingTopic> _availableTopics = <TrendingTopic>[];
  static const List<String> _fallbackTopics = <String>[
    'Drawing',
    'Science',
    'Music',
    'Coding',
    'Sports',
    'Story',
    'Math',
    'Reading',
  ];

  final Set<String> _selectedTopics = <String>{};

  @override
  void initState() {
    super.initState();
    _loadTopics();
  }

  Future<void> _loadTopics() async {
    try {
      final List<TrendingTopic> items =
          await PostsApi.instance.trendingTopics(limit: 50);
      if (mounted) {
        setState(() => _availableTopics = items);
      }
    } catch (_) {
      // Use fallback list on error
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_pickedImages.length + _pickedVideos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can attach up to 3 files. Remove one first.'),
        ),
      );
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) {
      return;
    }

    setState(() {
      _pickedImages.add(image);
    });
    // Kick off the AI moderation check right away so the user sees
    // the result as soon as we have it (rather than waiting until
    // they tap "Publish"). We do not block on it — they can keep
    // editing the post body while the upload runs.
    unawaited(_uploadAndCheckMedia(image, isVideo: false));
  }

  Future<void> _pickVideo() async {
    if (_pickedImages.length + _pickedVideos.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can attach up to 3 files. Remove one first.'),
        ),
      );
      return;
    }

    final XFile? video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (video == null) {
      return;
    }

    setState(() {
      _pickedVideos.add(video);
    });
    unawaited(_uploadAndCheckMedia(video, isVideo: true));
  }

  Future<void> _uploadAndCheckMedia(XFile file, {required bool isVideo}) async {
    // Upload runs in the background. The create post screen is
    // still usable while this is in flight; we just need the
    // moderation result before we allow the user to publish.
    try {
      final MediaAsset uploaded = await MediaApi.instance.upload(
        filePath: file.path,
        sourceType: 'OTHER',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _uploadedMedia[file.path] = uploaded;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isVideo
                ? 'Could not check the video for safety: ${error.message}'
                : 'Could not check the image for safety: ${error.message}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isVideo
                ? 'Could not check the video for safety: $error'
                : 'Could not check the image for safety: $error',
          ),
        ),
      );
    }
  }

  /// The create-post screen is shared with two callers, so we keep
  /// the `unawaited` helper in one place.
  void unawaited(Future<void> future) {
    future.then((Object? _) {}, onError: (Object? _, StackTrace? _) {});
  }

  void _addSticker(IconData icon) {
    setState(() {
      _stickers.add(
        _StickerPlacement(icon: icon, position: const Offset(40, 40)),
      );
    });
  }

  void _removeSticker(int index) {
    setState(() {
      _stickers.removeAt(index);
    });
  }

  Future<void> _openMoodPicker() async {
    final String? mood = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => MoodPickerScreen(selectedMood: _selectedMood),
      ),
    );
    if (mood == null) {
      return;
    }

    setState(() {
      _selectedMood = mood;
    });
  }

  Future<void> _submitPost() async {
    final String content = _contentController.text.trim();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (content.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter post content.')),
      );
      return;
    }

    // If the user has attached images but the AI check is still
    // running, wait for it. We give it a short window and fall
    // through if it is taking too long so the user is not stuck.
    await _waitForUploads();

    // Look at the moderation result of every attached image/video.
    // - status == BLOCKED: the AI strongly believes the media is
    //   unsafe → block publishing entirely. The user needs to pick
    //   a different attachment.
    // - thresholdExceeded: the image crossed the safe-publish
    //   threshold. We let the user publish, but they will see a
    //   confirmation dialog explaining that the post will be held
    //   for admin review.
    final List<MediaAsset> flagged = _pickedImages
        .map((file) => _uploadedMedia[file.path])
        .whereType<MediaAsset>()
        .where((asset) => asset.isFlagged)
        .toList();
    final List<MediaAsset> blocked = flagged
        .where((asset) => asset.status == 'BLOCKED')
        .toList();

    if (blocked.isNotEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Bài đăng của bạn chứa hình ảnh không phù hợp và đã bị hệ thống từ chối. Vui lòng chọn hình khác.',
          ),
        ),
      );
      return;
    }

    // ignore: use_build_context_synchronously
    if (flagged.isNotEmpty) {
      final bool? proceed = await showDialog<bool>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Hình ảnh cần admin duyệt'),
          content: const Text(
            'Chúng tôi nghi ngờ bài đăng của bạn có hình ảnh chứa nội dung nhạy cảm. Nếu bạn vẫn muốn đăng, bài viết sẽ được gửi cho admin duyệt trước khi hiển thị trên bảng tin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vẫn đăng'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        return;
      }
    }

    setState(() => _isPosting = true);

    try {
      final created = await PostsApi.instance.createPostAndCheck(
        content: content,
        topics: _selectedTopics.toList(),
        mood: _selectedMood,
        mediaUrls: const <String>[],
        audience: widget.groupId != null
            ? 'GROUP'
            : (_audience == 'Public' ? 'PUBLIC' : 'FRIENDS'),
        allowComments: _allowComments,
        allowReactions: _allowReactions,
        groupId: widget.groupId,
      );
      final FeedPost post = created.post;
      final bool backendNeedsReview = created.needsReview;

      final List<MediaAsset> uploadedMedia = <MediaAsset>[];
      for (final XFile image in _pickedImages) {
        final MediaAsset? cached = _uploadedMedia[image.path];
        if (cached != null) {
          uploadedMedia.add(cached);
        } else {
          uploadedMedia.add(
            await MediaApi.instance.upload(
              filePath: image.path,
              sourceType: 'POST',
              sourceId: post.id,
            ),
          );
        }
      }
      for (final XFile video in _pickedVideos) {
        final MediaAsset? cached = _uploadedMedia[video.path];
        if (cached != null) {
          uploadedMedia.add(cached);
        } else {
          uploadedMedia.add(
            await MediaApi.instance.upload(
              filePath: video.path,
              sourceType: 'POST',
              sourceId: post.id,
            ),
          );
        }
      }

      final List<String> mediaUrls = uploadedMedia
          .map((media) => media.url)
          .where((url) => url.isNotEmpty)
          .toList();

      if (mediaUrls.isNotEmpty) {
        await PostsApi.instance.updatePost(
          postId: post.id,
          mediaUrls: mediaUrls,
        );
      }

      if (!mounted) {
        return;
      }

      // If the post was held for review, surface the "we will let
      // you know" message; otherwise celebrate a normal publish.
      final bool showReviewMessage = flagged.isNotEmpty || backendNeedsReview;
      if (showReviewMessage) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Bài đăng đã được gửi, đang chờ admin duyệt. Bạn sẽ nhận được thông báo khi admin phản hồi.',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Post published.')));
      }

      _finishAfterPublish();
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to publish post: $error')));
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  /// Wait for the in-flight moderation uploads to finish so the
  /// user cannot tap Publish before we know whether the media is
  /// safe. Times out after a few seconds so a stuck upload does
  /// not lock the screen indefinitely.
  Future<void> _waitForUploads() async {
    final List<String> pending = <String>[
      for (final XFile image in _pickedImages) image.path,
      for (final XFile video in _pickedVideos) video.path,
    ].where((path) => !_uploadedMedia.containsKey(path)).toList();
    if (pending.isEmpty) {
      return;
    }
    // Best-effort wait: we do not have a per-file future, so we
    // poll for up to 5s. The moderation service itself usually
    // finishes well under that.
    const Duration tick = Duration(milliseconds: 200);
    const int maxTicks = 25;
    for (int i = 0; i < maxTicks; i++) {
      final bool stillPending = pending.any(
        (path) => !_uploadedMedia.containsKey(path),
      );
      if (!stillPending) {
        return;
      }
      await Future<void>.delayed(tick);
    }
  }

  void _finishAfterPublish() {
    _resetDraft();

    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(true);
      return;
    }

    AppShellNavigator.instance.switchToHome();
  }

  void _resetDraft() {
    _contentController.clear();
    void resetValues() {
      _pickedImages.clear();
      _pickedVideos.clear();
      _stickers.clear();
      _audience = 'Friends';
      _allowComments = true;
      _allowReactions = true;
      _selectedMood = 'Happy';
      _selectedTopics.clear();
    }

    if (mounted) {
      setState(resetValues);
    } else {
      resetValues();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? sessionUser = AuthSession.instance.user;
    final String displayName = (sessionUser?['displayName'] ?? 'User')
        .toString();
    final String initials = displayName.trim().isEmpty
        ? '?'
        : displayName.trim().substring(0, 1).toUpperCase();

    final bool isGroupPost = widget.groupId != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: Text(
          isGroupPost
              ? 'Post in ${widget.groupName ?? 'group'}'
              : 'Create post',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _CardSection(
            title: 'Content',
            subtitle: 'Share something fun today.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: const Color(0xFFBEEBD0),
                      child: Text(initials),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'What would you like to share today?',
                    filled: true,
                    fillColor: const Color(0xFFF6FAFF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _TopicPickerButton(
                  selectedTopics: _selectedTopics,
                  availableTopics: _availableTopics,
                  fallbackTopics: _fallbackTopics,
                  onChanged: (topics) {
                    setState(() => _selectedTopics
                      ..clear()
                      ..addAll(topics));
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ActionPill(
                      label: 'Add photo',
                      icon: Icons.photo_library_rounded,
                      color: const Color(0xFFBEEAFF),
                      onTap: _pickImage,
                    ),
                    _ActionPill(
                      label: 'Add video',
                      icon: Icons.video_library_rounded,
                      color: const Color(0xFFD7C8FF),
                      onTap: _pickVideo,
                    ),
                    _ActionPill(
                      label: 'Add sticker',
                      icon: Icons.emoji_emotions_rounded,
                      color: const Color(0xFFFFC5E6),
                      onTap: () => _addSticker(Icons.star_rounded),
                    ),
                    _ActionPill(
                      label: 'Choose mood',
                      icon: Icons.auto_awesome_rounded,
                      color: const Color(0xFFFFE59E),
                      onTap: _openMoodPicker,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFE59E), Color(0xFFFFC5E6)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.photo, color: Color(0xFF7A2E5A)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Choose a cover image for your post.\nYou can add stickers too!',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A2E5A),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _pickImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7A2E5A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Choose image'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: 'Preview',
            subtitle: 'Images and stickers will appear here.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PreviewCanvas(
                  images: _pickedImages,
                  videos: _pickedVideos,
                  stickers: _stickers,
                  uploadedMedia: _uploadedMedia,
                  onStickerMove: (index, offset) {
                    setState(() {
                      _stickers[index] = _stickers[index].copyWith(
                        position: offset,
                      );
                    });
                  },
                  onStickerRemove: _removeSticker,
                ),
                if (_hasFlaggedAttachment()) _buildMediaReviewWarning(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: 'Mood and stickers',
            subtitle: 'Choose a mood and drag stickers.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _MoodChip(
                      label: 'Happy',
                      selected: _selectedMood == 'Happy',
                      onTap: () => setState(() => _selectedMood = 'Happy'),
                    ),
                    _MoodChip(
                      label: 'Playful',
                      selected: _selectedMood == 'Playful',
                      onTap: () => setState(() => _selectedMood = 'Playful'),
                    ),
                    _MoodChip(
                      label: 'Curious',
                      selected: _selectedMood == 'Curious',
                      onTap: () => setState(() => _selectedMood = 'Curious'),
                    ),
                    _MoodChip(
                      label: 'Creative',
                      selected: _selectedMood == 'Creative',
                      onTap: () => setState(() => _selectedMood = 'Creative'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 82,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _StickerTile(
                        icon: Icons.star_rounded,
                        label: 'Star',
                        onTap: () => _addSticker(Icons.star_rounded),
                      ),
                      _StickerTile(
                        icon: Icons.emoji_emotions,
                        label: 'Smile',
                        onTap: () => _addSticker(Icons.emoji_emotions),
                      ),
                      _StickerTile(
                        icon: Icons.brush_rounded,
                        label: 'Draw',
                        onTap: () => _addSticker(Icons.brush_rounded),
                      ),
                      _StickerTile(
                        icon: Icons.rocket_launch_rounded,
                        label: 'Rocket',
                        onTap: () => _addSticker(Icons.rocket_launch_rounded),
                      ),
                      _StickerTile(
                        icon: Icons.pets_rounded,
                        label: 'Pet',
                        onTap: () => _addSticker(Icons.pets_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: 'Post settings',
            subtitle: isGroupPost
                ? 'Only members of this group can see and reply.'
                : 'Choose who can see this post.',
            child: Column(
              children: [
                if (!isGroupPost)
                  _SelectorTile(
                    title: 'Visibility',
                    value: _audience,
                    options: const ['Friends', 'Public'],
                    onSelected: (value) => setState(() => _audience = value),
                  ),
                SwitchListTile(
                  value: _allowComments,
                  onChanged: (value) => setState(() => _allowComments = value),
                  activeThumbColor: const Color(0xFF33B8FF),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Allow comments',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'People who can see this post can comment.',
                  ),
                ),
                SwitchListTile(
                  value: _allowReactions,
                  onChanged: (value) => setState(() => _allowReactions = value),
                  activeThumbColor: const Color(0xFF33B8FF),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Allow reactions',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'People who can see this post can react with stickers.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isPosting ? null : _submitPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isPosting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Publish post',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }

  /// True when at least one attached image/video has been flagged
  /// by the AI moderation service. Used to surface the "needs
  /// admin review" banner under the preview canvas.
  bool _hasFlaggedAttachment() {
    for (final XFile image in _pickedImages) {
      final MediaAsset? asset = _uploadedMedia[image.path];
      if (asset != null && asset.isFlagged) {
        return true;
      }
    }
    for (final XFile video in _pickedVideos) {
      final MediaAsset? asset = _uploadedMedia[video.path];
      if (asset != null && asset.isFlagged) {
        return true;
      }
    }
    return false;
  }

  Widget _buildMediaReviewWarning() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD591)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shield_outlined,
            color: Color(0xFF874800),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Hình ảnh sẽ được admin duyệt',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF874800),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Chúng tôi nghi ngờ bài đăng của bạn có hình ảnh chứa nội dung nhạy cảm. Bạn vẫn có thể đăng, nhưng admin sẽ xem xét trước khi hiển thị công khai.',
                  style: TextStyle(
                    color: Color(0xFF874800),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCanvas extends StatelessWidget {
  const _PreviewCanvas({
    required this.images,
    required this.videos,
    required this.stickers,
    required this.onStickerMove,
    required this.onStickerRemove,
    this.uploadedMedia = const <String, MediaAsset>{},
  });

  final List<XFile> images;
  final List<XFile> videos;
  final List<_StickerPlacement> stickers;
  final void Function(int index, Offset offset) onStickerMove;
  final void Function(int index) onStickerRemove;
  // Optional map of file path -> moderation result. Used to overlay
  // a small "needs review" badge on flagged media.
  final Map<String, MediaAsset> uploadedMedia;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size size = Size(constraints.maxWidth, 180);

        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF7FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: images.isEmpty
                      ? videos.isEmpty
                            ? const Center(
                                child: Text(
                                  'No image/video yet. Choose a file above.',
                                ),
                              )
                            : _VideoPreviewTile(video: videos.first)
                      : _PickedImagePreview(image: images.first),
                ),
              ),
              for (int i = 0; i < stickers.length; i++)
                _StickerDraggable(
                  key: ValueKey('sticker_$i'),
                  icon: stickers[i].icon,
                  position: stickers[i].position,
                  areaSize: size,
                  onMoved: (offset) => onStickerMove(i, offset),
                  onRemove: () => onStickerRemove(i),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PickedImagePreview extends StatelessWidget {
  const _PickedImagePreview({required this.image});

  final XFile image;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        image.path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Center(child: Text('Cannot preview this image.')),
      );
    }

    return Image.file(File(image.path), fit: BoxFit.cover);
  }
}

class _VideoPreviewTile extends StatelessWidget {
  const _VideoPreviewTile({required this.video});

  final XFile video;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF7FF),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_fill_rounded,
            size: 48,
            color: Color(0xFF33B8FF),
          ),
          const SizedBox(height: 8),
          Text(
            video.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StickerDraggable extends StatelessWidget {
  const _StickerDraggable({
    super.key,
    required this.icon,
    required this.position,
    required this.areaSize,
    required this.onMoved,
    required this.onRemove,
  });

  final IconData icon;
  final Offset position;
  final Size areaSize;
  final ValueChanged<Offset> onMoved;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    const double stickerSize = 36;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          final double newX = (position.dx + details.delta.dx)
              .clamp(0, areaSize.width - stickerSize)
              .toDouble();
          final double newY = (position.dy + details.delta.dy)
              .clamp(0, areaSize.height - stickerSize)
              .toDouble();
          onMoved(Offset(newX, newY));
        },
        onLongPress: onRemove,
        child: Container(
          width: stickerSize,
          height: stickerSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: const Color(0xFF33B8FF)),
        ),
      ),
    );
  }
}

class _StickerPlacement {
  const _StickerPlacement({required this.icon, required this.position});

  final IconData icon;
  final Offset position;

  _StickerPlacement copyWith({IconData? icon, Offset? position}) {
    return _StickerPlacement(
      icon: icon ?? this.icon,
      position: position ?? this.position,
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1A3D7C)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Color(0xFF5A74A6))),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  const _MoodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33B8FF) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF1A3D7C),
          ),
        ),
      ),
    );
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F6FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF33B8FF)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SelectorTile extends StatelessWidget {
  const _SelectorTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: onSelected,
          itemBuilder: (context) {
            return options
                .map(
                  (option) => PopupMenuItem(value: option, child: Text(option)),
                )
                .toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopicPickerButton extends StatefulWidget {
  const _TopicPickerButton({
    required this.selectedTopics,
    required this.availableTopics,
    required this.fallbackTopics,
    required this.onChanged,
  });

  final Set<String> selectedTopics;
  final List<TrendingTopic> availableTopics;
  final List<String> fallbackTopics;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_TopicPickerButton> createState() => _TopicPickerButtonState();
}

class _TopicPickerButtonState extends State<_TopicPickerButton> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _draftSelection = <String>{};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _draftSelection.addAll(widget.selectedTopics);
  }

  @override
  void didUpdateWidget(covariant _TopicPickerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTopics != oldWidget.selectedTopics) {
      _draftSelection.clear();
      _draftSelection.addAll(widget.selectedTopics);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _allTopicStrings {
    if (widget.availableTopics.isNotEmpty) {
      return widget.availableTopics.map((t) => t.topic).toList();
    }
    return widget.fallbackTopics;
  }

  List<String> get _filteredTopics {
    final List<String> source = _allTopicStrings;
    if (_searchQuery.isEmpty) {
      return source;
    }
    return source
        .where((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _openPicker() {
    _draftSelection.clear();
    _draftSelection.addAll(widget.selectedTopics);
    _searchController.clear();
    setState(() => _searchQuery = '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7E7FF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Select Topic',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A3D7C),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          widget.onChanged(Set<String>.from(_draftSelection));
                          Navigator.pop(context);
                        },
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF33B8FF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setSheetState(() => _searchQuery = value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search topics...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF8FA4C7)),
                      filled: true,
                      fillColor: const Color(0xFFF6FAFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_draftSelection.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _draftSelection.map((topic) {
                        return Chip(
                          label: Text(
                            topic,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: const Color(0xFF33B8FF),
                          deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                          onDeleted: () {
                            setSheetState(() => _draftSelection.remove(topic));
                          },
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      }).toList(),
                    ),
                  ),
                if (_draftSelection.isNotEmpty) const SizedBox(height: 12),
                Flexible(
                  child: _filteredTopics.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No topics found.',
                              style: TextStyle(color: Color(0xFF8FA4C7)),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _filteredTopics.length,
                          itemBuilder: (context, index) {
                            final topic = _filteredTopics[index];
                            final isSelected = _draftSelection.contains(topic);
                            return ListTile(
                              onTap: () {
                                setSheetState(() {
                                  if (isSelected) {
                                    _draftSelection.remove(topic);
                                  } else {
                                    _draftSelection.add(topic);
                                  }
                                });
                              },
                              leading: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: isSelected
                                    ? const Color(0xFF33B8FF)
                                    : const Color(0xFFD7E7FF),
                              ),
                              title: Text(
                                topic,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? const Color(0xFF33B8FF)
                                      : const Color(0xFF1A3D7C),
                                ),
                              ),
                              contentPadding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _openPicker,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6FAFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD7E7FF)),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_outline, color: Color(0xFF33B8FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.selectedTopics.isEmpty
                    ? 'Select topic'
                    : widget.selectedTopics.join(', '),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: widget.selectedTopics.isEmpty
                      ? const Color(0xFF8FA4C7)
                      : const Color(0xFF1A3D7C),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.selectedTopics.isNotEmpty)
              Text(
                '${widget.selectedTopics.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF33B8FF),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              color: Color(0xFF8FA4C7),
            ),
          ],
        ),
      ),
    );
  }
}
