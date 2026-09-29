import 'package:assessly/models/user_model.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/widgets/auth_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Creates a password account with [role], then returns to Login.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key, this.role = UserRole.teacher});

  final UserRole role;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  bool obscurePassword = true;
  bool obscureConfirm = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _showError(Object error) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
    );
  }

  Future<void> _googleRegister() async {
    try {
      await context.read<AuthProvider>().loginWithGoogle(widget.role);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
    } catch (error) {
      await _showError(error);
    }
  }

  Future<void> _register() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    try {
      await context.read<AuthProvider>().register(
        nameController.text.trim(),
        emailController.text.trim(),
        passwordController.text,
        widget.role,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Sign in to continue.')),
      );
      Navigator.pop(context);
    } catch (error) {
      await _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;
    final student = widget.role == UserRole.student;
    return AuthLayout(
      badge: student ? 'Student account' : 'Teacher account',
      title: 'Create your account',
      subtitle: student
          ? 'Then join your class with the code your teacher gives you.'
          : 'Set up classes, exams and grading in minutes.',
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoogleAuthButton(
                loading: loading,
                onPressed: loading ? null : _googleRegister,
              ),
              const SizedBox(height: 22),
              const AuthDivider(),
              const SizedBox(height: 22),
              TextFormField(
                controller: nameController,
                enabled: !loading,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => (value?.trim().length ?? 0) < 2
                    ? 'Enter your full name'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: emailController,
                enabled: !loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) =>
                    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Enter a valid email address',
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: passwordController,
                label: 'Password (8+ characters)',
                obscure: obscurePassword,
                onToggle: () =>
                    setState(() => obscurePassword = !obscurePassword),
                validator: (value) => (value?.length ?? 0) < 8
                    ? 'Use at least 8 characters'
                    : null,
              ),
              const SizedBox(height: 14),
              _PasswordField(
                controller: confirmController,
                label: 'Confirm password',
                obscure: obscureConfirm,
                onToggle: () =>
                    setState(() => obscureConfirm = !obscureConfirm),
                validator: (value) => value != passwordController.text
                    ? 'Passwords do not match'
                    : null,
                onSubmitted: (_) => loading ? null : _register(),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: loading ? null : _register,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Create account'),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Already registered?'),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.pushReplacementNamed(
                            context,
                            AppRoutes.login,
                            arguments: widget.role,
                          ),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggle,
    required this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?) validator;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: obscure,
    textInputAction: onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    autofillHints: const [AutofillHints.newPassword],
    onFieldSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        onPressed: onToggle,
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: validator,
  );
}
