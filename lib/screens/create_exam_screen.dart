import 'package:assessly/providers/class_provider.dart';
import 'package:assessly/providers/exam_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Form for a new exam: class, title, subject, question count and ID digit
/// counts. Opened from a class, that class is preselected.
class CreateExamScreen extends StatefulWidget {
  const CreateExamScreen({super.key, this.classData});

  final Map<String, dynamic>? classData;

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  late final subjectController = TextEditingController(
    text: widget.classData?['subject']?.toString(),
  );
  int selectedQuestionCount = 25;
  int selectedRollDigits = 7;
  int selectedRegistrationDigits = 10;
  late String? selectedClassId = widget.classData?['id']?.toString();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ClassProvider>().load(),
    );
  }

  Future<void> createExam() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    try {
      // Added through the provider so the home screen and exam list update.
      final exam = await context.read<ExamProvider>().create(
        title: titleController.text.trim(),
        subject: subjectController.text.trim(),
        totalQuestions: selectedQuestionCount,
        rollDigits: selectedRollDigits,
        registrationDigits: selectedRegistrationDigits,
        classId: selectedClassId,
      );

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.examDetails,
        arguments: exam,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    subjectController.dispose();
    super.dispose();
  }

  String? _required(String? value, String field) =>
      (value == null || value.trim().isEmpty) ? 'Enter the $field' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New exam')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Create a new exam', style: AppTextStyles.heading),
                const SizedBox(height: 6),
                const Text(
                  'You can add the answer key and scoring rules next.',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 28),
                Builder(
                  builder: (context) {
                    final classes = context.watch<ClassProvider>().classes;
                    final ids = classes.map((c) => c['id'].toString()).toSet();
                    return DropdownButtonFormField<String?>(
                      initialValue: ids.contains(selectedClassId)
                          ? selectedClassId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Class',
                        helperText: 'Results are matched to the class students by roll number',
                        prefixIcon: Icon(Icons.groups_2_outlined),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No class'),
                        ),
                        for (final c in classes)
                          DropdownMenuItem<String?>(
                            value: c['id'].toString(),
                            child: Text(c['name'].toString()),
                          ),
                      ],
                      onChanged: (v) => setState(() => selectedClassId = v),
                    );
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: titleController,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => _required(v, 'exam title'),
                  decoration: const InputDecoration(
                    labelText: 'Exam title',
                    hintText: 'e.g. Mid-term Physics',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: subjectController,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => _required(v, 'subject'),
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    hintText: 'e.g. Physics',
                    prefixIcon: Icon(Icons.menu_book_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Number of questions',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final count in const [25, 50, 75, 100])
                      ChoiceChip(
                        label: Text('$count'),
                        selected: selectedQuestionCount == count,
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selectedQuestionCount == count
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        onSelected: (_) =>
                            setState(() => selectedQuestionCount = count),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const Text(
                  'Candidate identifiers',
                  style: AppTextStyles.subtitle,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose how many digit columns are printed on the OMR sheet.',
                  style: AppTextStyles.bodySecondary,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedRollDigits,
                        decoration: const InputDecoration(
                          labelText: 'Roll digits',
                          prefixIcon: Icon(Icons.pin_outlined),
                        ),
                        items: [
                          for (int value = 1; value <= 14; value++)
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            selectedRollDigits = value;
                            if (selectedRollDigits +
                                    selectedRegistrationDigits >
                                26) {
                              selectedRegistrationDigits =
                                  26 - selectedRollDigits;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedRegistrationDigits,
                        decoration: const InputDecoration(
                          labelText: 'Registration digits',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        items: [
                          for (
                            int value = 0;
                            value <= 16 && value + selectedRollDigits <= 26;
                            value++
                          )
                            DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedRegistrationDigits = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                FilledButton(
                  onPressed: isLoading ? null : createExam,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create exam'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
