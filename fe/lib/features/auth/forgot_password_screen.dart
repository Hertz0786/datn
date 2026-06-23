import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/auth_api.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isSubmitting = false;
  bool _isSendingCode = false;
  bool _codeSent = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() {
      _countdownSeconds = seconds;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        timer.cancel();
      }
    });
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty && index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (_otpControllers.every((c) => c.text.isNotEmpty)) {
      FocusScope.of(context).unfocus();
    }
    setState(() {});
  }

  void _onOtpKey(String value, int index) {
    if (value.isEmpty && index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  String get _otpCode =>
      _otpControllers.map((c) => c.text).join();

  Future<void> _sendResetCode() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address.')),
      );
      return;
    }

    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      await AuthApi.instance.sendPasswordResetCode(email: email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCountdown(60);
      _otpFocusNodes[0].requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reset code sent. Check your email.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (_otpCode.length < 6 || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }
    if (password != confirmPassword) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match.')));
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthApi.instance.resetPassword(
        email: email,
        code: _otpCode,
        password: password,
      );

      if (!mounted) {
        _isSubmitting = false;
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successfully.')),
      );
      Navigator.pop(context);
    } on ApiException catch (error) {
      if (!mounted) {
        _isSubmitting = false;
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) {
        _isSubmitting = false;
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF33B8FF);
    const accent = Color(0xFFFF9AD5);
    const titleColor = Color(0xFF1A3D7C);

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
                        'Enter your email and we will send you a code to reset your password.',
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

              // --- Email section ---
              _EmailField(
                controller: _emailController,
                label: 'Email Address',
                hint: 'yourname@example.com',
                icon: Icons.alternate_email_rounded,
                color: titleColor,
                isSendingCode: _isSendingCode,
                countdownSeconds: _countdownSeconds,
                onSendCode: _sendResetCode,
              ),

              // --- OTP boxes ---
              if (_codeSent) ...[
                const SizedBox(height: 20),
                _buildOtpSection(primary),
              ],

              // --- Password fields ---
              if (_codeSent) ...[
                const SizedBox(height: 18),
                _PasswordField(
                  controller: _passwordController,
                  label: 'New password',
                  hint: '********',
                  icon: Icons.lock_outline_rounded,
                  color: titleColor,
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm new password',
                  hint: '********',
                  icon: Icons.lock_reset_rounded,
                  color: titleColor,
                ),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSubmitting || _isSendingCode
                    ? null
                    : (_codeSent ? _resetPassword : _sendResetCode),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _codeSent ? accent : primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting || _isSendingCode
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _codeSent ? 'Reset Password' : 'Send Reset Code',
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

  Widget _buildOtpSection(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reset code',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) {
            return Container(
              width: 46,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: color.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A3D7C),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) => _onOtpChanged(value, index),
                onSubmitted: (_) => _onOtpKey('', index),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _countdownSeconds > 0
                  ? 'Resend in ${_countdownSeconds}s'
                  : 'Didn\'t receive the code?',
              style: TextStyle(
                fontSize: 12,
                color: _countdownSeconds > 0
                    ? color.withValues(alpha: 0.6)
                    : const Color(0xFF3A5A8A),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_countdownSeconds <= 0) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _sendResetCode,
                child: Text(
                  'Resend',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EmailField extends StatefulWidget {
  const _EmailField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    required this.isSendingCode,
    required this.countdownSeconds,
    required this.onSendCode,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final bool isSendingCode;
  final int countdownSeconds;
  final VoidCallback onSendCode;

  @override
  State<_EmailField> createState() => _EmailFieldState();
}

class _EmailFieldState extends State<_EmailField> {
  final FocusNode _focusNode = FocusNode();
  bool _hasInteracted = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) _hideHint();
  }

  void _hideHint() {
    if (_hasInteracted) return;
    setState(() => _hasInteracted = true);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool canSend = widget.controller.text.trim().isNotEmpty;

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
          focusNode: _focusNode,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onTap: _hideHint,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: _hasInteracted ? null : widget.hint,
            prefixIcon: Icon(widget.icon, color: widget.color),
            suffixIcon: widget.countdownSeconds <= 0
                ? canSend
                    ? IconButton(
                        onPressed: widget.isSendingCode
                            ? null
                            : widget.onSendCode,
                        icon: widget.isSendingCode
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded, size: 20),
                      )
                    : const SizedBox.shrink()
                : Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.countdownSeconds}s',
                      style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: color),
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
      ],
    );
  }
}
