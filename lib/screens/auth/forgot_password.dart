import 'package:assessly/services/api_service.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';

/// Two-step password reset: request an emailed 6-digit code, then set a new password.
class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final passwordController = TextEditingController();
  bool codeSent = false;
  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final email = emailController.text.trim();
      if (codeSent) {
        await ApiService.resetPassword(
          email: email,
          code: codeController.text.trim(),
          password: passwordController.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset. You can now sign in.')),
        );
        Navigator.pop(context);
      } else {
        await ApiService.requestPasswordReset(email);
        if (!mounted) return;
        setState(() => codeSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('If the account exists, a reset code was emailed.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 60),
            Text('Reset password', style: AppTextStyles.title),
            const SizedBox(height: 12),
            Text(
              codeSent
                  ? 'Enter the six-digit code from your email and choose a new password.'
                  : 'Enter your email to receive a six-digit reset code.',
              style: AppTextStyles.body,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: emailController,
              enabled: !codeSent && !loading,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.email_outlined),
                labelText: 'Email',
              ),
            ),
            if (codeSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.pin_outlined),
                  labelText: 'Reset code',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline),
                  labelText: 'New password (8+ characters)',
                ),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: loading
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(codeSent ? 'Reset password' : 'Send reset code'),
            ),
          ],
        ),
      ),
    );
  }
}
