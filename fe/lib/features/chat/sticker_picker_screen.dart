import 'package:flutter/material.dart';

/// Catalog of supported sticker codes that get embedded as message content.
const Map<String, IconData> kStickerIconCatalog = <String, IconData>{
  'sticker:star': Icons.star_rounded,
  'sticker:smile': Icons.emoji_emotions,
  'sticker:pets': Icons.pets_rounded,
  'sticker:rocket': Icons.rocket_launch_rounded,
  'sticker:cake': Icons.cake_rounded,
  'sticker:music': Icons.music_note_rounded,
};

const Map<String, String> kStickerLabels = <String, String>{
  'sticker:star': 'Star',
  'sticker:smile': 'Smile',
  'sticker:pets': 'Pets',
  'sticker:rocket': 'Rocket',
  'sticker:cake': 'Cake',
  'sticker:music': 'Music',
};

bool isStickerCode(String content) {
  final String trimmed = content.trim();
  return kStickerIconCatalog.containsKey(trimmed);
}

IconData? iconForSticker(String content) {
  return kStickerIconCatalog[content.trim()];
}

class StickerPickerScreen extends StatelessWidget {
  const StickerPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, IconData>> stickers =
        kStickerIconCatalog.entries.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'Choose sticker',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: stickers.length,
        itemBuilder: (context, index) {
          final entry = stickers[index];
          return InkWell(
            onTap: () => Navigator.pop(context, entry.key),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEFF4FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(entry.value, color: const Color(0xFF33B8FF), size: 36),
                  const SizedBox(height: 8),
                  Text(
                    kStickerLabels[entry.key] ?? entry.key,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
