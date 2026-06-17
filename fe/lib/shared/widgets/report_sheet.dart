import 'package:flutter/material.dart';

import '../../core/services/safety_api.dart';

/// Common bottom-sheet for reporting content (POST / COMMENT).
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    this.title = 'Report content',
    this.description = 'Tell us why this should be reviewed.',
  });

  final String targetType;
  final String targetId;
  final String title;
  final String description;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  static const List<MapEntry<String, String>> _categories =
      <MapEntry<String, String>>[
    MapEntry<String, String>('BULLYING', 'Bullying or harassment'),
    MapEntry<String, String>('UNSAFE_CONTENT', 'Unsafe or age-inappropriate'),
    MapEntry<String, String>('PRIVATE_INFO', 'Sharing private information'),
    MapEntry<String, String>('SPAM', 'Spam or scam'),
    MapEntry<String, String>('OTHER', 'Something else'),
  ];

  String _category = 'BULLYING';
  final TextEditingController _detailsController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await SafetyApi.instance.submitReport(
        targetType: widget.targetType,
        targetId: widget.targetId,
        category: _category,
        details: _detailsController.text.trim(),
        urgency: _category == 'PRIVATE_INFO' ? 4 : 2,
      );
      if (!mounted) {
        return;
      }
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E6F5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A3D7C),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.description,
              style: const TextStyle(color: Color(0xFF5A74A6)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((entry) {
                final bool selected = entry.key == _category;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: selected,
                  selectedColor: const Color(0xFF33B8FF),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF1A3D7C),
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: const Color(0xFFEFF4FF),
                  onSelected: _isSubmitting
                      ? null
                      : (_) {
                          setState(() => _category = entry.key);
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Add more context (optional)...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFE2536F)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _isSubmitting ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF33B8FF),
                      foregroundColor: Colors.white,
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Submit report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showReportSheet({
  required BuildContext context,
  required String targetType,
  required String targetId,
  String title = 'Report content',
  String description = 'Tell us why this should be reviewed.',
}) async {
  final bool? result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => ReportSheet(
      targetType: targetType,
      targetId: targetId,
      title: title,
      description: description,
    ),
  );
  return result == true;
}
