import 'package:flutter/material.dart';

class MoodPickerScreen extends StatefulWidget {
  const MoodPickerScreen({super.key, required this.selectedMood});

  final String selectedMood;

  @override
  State<MoodPickerScreen> createState() => _MoodPickerScreenState();
}

class _MoodPickerScreenState extends State<MoodPickerScreen> {
  late String _mood;

  final List<String> _moods = const [
    'Happy',
    'Dua nghich',
    'To mo',
    'Sang tao',
    'Proud',
    'Tinh nghich',
  ];

  @override
  void initState() {
    super.initState();
    _mood = widget.selectedMood;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'Choose mood',
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
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _moods.map((item) {
              final bool selected = _mood == item;
              return GestureDetector(
                onTap: () => setState(() => _mood = item),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF33B8FF)
                        : const Color(0xFFEFF4FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    item,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF1A3D7C),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _mood),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Choose mood',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
