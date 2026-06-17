import 'package:flutter/material.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/auth_api.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final FocusNode _accountFocusNode = FocusNode();
  bool _isSubmitting = false;
  bool _hasInteracted = false;
  bool _resetMode = false;

  @override
  void dispose() {
    _accountController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _accountFocusNode.dispose();
    super.dispose();
  }

  void _hideHint() {
    if (_hasInteracted) {
      return;
    }
    setState(() => _hasInteracted = true);
  }

  Future<void> _submit() async {
    final String account = _accountController.text.trim();
    if (account.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email or username.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final String? resetToken = await AuthApi.instance.requestPasswordReset(
        username: account,
      );

      if (!mounted) {
        return;
      }

      if (resetToken != null && resetToken.isNotEmpty) {
        _tokenController.text = resetToken;
      }

      setState(() => _resetMode = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reset token has been created.')),
      );
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
      ).showSnackBar(SnackBar(content: Text('Reset request failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final String username = _accountController.text.trim();
    final String token = _tokenController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty || token.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter username, token, password.'),
        ),
      );
      return;
    }
    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthApi.instance.resetPassword(
        username: username,
        token: token,
        password: password,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successfully.')),
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
      ).showSnackBar(SnackBar(content: Text('Reset password failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF33B8FF);
    const Color titleColor = Color(0xFF1A3D7C);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      appBar: AppBar(
        title: const Text(
          'Forgot Password',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A3D7C)),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -50,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF9BE7FF).withValues(alpha: 0.35),
              ),
            ),
          ),
          Positioned(
            left: -25,
            bottom: 80,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFD6EF).withValues(alpha: 0.45),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9BE7FF), Color(0xFFFFD9F0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.lock_reset_rounded,
                        color: titleColor,
                        size: 26,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enter your email or username and we will send you instructions to reset your password.',
                        style: TextStyle(
                          color: Color(0xFF1E3C77),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Email or Username',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2A4474),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _accountController,
                focusNode: _accountFocusNode,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onTap: _hideHint,
                onSubmitted: (_) => _isSubmitting ? null : _submit(),
                decoration: InputDecoration(
                  hintText: _hasInteracted ? null : 'yourname@example.com',
                  prefixIcon: const Icon(
                    Icons.alternate_email_rounded,
                    color: titleColor,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_resetMode) ...[
                const Text(
                  'Reset Token',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A4474),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  decoration: _inputDecoration(
                    hint: 'Paste reset token',
                    icon: Icons.key_rounded,
                    titleColor: titleColor,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: _inputDecoration(
                    hint: 'New password',
                    icon: Icons.lock_outline_rounded,
                    titleColor: titleColor,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: _inputDecoration(
                    hint: 'Confirm new password',
                    icon: Icons.lock_reset_rounded,
                    titleColor: titleColor,
                  ),
                ),
                const SizedBox(height: 18),
              ],
              ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : (_resetMode ? _resetPassword : _submit),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _isSubmitting
                      ? 'Sending...'
                      : (_resetMode ? 'Reset Password' : 'Send Recovery Link'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Remember your password? Back to sign in',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required Color titleColor,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: titleColor),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }
}
