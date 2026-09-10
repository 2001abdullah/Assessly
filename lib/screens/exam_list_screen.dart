import 'package:flutter/material.dart';

import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/services/exam_service.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';

class ExamListScreen extends StatefulWidget {
  const ExamListScreen({super.key});

  @override
  State<ExamListScreen> createState() => _ExamListScreenState();
}

class _ExamListScreenState extends State<ExamListScreen> {
  final ExamService _examService = ExamService();

  List<Map<String, dynamic>> exams = [];

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  // --------------------------------------------------
  // Load Exams
  // --------------------------------------------------

  Future<void> _loadExams() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedExams = await _examService.getExams();

      if (!mounted) return;

      setState(() {
        exams = loadedExams;
        isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage = error.toString();
      });
    }
  }

  // --------------------------------------------------
  // Confirm Delete
  // --------------------------------------------------

  Future<void> _confirmDeleteExam(
      Map<String, dynamic> exam,
      ) async {
    final examId = exam['id']?.toString();

    if (examId == null || examId.isEmpty) {
      return;
    }

    final title =
        exam['title']?.toString() ?? 'this exam';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Exam?'),

          content: Text(
            'Are you sure you want to delete "$title"?\n\n'
                'This action cannot be undone.',
          ),

          actions: [
            // Cancel
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),

            // Delete
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    // User cancelled
    if (confirmed != true) {
      return;
    }

    // --------------------------------------------------
    // Delete Exam
    // --------------------------------------------------

    try {
      await _examService.deleteExam(examId);

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"$title" deleted successfully.',
          ),
        ),
      );

      // Reload exam list
      await _loadExams();
    } catch (error) {
      if (!mounted) return;

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to delete exam: $error',
          ),
        ),
      );
    }
  }

  // --------------------------------------------------
  // Build
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Exams'),
      ),

      body: _buildBody(),

      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.pushNamed(
            context,
            AppRoutes.createNewExam,
          );

          // Reload exams after returning
          _loadExams();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // --------------------------------------------------
  // Body
  // --------------------------------------------------

  Widget _buildBody() {
    // --------------------------------------------------
    // Loading
    // --------------------------------------------------

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // --------------------------------------------------
    // Error
    // --------------------------------------------------

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 60,
              ),

              const SizedBox(height: 16),

              Text(
                'Failed to load exams',
                style: AppTextStyles.title,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                errorMessage!,
                style: AppTextStyles.bodySecondary,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _loadExams,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    // --------------------------------------------------
    // Empty
    // --------------------------------------------------

    if (exams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 64,
                color: AppColors.textSecondary,
              ),

              const SizedBox(height: 16),

              Text(
                'No exams yet',
                style: AppTextStyles.title,
              ),

              const SizedBox(height: 8),

              Text(
                'Create your first exam to get started.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySecondary,
              ),

              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.pushNamed(
                    context,
                    AppRoutes.createNewExam,
                  );

                  _loadExams();
                },
                icon: const Icon(Icons.add),
                label: const Text('Create Exam'),
              ),
            ],
          ),
        ),
      );
    }

    // --------------------------------------------------
    // Exam List
    // --------------------------------------------------

    return RefreshIndicator(
      onRefresh: _loadExams,

      child: ListView.builder(
        padding: const EdgeInsets.all(16),

        itemCount: exams.length,

        itemBuilder: (context, index) {
          final exam = exams[index];

          final title =
              exam['title']?.toString() ?? 'Untitled Exam';

          final subject =
              exam['subject']?.toString() ?? 'No subject';

          final totalQuestions =
              exam['total_questions']?.toString() ?? '0';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),

            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),

              // --------------------------------------------------
              // Exam Icon
              // --------------------------------------------------

              leading: CircleAvatar(
                backgroundColor: AppColors.primary,
                child: const Icon(
                  Icons.description_outlined,
                  color: Colors.white,
                ),
              ),

              // --------------------------------------------------
              // Exam Title
              // --------------------------------------------------

              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

              // --------------------------------------------------
              // Subject + Questions
              // --------------------------------------------------

              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '$subject • $totalQuestions questions',
                ),
              ),

              // --------------------------------------------------
              // Delete Button
              // --------------------------------------------------

              trailing: IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),

                tooltip: 'Delete exam',

                onPressed: () {
                  _confirmDeleteExam(exam);
                },
              ),

              // --------------------------------------------------
              // Open Exam Details
              // --------------------------------------------------

              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.examDetails,
                  arguments: exam,
                );
              },
            ),
          );
        },
      ),
    );
  }
}