import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:assessly/services/exam_service.dart';


class ExamDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> exam;
  const ExamDetailsScreen({super.key, required this.exam});

  Future<void> _generateSheet(BuildContext context) async {
    try {
      final bytes = await ExamService().downloadOmrSheet(exam['id'].toString());
      final path = await FilePicker.saveFile(
        dialogTitle: 'Save OMR sheet',
        fileName: '${exam['title']}-omr.pdf',
        bytes: bytes,
      );
      if (context.mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $path')));
      }
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exam['title'],
                style: AppTextStyles.heading,
              ),

              const SizedBox(height: 8),

              Text(
                exam['subject'],
                style: AppTextStyles.bodySecondary,
              ),

              const SizedBox(height: 24),

              // exam summary will go here

              const SizedBox(height: 32),

              Text(
                'Manage Exam',
                style: AppTextStyles.title,
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.answerKey,
                      arguments: exam,
                    );
                  },
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Answer Key'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.scoringRules,
                      arguments: exam,
                    );
                  },
                  icon: const Icon(Icons.rule_outlined),
                  label: const Text('Scoring Rules'),
                ),
              ),
              // Scan OMR
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.scanOmr,
                      arguments: exam,
                    );
                  },
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Scan OMR'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => _generateSheet(context),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generate OMR Sheet'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    AppRoutes.studentResults,
                    arguments: exam,
                  ),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Student Results'),
                ),
              ),
              // Results
            ],
          ),
        ),
      ),
    );
  }
}
