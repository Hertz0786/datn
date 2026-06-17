import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/media_api.dart';
import '../../core/services/users_api.dart';
import '../../core/session/auth_session.dart';
import '../../shared/widgets/user_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final PublicUser user;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _topicsController;
  late final TextEditingController _avatarUrlController;
  late final TextEditingController _coverUrlController;

  final ImagePicker _picker = ImagePicker();
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;
  bool _isSaving = false;

  // Track the avatar URL as separate state so changing it does not require
  // the user to also touch the TextField, and the avatar preview can rebuild
  // deterministically when the value changes.
  String _avatarUrl = '';
  String _coverUrl = '';

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.user.displayName,
    );
    _bioController = TextEditingController(text: widget.user.bio);
    _topicsController = TextEditingController(
      text: widget.user.favoriteTopics.join(', '),
    );
    _avatarUrl = widget.user.avatarUrl;
    _coverUrl = widget.user.coverUrl;
    _avatarUrlController = TextEditingController(text: _avatarUrl);
    _coverUrlController = TextEditingController(text: _coverUrl);
    _avatarUrlController.addListener(_handleAvatarUrlChanged);
    _coverUrlController.addListener(_handleCoverUrlChanged);
  }

  @override
  void dispose() {
    _avatarUrlController.removeListener(_handleAvatarUrlChanged);
    _coverUrlController.removeListener(_handleCoverUrlChanged);
    _displayNameController.dispose();
    _bioController.dispose();
    _topicsController.dispose();
    _avatarUrlController.dispose();
    _coverUrlController.dispose();
    super.dispose();
  }

  void _handleAvatarUrlChanged() {
    final String next = _avatarUrlController.text.trim();
    if (next != _avatarUrl) {
      setState(() => _avatarUrl = next);
    }
  }

  void _handleCoverUrlChanged() {
    final String next = _coverUrlController.text.trim();
    if (next != _coverUrl) {
      setState(() => _coverUrl = next);
    }
  }

  bool _looksLikeUrl(String value) {
    final String v = value.trim();
    if (v.isEmpty) {
      return true;
    }
    final Uri? uri = Uri.tryParse(v);
    if (uri == null) {
      return false;
    }
    return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _pickAvatar({required ImageSource source}) async {
    if (_isUploadingAvatar) {
      return;
    }
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 82,
    );
    if (image == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isUploadingAvatar = true);

    try {
      final media = await MediaApi.instance.upload(
        filePath: image.path,
        sourceType: 'PROFILE',
      );
      if (!mounted) {
        return;
      }
      _avatarUrlController.text = media.url;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo uploaded.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  Future<void> _pickCover({required ImageSource source}) async {
    if (_isUploadingCover) {
      return;
    }
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 84,
    );
    if (image == null) {
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() => _isUploadingCover = true);

    try {
      final media = await MediaApi.instance.upload(
        filePath: image.path,
        sourceType: 'PROFILE_COVER',
      );
      if (!mounted) {
        return;
      }
      _coverUrlController.text = media.url;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cover photo uploaded.')));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isUploadingCover = false);
      }
    }
  }

  Future<void> _showAvatarSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Update profile photo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a new photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(source: ImageSource.camera);
              },
            ),
            if (_avatarUrl.isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove current photo',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _avatarUrlController.clear();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCoverSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Update cover photo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCover(source: ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a new photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCover(source: ImageSource.camera);
              },
            ),
            if (_coverUrl.isNotEmpty)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Remove current cover',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _coverUrlController.clear();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final String displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name cannot be empty.')),
      );
      return;
    }
    final String avatarUrl = _avatarUrlController.text.trim();
    if (!_looksLikeUrl(avatarUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avatar URL must be a valid http(s) link.'),
        ),
      );
      return;
    }
    final String coverUrl = _coverUrlController.text.trim();
    if (!_looksLikeUrl(coverUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover URL must be a valid http(s) link.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final PublicUser user = await UsersApi.instance.updateMe(
        displayName: displayName,
        bio: _bioController.text.trim(),
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
        favoriteTopics: _parseTopics(_topicsController.text),
      );

      await AuthSession.instance.updateUser(<String, dynamic>{
        'id': user.id,
        'displayName': user.displayName,
        'username': user.username,
        'age': user.age,
        'role': user.role,
        'avatarUrl': user.avatarUrl,
        'coverUrl': user.coverUrl,
        'bio': user.bio,
        'favoriteTopics': user.favoriteTopics,
        'privacy': user.privacy.toJson(),
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save profile failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<String> _parseTopics(String raw) {
    return raw
        .split(',')
        .map((String item) => item.trim())
        .where((String item) => item.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'Edit profile',
          style: TextStyle(
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
          _CoverPicker(
            coverUrl: _coverUrl,
            isUploading: _isUploadingCover,
            onTap: _isUploadingCover ? null : _showCoverSheet,
          ),
          const SizedBox(height: 12),
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                UserAvatar(
                  avatarUrl: _avatarUrl,
                  initials: widget.user.initials,
                  radius: 50,
                  backgroundColor: const Color(0xFFBEEBD0),
                ),
                Material(
                  color: const Color(0xFF33B8FF),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _isUploadingAvatar ? null : _showAvatarSheet,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: _isUploadingAvatar
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _isUploadingAvatar ? null : _showAvatarSheet,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Change photo'),
                ),
                TextButton.icon(
                  onPressed: _isUploadingCover ? null : _showCoverSheet,
                  icon: const Icon(Icons.panorama_rounded, size: 18),
                  label: const Text('Change cover'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _InputCard(
            label: 'Display name',
            icon: Icons.person_outline,
            controller: _displayNameController,
          ),
          const SizedBox(height: 12),
          _ReadOnlyCard(
            label: 'Age',
            value: widget.user.age > 0 ? '${widget.user.age}' : 'Not set',
            icon: Icons.cake_rounded,
          ),
          const SizedBox(height: 12),
          _InputCard(
            label: 'Favorite topics',
            icon: Icons.palette_rounded,
            controller: _topicsController,
            hint: 'Drawing, Music, Coding',
          ),
          const SizedBox(height: 12),
          _InputCard(
            label: 'Short bio',
            icon: Icons.edit_note_rounded,
            controller: _bioController,
            hint: 'I like drawing colorful pictures.',
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSaving || _isUploadingAvatar || _isUploadingCover
                ? null
                : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Save changes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CoverPicker extends StatelessWidget {
  const _CoverPicker({
    required this.coverUrl,
    required this.isUploading,
    required this.onTap,
  });

  final String coverUrl;
  final bool isUploading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 142,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverUrl.trim().isEmpty)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF9BE7FF), Color(0xFFFFD6EC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.panorama_rounded,
                    size: 42,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
              )
            else
              Image.network(
                coverUrl.trim(),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFC6E2FF),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isUploading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(
                        Icons.camera_alt_rounded,
                        size: 16,
                        color: Color(0xFF1A3D7C),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      isUploading ? 'Uploading' : 'Cover',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.maxLines = 1,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF33B8FF)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFFF6FAFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF33B8FF)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Color(0xFF7A8BBF))),
        ],
      ),
    );
  }
}
