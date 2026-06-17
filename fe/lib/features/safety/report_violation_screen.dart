import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/safety_api.dart';

class ReportViolationScreen extends StatefulWidget {
  const ReportViolationScreen({super.key, this.targetType, this.targetId});

  final String? targetType;
  final String? targetId;

  @override
  State<ReportViolationScreen> createState() => _ReportViolationScreenState();
}

class _ReportViolationScreenState extends State<ReportViolationScreen> {
  final TextEditingController _detailsController = TextEditingController();

  final List<String> _categories = const [
    'Bullying',
    'Unsafe content',
    'Private info sharing',
    'Spam',
    'Other',
  ];

  String _selectedCategory = 'Bullying';
  String _selectedWhere = 'Post';
  double _urgency = 2;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final String? targetType = widget.targetType;
    if (targetType != null && targetType.trim().isNotEmpty) {
      _selectedWhere = targetType.trim();
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (_isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await SafetyApi.instance.submitReport(
        targetType: _selectedWhere.toUpperCase(),
        targetId: widget.targetId?.trim().isNotEmpty == true
            ? widget.targetId!.trim()
            : 'general',
        category: _selectedCategory,
        details: _detailsController.text.trim(),
        urgency: _urgency.round(),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Report sent. Thank you for helping keep the app safe.',
          ),
        ),
      );
      Navigator.pop(context);
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
      ).showSnackBar(SnackBar(content: Text('Send report failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        title: const Text(
          'Report Violation',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF7FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'Your report is private. A trusted safety team will review it.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A3D7C),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'What happened?',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _categories.map((item) {
                final bool selected = item == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF33B8FF)
                          : const Color(0xFFEFF4FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      item,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF1A3D7C),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Where did it happen?',
            child: Row(
              children: [
                Expanded(
                  child: _PickButton(
                    label: 'Post',
                    selected: _selectedWhere == 'Post',
                    onTap: () => setState(() => _selectedWhere = 'Post'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickButton(
                    label: 'Comment',
                    selected: _selectedWhere == 'Comment',
                    onTap: () => setState(() => _selectedWhere = 'Comment'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PickButton(
                    label: 'Chat',
                    selected: _selectedWhere == 'Chat',
                    onTap: () => setState(() => _selectedWhere = 'Chat'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'How urgent is this?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _urgency >= 4 ? 'High urgency' : 'Normal urgency',
                  style: const TextStyle(color: Color(0xFF5A74A6)),
                ),
                Slider(
                  min: 1,
                  max: 5,
                  divisions: 4,
                  value: _urgency,
                  activeColor: const Color(0xFF33B8FF),
                  onChanged: (value) => setState(() => _urgency = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Card(
            title: 'Details',
            child: TextField(
              controller: _detailsController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Explain what happened in simple words...',
                filled: true,
                fillColor: const Color(0xFFF5F9FF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReport,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF33B8FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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
                : const Text(
                    'Send Report',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
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
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF33B8FF) : const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(14),
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
