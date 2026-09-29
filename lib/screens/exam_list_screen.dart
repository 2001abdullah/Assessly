import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:assessly/providers/exam_provider.dart';
import 'package:assessly/providers/results_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/widgets/app_widgets.dart';
import 'package:assessly/widgets/exam_card.dart';

/// All of the user's exams (from ExamProvider), with delete.
class ExamListScreen extends StatefulWidget {
  const ExamListScreen({super.key});

  @override
  State<ExamListScreen> createState() => _ExamListScreenState();
}

class _ExamListScreenState extends State<ExamListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ExamProvider>().load(force: true),
    );
  }

  // --------------------------------------------------
  // Confirm Delete
  // --------------------------------------------------

  Future<void> _confirmDeleteExam(Map<String, dynamic> exam) async {
    final examId = exam['id']?.toString();
    if (examId == null || examId.isEmpty) return;

    final title = exam['title']?.toString() ?? 'this exam';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
        title: const Text('Delete exam?'),
        content: Text(
          '"$title" and all of its answer keys and results will be '
          'permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // The provider removes the exam from every screen (home included).
    final messenger = ScaffoldMessenger.of(context);
    final results = context.read<ResultsProvider>();
    try {
      await context.read<ExamProvider>().delete(examId);
      results.removeExam(examId);
      messenger.showSnackBar(SnackBar(content: Text('"$title" deleted.')));
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete exam: $error')),
      );
    }
  }

  // --------------------------------------------------
  // Build
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExamProvider>();
    final results = context.watch<ResultsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Your exams')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.createNewExam),
        icon: const Icon(Icons.add),
        label: const Text('New exam'),
      ),
      body: _buildBody(provider, results),
    );
  }

  Widget _buildBody(ExamProvider provider, ResultsProvider results) {
    final exams = provider.exams;

    if (provider.isLoading && exams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null && exams.isEmpty) {
      return ErrorState(
        message: provider.error!,
        onRetry: () => provider.load(force: true),
      );
    }

    if (exams.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No exams yet',
            message: 'Create your first exam to get started.',
            action: FilledButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.createNewExam),
              icon: const Icon(Icons.add),
              label: const Text('Create exam'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.load(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        itemCount: exams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final exam = exams[index];
          return ExamCard(
            exam: exam,
            gradedCount: results.resultsFor(exam['id'].toString())?.length,
            onDelete: () => _confirmDeleteExam(exam),
          );
        },
      ),
    );
  }
}
