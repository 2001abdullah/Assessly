import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../themes/app_text_styles.dart';
import '../../widgets/file_export.dart';

/// Change (or, for Google-only accounts, set) the password. With [forced]
/// (teacher-issued temporary password) the current password is not asked
/// for again, since the user just signed in with it.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forced = false});

  final bool forced;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().changePassword(
        current: _current.text,
        next: _next.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password updated')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final needsCurrent = (user?.hasPassword ?? true);
    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(
          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    );

    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: Text(needsCurrent ? 'Change password' : 'Set a password'),
          automaticallyImplyLeading: !widget.forced,
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                if (widget.forced) ...[
                  const Text(
                    'Choose your own password',
                    style: AppTextStyles.heading,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'You signed in with a temporary password from your teacher. Pick a new one to continue.',
                    style: AppTextStyles.bodySecondary,
                  ),
                  const SizedBox(height: 24),
                ],
                if (needsCurrent) ...[
                  TextFormField(
                    controller: _current,
                    obscureText: _obscure,
                    decoration: field(
                      widget.forced ? 'Temporary password' : 'Current password',
                    ),
                    validator: (v) => (v ?? '').isEmpty
                        ? 'Enter your current password'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _next,
                  obscureText: _obscure,
                  decoration: field('New password'),
                  validator: (v) =>
                      (v ?? '').length < 8 ? 'Use at least 8 characters' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: field('Confirm new password'),
                  validator: (v) =>
                      v != _next.text ? 'Passwords do not match' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
