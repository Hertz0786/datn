import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/auth_api.dart';

/// In-app change-password flow for an already-signed-in child.
///
/// Steps:
/// 1. Fetch the verified email tied to this account.
/// 2. Show that email so the child can tell a parent where to look.
/// 3. Send an OTP to that email via the existing forgot-password
///    endpoint.
/// 4. The child enters the OTP (delivered to the parent's mailbox)
///    plus a new password to complete the reset.
///
/// The OTP is never read out loud by the app — only the email
/// address is shown, which is necessary so a parent knows which inbox
/// to check. Passwords are kept in memory only and never logged.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 60;

  // Phase machine:
  //   loading → (ready | noEmail)
  //   ready → (sending → codeSent → submitting → done)
  //                    ↘ resendCountdown
  _Phase _phase = _Phase.loading;

  String? _accountEmail;
  bool _isSendingCode = false;
  bool _isSubmitting = false;
  int _resendCountdown = 0;
  Timer? _countdownTimer;
  String? _errorMessage;

  final List<TextEditingController> _otpControllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    _loadAccountEmail();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountEmail() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
    });

    try {
      final String? email = await AuthApi.instance.getMyEmail();
      if (!mounted) return;
      if (email == null) {
        setState(() => _phase = _Phase.noEmail);
      } else {
        setState(() {
          _accountEmail = email;
          _phase = _Phase.ready;
        });
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.noEmail;
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.noEmail;
        _errorMessage = 'Could not load account email: $error';
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = _resendCooldownSeconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCountdown--);
      if (_resendCountdown <= 0) {
        timer.cancel();
      }
    });
  }

  Future<void> _sendOtp() async {
    final String? email = _accountEmail;
    if (email == null) {
      return;
    }
    setState(() => _isSendingCode = true);

    try {
      await AuthApi.instance.sendPasswordResetCode(email: email);
      if (!mounted) return;
      _startCountdown();
      _otpFocusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code sent to $email. Ask a parent to check it.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send code: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSendingCode = false);
    }
  }

  void _onOtpChanged(String value, int index) {
    if (value.isNotEmpty && index < _otpLength - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    if (_otpControllers.every((c) => c.text.isNotEmpty)) {
      FocusScope.of(context).unfocus();
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final String? email = _accountEmail;
    final String code = _otpCode;
    final String password = _newPasswordController.text;
    final String confirm = _confirmPasswordController.text;

    if (email == null) return;

    if (code.length < _otpLength) {
      _showError('Please enter the 6-digit code your parent received.');
      return;
    }
    if (password.isEmpty) {
      _showError('Please type a new password.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must have at least 6 characters.');
      return;
    }
    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await AuthApi.instance.resetPassword(
        email: email,
        code: code,
        password: password,
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } catch (error) {
      if (!mounted) return;
      _showError('Could not change password: $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const titleColor = Color(0xFF1A3D7C);
    const primary = Color(0xFF33B8FF);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      appBar: AppBar(
        title: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: titleColor),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const _LoadingBody(),
          _Phase.noEmail => _NoEmailBody(
              errorMessage: _errorMessage,
              onRetry: _loadAccountEmail,
            ),
          _Phase.done => const _DoneBody(),
          _ => _readyBody(primary: primary, titleColor: titleColor),
        },
      ),
    );
  }

  Widget _readyBody({
    required Color primary,
    required Color titleColor,
  }) {
    final String email = _accountEmail ?? '';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9BE7FF), Color(0xFFFFD9F0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.lock_reset_rounded,
                  color: titleColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A code will be sent to:',
                      style: TextStyle(
                        color: Color(0xFF1E3C77),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      email,
                      style: const TextStyle(
                        color: Color(0xFF1A3D7C),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ask a parent to open that email and read the 6-digit code to you.',
                      style: TextStyle(
                        color: Color(0xFF1E3C77),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _isSendingCode || _isSubmitting ? null : _sendOtp,
            icon: _isSendingCode
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _resendCountdown > 0
                  ? 'Send code (wait ${_resendCountdown}s)'
                  : 'Send code to email',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        _OtpSection(
          controllers: _otpControllers,
          focusNodes: _otpFocusNodes,
          primary: primary,
          countdown: _resendCountdown,
          onChanged: _onOtpChanged,
          onResend: _isSendingCode ? null : _sendOtp,
        ),
        const SizedBox(height: 22),
        _PasswordField(
          controller: _newPasswordController,
          label: 'New password',
          icon: Icons.lock_outline_rounded,
          color: titleColor,
        ),
        const SizedBox(height: 14),
        _PasswordField(
          controller: _confirmPasswordController,
          label: 'Confirm new password',
          icon: Icons.lock_reset_rounded,
          color: titleColor,
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: (_isSubmitting || _isSendingCode) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9AD5),
            foregroundColor: Colors.white,
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
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}

enum _Phase { loading, ready, noEmail, done }

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _NoEmailBody extends StatelessWidget {
  const _NoEmailBody({this.errorMessage, required this.onRetry});

  final String? errorMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(
          Icons.alternate_email_rounded,
          size: 56,
          color: Color(0xFF33B8FF),
        ),
        const SizedBox(height: 12),
        const Text(
          'No email on this account',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF1A3D7C),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          errorMessage ??
              'To change your password we need to send a code to the email on this account. Ask a parent to add an email first, then try again.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF3A5A8A), height: 1.4),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _DoneBody extends StatelessWidget {
  const _DoneBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const Icon(
          Icons.check_circle_rounded,
          size: 72,
          color: Color(0xFF34C759),
        ),
        const SizedBox(height: 12),
        const Text(
          'Password changed!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Color(0xFF1A3D7C),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use your new password next time you log in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF3A5A8A), height: 1.4),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF33B8FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Back to settings',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

typedef _OtpChangedCallback = void Function(String value, int index);

class _OtpSection extends StatelessWidget {
  const _OtpSection({
    required this.controllers,
    required this.focusNodes,
    required this.primary,
    required this.countdown,
    required this.onChanged,
    required this.onResend,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final Color primary;
  final int countdown;
  final _OtpChangedCallback onChanged;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Code from email',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A4474),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(controllers.length, (index) {
            return Container(
              width: 46,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
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
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) => onChanged(value, index),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.center,
          child: Text(
            countdown > 0
                ? 'You can resend in ${countdown}s'
                : 'Didn\'t get the code?',
            style: TextStyle(
              fontSize: 12,
              color: countdown > 0
                  ? primary.withValues(alpha: 0.6)
                  : const Color(0xFF3A5A8A),
              fontWeight: FontWeight.w500,
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
    required this.icon,
    required this.color,
  });

  final TextEditingController controller;
  final String label;
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