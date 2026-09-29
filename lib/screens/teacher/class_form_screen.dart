import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/class_provider.dart';
import '../../routes/app_routes.dart';
import '../../themes/app_text_styles.dart';

/// Create a class, or edit one when [existing] is given.
class ClassFormScreen extends StatefulWidget {
  const ClassFormScreen({super.key, this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends State<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.existing?['name']?.toString(),
  );
  late final _subject = TextEditingController(
    text: widget.existing?['subject']?.toString(),
  );
  late final _section = TextEditingController(
    text: widget.existing?['section']?.toString(),
  );
  late final _description = TextEditingController(
    text: widget.existing?['description']?.toString(),
  );
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _subject, _section, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final provider = context.read<ClassProvider>();
    try {
      if (_editing) {
        final updated = await provider.service.update(
          widget.existing!['id'].toString(),
          name: _name.text.trim(),
          subject: _opt(_subject),
          section: _opt(_section),
          description: _opt(_description),
        );
        await provider.refresh();
        if (mounted) Navigator.pop(context, updated);
      } else {
        final created = await provider.create(
          name: _name.text.trim(),
          subject: _opt(_subject),
          section: _opt(_section),
          description: _opt(_description),
        );
        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.classDetails,
            arguments: created,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit class' : 'New class')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                _editing ? 'Class details' : 'Create a class',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: 6),
              const Text(
                'Students join with the code you get next. Exams, attendance and announcements belong to a class.',
                style: AppTextStyles.bodySecondary,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Class name',
                  hintText: 'e.g. Class 9 A',
                  prefixIcon: Icon(Icons.groups_2_outlined),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a class name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subject,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Subject (optional)',
                  hintText: 'e.g. Physics',
                  prefixIcon: Icon(Icons.menu_book_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _section,
                decoration: const InputDecoration(
                  labelText: 'Section / session (optional)',
                  hintText: 'e.g. Morning shift, 2026',
                  prefixIcon: Icon(Icons.bookmark_border),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(_editing ? 'Save changes' : 'Create class'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
