import 'package:flutter/material.dart';

import '../../core/models/community_rule.dart';
import '../../core/services/safety_api.dart';
import 'report_violation_screen.dart';

class CommunityRulesScreen extends StatefulWidget {
  const CommunityRulesScreen({super.key});

  @override
  State<CommunityRulesScreen> createState() => _CommunityRulesScreenState();
}

class _CommunityRulesScreenState extends State<CommunityRulesScreen> {
  bool _isLoading = true;
  List<CommunityRule> _rules = const <CommunityRule>[];

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);

    try {
      final List<CommunityRule> rules = await SafetyApi.instance.getRules();
      if (!mounted) {
        return;
      }
      setState(() => _rules = rules);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rules = const <CommunityRule>[
          CommunityRule(
            id: 'kindness',
            title: 'Be kind in every message',
            description: 'No teasing, bullying, or mean nicknames.',
          ),
          CommunityRule(
            id: 'private-info',
            title: 'Keep private info safe',
            description:
                'Do not share phone numbers, school names, or address.',
          ),
          CommunityRule(
            id: 'age-safe',
            title: 'Share age-friendly content',
            description: 'Posts must be safe for kids from 7 to 14.',
          ),
          CommunityRule(
            id: 'respect',
            title: 'Respect everyone\'s boundaries',
            description: 'Stop if someone says no or asks for space.',
          ),
        ];
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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
          'Community Rules',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadRules,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFE59E), Color(0xFFFFC5E6)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.shield_rounded,
                    size: 30,
                    color: Color(0xFF7A2E5A),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Our community is made for kindness, learning, and fun.',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7A2E5A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ..._rules.map(
                (CommunityRule rule) => _RuleTile(
                  icon: _ruleIcon(rule.id),
                  color: _ruleColor(rule.id),
                  title: rule.title,
                  description: rule.description,
                ),
              ),
            const SizedBox(height: 16),
            Container(
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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What happens after a report?',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A3D7C),
                    ),
                  ),
                  SizedBox(height: 8),
                  _StepText(
                    index: 1,
                    text: 'Safety team checks the report quickly.',
                  ),
                  _StepText(
                    index: 2,
                    text: 'Content can be hidden while reviewing.',
                  ),
                  _StepText(
                    index: 3,
                    text: 'Serious cases can lead to account limits.',
                  ),
                  _StepText(
                    index: 4,
                    text: 'You get a notification about the result.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.tips_and_updates_rounded,
                    color: Color(0xFF33B8FF),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'If something feels unsafe, trust your feeling and report it.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A3D7C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportViolationScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF33B8FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.report_gmailerrorred_rounded),
              label: const Text(
                'Report a Violation',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _ruleIcon(String id) {
    switch (id) {
      case 'kindness':
        return Icons.favorite_rounded;
      case 'private-info':
        return Icons.lock_rounded;
      case 'age-safe':
        return Icons.no_adult_content_rounded;
      case 'respect':
        return Icons.verified_user_rounded;
      default:
        return Icons.rule_rounded;
    }
  }

  Color _ruleColor(String id) {
    switch (id) {
      case 'kindness':
        return const Color(0xFFFFD9E9);
      case 'private-info':
        return const Color(0xFFD4EDFF);
      case 'age-safe':
        return const Color(0xFFFFF0BA);
      case 'respect':
        return const Color(0xFFCFF4DE);
      default:
        return const Color(0xFFE7ECFF);
    }
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFF1A3D7C)),
          ),
          const SizedBox(width: 10),
          Expanded(
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
                const SizedBox(height: 4),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  const _StepText({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF33B8FF),
            ),
          ),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
