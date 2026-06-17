import 'package:flutter/material.dart';

import '../../core/models/public_user.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/users_api.dart';
import '../safety/community_rules_screen.dart';
import '../safety/report_violation_screen.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _allowFriendRequests = true;
  bool _allowComments = true;
  bool _safeSearchOnly = true;

  @override
  void initState() {
    super.initState();
    _loadPrivacy();
  }

  Future<void> _loadPrivacy() async {
    setState(() => _isLoading = true);

    try {
      final PublicUser user = await UsersApi.instance.getMe();
      if (!mounted) {
        return;
      }
      setState(() {
        _allowFriendRequests = user.privacy.allowFriendRequests;
        _allowComments = user.privacy.allowComments;
        _safeSearchOnly = user.privacy.safeSearchOnly;
      });
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
      ).showSnackBar(SnackBar(content: Text('Load privacy failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePrivacy() async {
    setState(() => _isSaving = true);

    try {
      await UsersApi.instance.updateMe(
        privacy: <String, dynamic>{
          'allowFriendRequests': _allowFriendRequests,
          'allowComments': _allowComments,
          'safeSearchOnly': _safeSearchOnly,
        },
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Privacy settings saved.')));
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
      ).showSnackBar(SnackBar(content: Text('Save privacy failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _setAndSave(void Function() update) {
    setState(update);
    _savePrivacy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      appBar: AppBar(
        title: const Text(
          'Privacy & Safety',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A3D7C),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPrivacy,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _SectionCard(
                    title: 'Connections',
                    description:
                        'These settings are saved to your backend profile.',
                    child: Column(
                      children: [
                        _SwitchTile(
                          title: 'Allow friend requests',
                          subtitle: 'New people can send you friend requests.',
                          value: _allowFriendRequests,
                          onChanged: (value) =>
                              _setAndSave(() => _allowFriendRequests = value),
                        ),
                        _SwitchTile(
                          title: 'Allow comments',
                          subtitle: 'Friends can comment on your posts.',
                          value: _allowComments,
                          onChanged: (value) =>
                              _setAndSave(() => _allowComments = value),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Safety tools',
                    description: 'Extra protection for age-safe search.',
                    child: Column(
                      children: [
                        _SwitchTile(
                          title: 'Safe search only',
                          subtitle:
                              'Prefer content that matches your safety settings.',
                          value: _safeSearchOnly,
                          onChanged: (value) =>
                              _setAndSave(() => _safeSearchOnly = value),
                        ),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CommunityRulesScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1A3D7C),
                            side: const BorderSide(
                              color: Color(0xFFBEEAFF),
                              width: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.block),
                          label: const Text('Community rules'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Your controls',
                    description: 'Report a safety problem to moderation.',
                    child: _ActionTile(
                      icon: Icons.report_gmailerrorred_rounded,
                      title: 'Report a problem',
                      subtitle: 'Tell us if something feels wrong.',
                      color: const Color(0xFFFFE59E),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ReportViolationScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
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
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A3D7C),
            ),
          ),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: Color(0xFF5A74A6))),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: const Color(0xFF33B8FF),
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: const Color(0xFF1A3D7C)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
    );
  }
}
