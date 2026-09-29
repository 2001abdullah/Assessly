import 'package:assessly/models/user_model.dart';
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/widgets/auth_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Email/password and Google sign-in for the chosen [role]. Students can
/// also use the username a teacher created for them.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.role = UserRole.teacher});

  final UserRole role;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _finish(Future<void> Function() authenticate) async {
    try {
      await authenticate();
      if (!mounted) return;
      final mustChange =
          context.read<AuthProvider>().user?.mustChangePassword ?? false;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (_) => false);
      // Teacher-issued temporary password: ask for a new one right away.
      if (mustChange) {
        Navigator.pushNamed(context, AppRoutes.changePassword, arguments: true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _login() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    await _finish(
      () => context.read<AuthProvider>().login(
        emailController.text.trim(),
        passwordController.text,
        widget.role,
      ),
    );
  }

  Future<void> _googleLogin() =>
      _finish(() => context.read<AuthProvider>().loginWithGoogle(widget.role));

  bool get _student => widget.role == UserRole.student;

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;
    return AuthLayout(
      badge: _student ? 'Student sign in' : 'Teacher sign in',
      title: 'Welcome back',
      subtitle: _student
          ? 'Sign in to see your results, progress and attendance.'
          : 'Sign in to manage your classes, exams and results.',
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GoogleAuthButton(
                loading: loading,
                onPressed: loading ? null : _googleLogin,
              ),
              const SizedBox(height: 22),
              const AuthDivider(),
              const SizedBox(height: 22),
              TextFormField(
                controller: emailController,
                enabled: !loading,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                decoration: InputDecoration(
                  labelText: _student ? 'Email or username' : 'Email address',
                  helperText: _student
                      ? 'Use the username from your teacher if you were given one'
                      : null,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final login = value?.trim() ?? '';
                  // Teacher-created student logins are usernames, not emails.
                  if (_student && login.isNotEmpty && !login.contains('@')) {
                    return null;
                  }
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(login)) {
                    return _student
                        ? 'Enter your email or username'
                        : 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                enabled: !loading,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => loading ? null : _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (value) =>
                    (value?.isEmpty ?? true) ? 'Enter your password' : null,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.pushNamed(
                          context,
                          AppRoutes.forgotPassword,
                        ),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: loading ? null : _login,
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
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: loading
                        ? null
                        : () => Navigator.pushNamed(
                            context,
                            AppRoutes.register,
                            arguments: widget.role,
                          ),
                    child: const Text('Create account'),
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
