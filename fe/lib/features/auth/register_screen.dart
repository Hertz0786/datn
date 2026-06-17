import 'package:flutter/material.dart';

import '../../app/app_shell.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/auth_api.dart';
import '../onboarding/topic_preferences_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isSubmitting = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _ageController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String displayName = _displayNameController.text.trim();
    final String username = _usernameController.text.trim();
    final String ageText = _ageController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (displayName.isEmpty ||
        username.isEmpty ||
        ageText.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields.')),
      );
      return;
    }

    final int? age = int.tryParse(ageText);
    if (age == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Age must be a valid number.')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password confirmation does not match.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthApi.instance.register(
        displayName: displayName,
        username: username,
        age: age,
        password: password,
      );

      if (!mounted) {
        return;
      }

      // First-time users always go through topic selection so the backend
      // can drive the feed and search from the first session.
      await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => TopicPreferencesScreen(
            initialTopics: const <String>[],
            isFirstTime: true,
          ),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) {
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Register failed. Please try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundStart = Color(0xFFFFF1E6);
    const backgroundEnd = Color(0xFFE8F7FF);
    const primary = Color(0xFF33B8FF);
    const accent = Color(0xFFFF9AD5);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [backgroundStart, backgroundEnd],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Create account',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A3D7C),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Welcome, new friend!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A3D7C),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create an account to connect and share fun moments.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: Color(0xFF3A5A8A),
                  ),
                ),
                const SizedBox(height: 20),
                _InputField(
                  controller: _displayNameController,
                  label: 'Display name',
                  hint: 'little_star',
                  icon: Icons.face_rounded,
                  color: primary,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'kiddo_123',
                  icon: Icons.alternate_email,
                  color: accent,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _ageController,
                  label: 'Age',
                  hint: '8',
                  icon: Icons.cake_rounded,
                  color: primary,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: '********',
                  icon: Icons.lock_outline,
                  color: primary,
                  obscure: true,
                ),
                const SizedBox(height: 14),
                _InputField(
                  controller: _confirmPasswordController,
                  label: 'Confirm password',
                  hint: '********',
                  icon: Icons.lock_outline,
                  color: accent,
                  obscure: true,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Get started',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.favorite_border,
                        color: Color(0xFF1A3D7C),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'You can update your privacy settings anytime.',
                          style: TextStyle(
                            color: Color(0xFF2A4474),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatefulWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    this.obscure = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  State<_InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<_InputField> {
  final FocusNode _focusNode = FocusNode();
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _hideHint();
    }
  }

  void _hideHint() {
    if (_hasInteracted) {
      return;
    }
    setState(() {
      _hasInteracted = true;
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscure,
          focusNode: _focusNode,
          onTap: _hideHint,
          decoration: InputDecoration(
            hintText: _hasInteracted ? null : widget.hint,
            prefixIcon: Icon(widget.icon, color: widget.color),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
