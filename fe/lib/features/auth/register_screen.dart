import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shell.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/auth_api.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  DateTime? _selectedDate;

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
    _displayNameController.dispose();
    _usernameController.dispose();
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

  Future<void> _sendVerificationCode() async {
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
      await AuthApi.instance.sendVerificationCode(email: email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCountdown(60);
      _otpFocusNodes[0].requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code sent. Check your email.'),
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
      ).showSnackBar(SnackBar(content: Text('Failed to send code: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  String get _otpCode =>
      _otpControllers.map((c) => c.text).join();

  Future<void> _submit() async {
    final String displayName = _displayNameController.text.trim();
    final String username = _usernameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;
    final String confirmPassword = _confirmPasswordController.text;

    if (displayName.isEmpty ||
        username.isEmpty ||
        _selectedDate == null ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields.')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password confirmation does not match.')),
      );
      return;
    }

    if (email.isNotEmpty && !_codeSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please send a verification code first.')),
      );
      return;
    }

    if (email.isNotEmpty && _otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the full verification code.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthApi.instance.register(
        displayName: displayName,
        username: username,
        birthDate: _selectedDate!,
        password: password,
        email: email.isNotEmpty ? email : null,
        verificationCode: email.isNotEmpty ? _otpCode : null,
      );

      if (!mounted) {
        _isSubmitting = false;
        return;
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
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
                const SizedBox(height: 24),

                // --- Email section ---
                _EmailSection(
                  controller: _emailController,
                  label: 'Email',
                  hint: 'parent@example.com',
                  icon: Icons.email_outlined,
                  color: primary,
                  isSendingCode: _isSendingCode,
                  countdownSeconds: _countdownSeconds,
                  onSendCode: _sendVerificationCode,
                ),

                // --- OTP boxes (always visible after code sent) ---
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  _buildOtpSection(primary),
                ],

                const SizedBox(height: 16),
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
                _buildBirthDateField(primary),
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
                  child: const Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        color: Color(0xFF1A3D7C),
                      ),
                      SizedBox(width: 8),
                      Expanded(
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

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final earliest = DateTime(now.year - 14);
    final latest = DateTime(now.year - 7, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? earliest,
      firstDate: DateTime(now.year - 14),
      lastDate: latest,
      helpText: 'Select your birthday',
      cancelText: 'Cancel',
      confirmText: 'Confirm',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF33B8FF),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A3D7C),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Widget _buildBirthDateField(Color color) {
    final bool hasDate = _selectedDate != null;
    final String displayText = hasDate
        ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of birth',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _selectBirthDate,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 16,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.cake_rounded, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    hasDate ? displayText : 'Select your birthday',
                    style: TextStyle(
                      fontSize: 16,
                      color: hasDate
                          ? const Color(0xFF1A3D7C)
                          : const Color(0xFF3A5A8A),
                      fontWeight:
                          hasDate ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  color: color,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpSection(Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verification code',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(6, (index) {
            return _OtpBox(
              controller: _otpControllers[index],
              focusNode: _otpFocusNodes[index],
              onChanged: (value) => _onOtpChanged(value, index),
              onSubmitted: (_) => _onOtpKey('', index),
            );
          }),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _countdownSeconds > 0
                  ? 'Resend in ${_countdownSeconds}s'
                  : 'Didn\'t receive the code?',
              style: TextStyle(
                fontSize: 13,
                color: _countdownSeconds > 0
                    ? color.withValues(alpha: 0.6)
                    : const Color(0xFF3A5A8A),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (_countdownSeconds <= 0) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _sendVerificationCode,
                child: Text(
                  'Resend',
                  style: TextStyle(
                    fontSize: 13,
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

class _OtpBox extends StatefulWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<_OtpBox> createState() => _OtpBoxState();
}

class _OtpBoxState extends State<_OtpBox> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = widget.focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 50,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isFocused
              ? const Color(0xFF33B8FF)
              : const Color(0xFF33B8FF).withValues(alpha: 0.3),
          width: _isFocused ? 2.5 : 1.5,
        ),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF33B8FF).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0xFF33B8FF).withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1A3D7C),
          letterSpacing: 2,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: '',
          contentPadding: EdgeInsets.symmetric(vertical: 16),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _EmailSection extends StatelessWidget {
  const _EmailSection({
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
  Widget build(BuildContext context) {
    final bool canSend = controller.text.trim().isNotEmpty;

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
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: color),
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
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (!canSend || isSendingCode || countdownSeconds > 0)
                ? null
                : onSendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: canSend && countdownSeconds <= 0
                  ? const Color(0xFF33B8FF)
                  : const Color(0xFF33B8FF).withValues(alpha: 0.4),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF33B8FF).withValues(alpha: 0.2),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
              elevation: canSend && countdownSeconds <= 0 ? 4 : 0,
              shadowColor: const Color(0xFF33B8FF).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: isSendingCode
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (countdownSeconds > 0) ...[
                        const Icon(Icons.mail_outline_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Resend in ${countdownSeconds}s',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              canSend
                                  ? Icons.send_rounded
                                  : Icons.email_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              canSend
                                  ? 'Send verification code'
                                  : 'Enter email to send code',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
        ),
      ],
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
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final bool obscure;

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
