import 'package:flutter/material.dart';

import '../../core/models/user_photo.dart';
import '../../core/services/photos_api.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../../shared/widgets/loading_state_view.dart';
import '../feed/post_detail_screen.dart';

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key, this.initialPhotos});

  final List<UserPhoto>? initialPhotos;

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  bool _isLoading = true;
  List<UserPhoto> _photos = const <UserPhoto>[];

  @override
  void initState() {
    super.initState();
    if (widget.initialPhotos != null) {
      _photos = widget.initialPhotos!;
      _isLoading = false;
    }
    if (_photos.isEmpty) {
      _loadPhotos();
    }
  }

  Future<void> _loadPhotos() async {
    setState(() => _isLoading = true);

    try {
      final List<UserPhoto> items = await PhotosApi.instance.myPhotos();
      if (!mounted) {
        return;
      }
      setState(() => _photos = items);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openPhoto(UserPhoto photo) {
    if (photo.postId == null || photo.postId!.isEmpty) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(postId: photo.postId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'Photo Gallery',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
      ),
      body: RefreshIndicator(
        onRefresh: _loadPhotos,
        child: _isLoading
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [LoadingStateView(title: 'Loading photos...')],
              )
            : _photos.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  EmptyStateView(
                    icon: Icons.photo_library_outlined,
                    title: 'No photos yet',
                    message: 'Add image URLs when creating posts.',
                  ),
                ],
              )
            : GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _photos.length,
                itemBuilder: (context, index) {
                  final UserPhoto photo = _photos[index];
                  return InkWell(
                    onTap: () => _openPhoto(photo),
                    borderRadius: BorderRadius.circular(16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            photo.url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFEFF7FF),
                              alignment: Alignment.center,
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              color: Colors.black.withValues(alpha: 0.45),
                              child: Text(
                                photo.caption.isEmpty
                                    ? photo.sourceType
                                    : photo.caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
